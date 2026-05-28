package com.lanlink.app

import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanlink/android_apps")
            .setMethodCallHandler { call, result ->
                if (call.method != "listApps") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                result.success(listLaunchableApps())
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanlink/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareFiles") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val paths = call.argument<List<String>>("paths").orEmpty()
                result.success(shareFiles(paths))
            }

        val notifier = TransferNotifier(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanlink/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showProgress" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val title = call.argument<String>("title").orEmpty()
                        val text = call.argument<String>("text").orEmpty()
                        val progress = call.argument<Int>("progress") ?: 0
                        val max = call.argument<Int>("max") ?: 100
                        val indeterminate = call.argument<Boolean>("indeterminate") ?: false
                        notifier.showProgress(id, title, text, progress, max, indeterminate)
                        result.success(true)
                    }
                    "showFinal" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val title = call.argument<String>("title").orEmpty()
                        val text = call.argument<String>("text").orEmpty()
                        val success = call.argument<Boolean>("success") ?: false
                        notifier.showFinal(id, title, text, success)
                        result.success(true)
                    }
                    "cancel" -> {
                        val id = call.argument<Int>("id") ?: 0
                        notifier.cancel(id)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanlink/received_files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                        result.success(true)
                    }
                    "publishToDownloads" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val fileName = call.argument<String>("fileName")
                        if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.error(
                                "ARGS",
                                "publishToDownloads requires sourcePath + fileName",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val published = publishToDownloads(sourcePath, fileName)
                            result.success(published)
                        } catch (e: Exception) {
                            result.error("PUBLISH_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun listLaunchableApps(): List<Map<String, Any>> {
        val pm = packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN, null).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcherIntent, 0).mapNotNull { resolveInfo ->
            val packageName = resolveInfo.activityInfo.packageName
            val appInfo = try {
                pm.getApplicationInfo(packageName, 0)
            } catch (_: PackageManager.NameNotFoundException) {
                return@mapNotNull null
            }
            val source = appInfo.publicSourceDir ?: appInfo.sourceDir ?: return@mapNotNull null
            val apk = File(source)
            if (!apk.exists()) return@mapNotNull null
            mapOf(
                "label" to pm.getApplicationLabel(appInfo).toString(),
                "packageName" to packageName,
                "apkPath" to apk.absolutePath,
                "size" to apk.length(),
            )
        }.distinctBy { it["packageName"] as String }
    }

    private fun shareFiles(paths: List<String>): Boolean {
        if (paths.isEmpty()) return false
        val uris = ArrayList<Uri>()
        for (path in paths) {
            val file = File(path)
            if (!file.exists()) continue
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            uris.add(uri)
        }
        if (uris.isEmpty()) return false
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "*/*"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "Share with LanLink"))
        return true
    }

    /**
     * Publishes a finished file into the user-visible `Downloads/LanLink`
     * directory. On Android 10+ this goes through MediaStore (no extra
     * permission required for files this app inserts itself). On older
     * Android we copy directly into the public Downloads folder and ping
     * the media scanner.
     *
     * Returns a human-readable destination path that can be shown to the
     * user (e.g. `Download/LanLink/photo.jpg`) on success, or null on
     * failure.
     */
    private fun publishToDownloads(sourcePath: String, fileName: String): String? {
        val source = File(sourcePath)
        if (!source.exists()) return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            publishViaMediaStore(source, fileName)
        } else {
            publishViaLegacyPath(source, fileName)
        }
    }

    private fun publishViaMediaStore(source: File, fileName: String): String? {
        val resolver = contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val displayName = uniqueDisplayName(fileName) { candidate ->
            isDisplayNameTaken(resolver, candidate)
        }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.MIME_TYPE, mimeTypeFor(displayName))
            put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/LanLink")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val itemUri = resolver.insert(collection, values) ?: return null
        try {
            resolver.openOutputStream(itemUri).use { out ->
                if (out == null) return null
                FileInputStream(source).use { input ->
                    input.copyTo(out)
                }
            }
            val finalize = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            resolver.update(itemUri, finalize, null, null)
            return "${Environment.DIRECTORY_DOWNLOADS}/LanLink/$displayName"
        } catch (e: Exception) {
            try {
                resolver.delete(itemUri, null, null)
            } catch (_: Exception) {
            }
            throw e
        }
    }

    private fun publishViaLegacyPath(source: File, fileName: String): String? {
        @Suppress("DEPRECATION")
        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val targetDir = File(downloads, "LanLink")
        if (!targetDir.exists() && !targetDir.mkdirs()) return null
        val target = uniqueFile(targetDir, fileName)
        source.inputStream().use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), null, null)
        return target.absolutePath
    }

    private fun uniqueDisplayName(
        original: String,
        taken: (String) -> Boolean,
    ): String {
        if (!taken(original)) return original
        val dotIndex = original.lastIndexOf('.')
        val base = if (dotIndex > 0) original.substring(0, dotIndex) else original
        val ext = if (dotIndex > 0) original.substring(dotIndex) else ""
        var i = 1
        while (true) {
            val candidate = "$base ($i)$ext"
            if (!taken(candidate)) return candidate
            i++
            if (i > 9999) return "$base-${System.currentTimeMillis()}$ext"
        }
    }

    private fun isDisplayNameTaken(
        resolver: android.content.ContentResolver,
        displayName: String,
    ): Boolean {
        val projection = arrayOf(MediaStore.Downloads._ID)
        val selection =
            "${MediaStore.Downloads.DISPLAY_NAME}=? AND ${MediaStore.Downloads.RELATIVE_PATH}=?"
        val args = arrayOf(displayName, "${Environment.DIRECTORY_DOWNLOADS}/LanLink/")
        return resolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            args,
            null,
        )?.use { it.count > 0 } ?: false
    }

    private fun uniqueFile(dir: File, fileName: String): File {
        var candidate = File(dir, fileName)
        if (!candidate.exists()) return candidate
        val dotIndex = fileName.lastIndexOf('.')
        val base = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
        val ext = if (dotIndex > 0) fileName.substring(dotIndex) else ""
        var i = 1
        while (true) {
            candidate = File(dir, "$base ($i)$ext")
            if (!candidate.exists()) return candidate
            i++
            if (i > 9999) return File(dir, "$base-${System.currentTimeMillis()}$ext")
        }
    }

    private fun mimeTypeFor(fileName: String): String {
        val dotIndex = fileName.lastIndexOf('.')
        if (dotIndex < 0 || dotIndex == fileName.length - 1) return "application/octet-stream"
        val ext = fileName.substring(dotIndex + 1).lowercase()
        return when (ext) {
            "apk" -> "application/vnd.android.package-archive"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "mp4" -> "video/mp4"
            "mov" -> "video/quicktime"
            "mkv" -> "video/x-matroska"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/x-wav"
            "ogg" -> "audio/ogg"
            "flac" -> "audio/flac"
            "pdf" -> "application/pdf"
            "zip" -> "application/zip"
            "txt", "log", "md" -> "text/plain"
            "json" -> "application/json"
            "xml" -> "application/xml"
            "doc" -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "ppt" -> "application/vnd.ms-powerpoint"
            "pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            else -> "application/octet-stream"
        }
    }
}
