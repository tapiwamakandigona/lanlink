package com.lanlink.app

import android.app.Activity
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Self-contained handler for the `lanlink/app_invite` method channel.
 *
 * "Invite a friend": copies this app's own APK into the cache directory
 * under a friendly, version-stamped name, exposes it through the app's
 * existing FileProvider, and fires ACTION_SEND with the APK mime type so
 * the user can pick Bluetooth / Quick Share in the system share sheet.
 *
 * Registration (one line in MainActivity.configureFlutterEngine):
 *     AppInvite.register(this, flutterEngine.dartExecutor.binaryMessenger)
 */
object AppInvite {
    private const val CHANNEL = "lanlink/app_invite"
    private const val APK_MIME = "application/vnd.android.package-archive"

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareApk" -> {
                    val fileName = call.argument<String>("fileName")
                        ?: defaultFileName(activity)
                    try {
                        result.success(shareApk(activity, fileName))
                    } catch (e: Exception) {
                        result.error("share_failed", e.message, null)
                    }
                }
                "shareText" -> {
                    val text = call.argument<String>("text")
                    if (text.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        try {
                            result.success(shareText(activity, text))
                        } catch (e: Exception) {
                            result.error("share_failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun defaultFileName(activity: Activity): String {
        val version = try {
            activity.packageManager
                .getPackageInfo(activity.packageName, 0).versionName
        } catch (_: Exception) {
            null
        }
        return "LanLink-v${version ?: "latest"}.apk"
    }

    /**
     * Returns "shared" when the share sheet was opened with a valid APK,
     * or "split" when this install uses split APKs (sharing just the base
     * split would produce a broken install — the caller should offer the
     * universal-download link instead).
     */
    private fun shareApk(activity: Activity, fileName: String): String {
        val appInfo = activity.applicationInfo

        // Play-style split installs: base.apk alone won't install.
        val splits = appInfo.splitSourceDirs
        if (splits != null && splits.isNotEmpty()) return "split"

        val source = File(appInfo.sourceDir)
        if (!source.exists()) throw IllegalStateException("APK not found at ${appInfo.sourceDir}")

        // Copy into cache under a friendly name; FileProvider's cache-path
        // root already covers this directory.
        val outDir = File(activity.cacheDir, "invite").apply { mkdirs() }
        val safeName = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val out = File(outDir, safeName)
        if (!out.exists() || out.length() != source.length()) {
            source.copyTo(out, overwrite = true)
        }

        val uri = FileProvider.getUriForFile(
            activity, "${activity.packageName}.fileprovider", out
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = APK_MIME
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(Intent.createChooser(intent, "Invite a friend to LanLink"))
        return "shared"
    }

    private fun shareText(activity: Activity, text: String): Boolean {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        activity.startActivity(Intent.createChooser(intent, "Share LanLink"))
        return true
    }
}
