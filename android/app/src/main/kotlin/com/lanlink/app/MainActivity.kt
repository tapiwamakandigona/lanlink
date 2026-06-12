package com.lanlink.app

import android.content.ComponentName
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.media.MediaScannerConnection
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Size
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.Inet4Address
import java.net.NetworkInterface

class MainActivity : FlutterActivity() {

    /// Buffer of files handed to us by an incoming `ACTION_SEND` /
    /// `ACTION_SEND_MULTIPLE` intent before the Flutter side asks for
    /// them. The pairing wizard / home page polls this on startup and
    /// when the activity comes back to the foreground.
    private val pendingShares = mutableListOf<Map<String, Any>>()

    /// Live LocalOnlyHotspot reservation. Non-null while LanLink is
    /// hosting a direct link. Closing it tears the hotspot down.
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null

    /// Result waiting for the runtime-permission dialog that gates
    /// startLocalOnlyHotspot (location / nearby-devices).
    private var hotspotPermissionResult: MethodChannel.Result? = null

    companion object {
        private const val HOTSPOT_PERMISSION_REQUEST = 7431
    }
    private var shareChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        capturePendingShare(intent)
    }

    override fun onDestroy() {
        stopLocalHotspot()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        capturePendingShare(intent)
        // The Flutter side may already be listening; nudge it.
        shareChannel?.invokeMethod("onShareReceived", null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanlink/android_apps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // App listing touches the package manager for every
                    // installed app; keep it off the UI thread. Icons are
                    // deliberately not included — they load lazily below.
                    "listApps" -> Thread {
                        val apps = try {
                            listLaunchableApps()
                        } catch (_: Exception) {
                            emptyList<Map<String, Any>>()
                        }
                        runOnUiThread { result.success(apps) }
                    }.start()
                    // One launcher icon at a time, fetched as rows become
                    // visible — keeps the Apps tab paint instant.
                    "appIcon" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            val bytes = try {
                                appIconPng(pkg)
                            } catch (_: Exception) {
                                null
                            }
                            runOnUiThread { result.success(bytes) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        // Media library (photos + videos) for the share picker and the
        // one-tap "Move my photos" migration. MediaStore queries and
        // thumbnail decoding are I/O heavy, so both run off the UI thread.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanlink/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listMedia" -> Thread {
                        val items = try {
                            listMediaItems()
                        } catch (_: Exception) {
                            emptyList<Map<String, Any>>()
                        }
                        runOnUiThread { result.success(items) }
                    }.start()
                    "thumbnail" -> {
                        val id = (call.argument<Number>("id"))?.toLong()
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        if (id == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            val bytes = try {
                                mediaThumbnail(id, isVideo)
                            } catch (_: Exception) {
                                null
                            }
                            runOnUiThread { result.success(bytes) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanlink/foreground_service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val activeCount = call.argument<Int>("activeCount") ?: 1
                        val intent = Intent(applicationContext, TransferForegroundService::class.java).apply {
                            action = TransferForegroundService.ACTION_START
                            putExtra(TransferForegroundService.EXTRA_ACTIVE_COUNT, activeCount)
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                applicationContext.startForegroundService(intent)
                            } else {
                                applicationContext.startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FG_START_FAILED", e.message, null)
                        }
                    }
                    "stop" -> {
                        val intent = Intent(applicationContext, TransferForegroundService::class.java).apply {
                            action = TransferForegroundService.ACTION_STOP
                        }
                        try {
                            applicationContext.startService(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FG_STOP_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanlink/system_settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openHotspotSettings" -> result.success(openHotspotSettings())
                    "openWifiSettings" -> result.success(openWifiSettings())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanlink/hotspot")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" ->
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    "hasPermission" -> result.success(hasHotspotPermission())
                    "requestPermission" -> requestHotspotPermission(result)
                    "start" -> startLocalHotspot(result)
                    "stop" -> {
                        stopLocalHotspot()
                        result.success(true)
                    }
                    "isRunning" -> result.success(hotspotReservation != null)
                    else -> result.notImplemented()
                }
            }

        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lanlink/incoming_share",
        )
        shareChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consume" -> {
                    val drained = ArrayList(pendingShares)
                    pendingShares.clear()
                    result.success(drained)
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
                        val subDir = call.argument<String>("subDir")
                        if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.error(
                                "ARGS",
                                "publishToDownloads requires sourcePath + fileName",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val published = publishToDownloads(sourcePath, fileName, subDir)
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
            val map = mutableMapOf<String, Any>(
                "label" to pm.getApplicationLabel(appInfo).toString(),
                "packageName" to packageName,
                "apkPath" to apk.absolutePath,
                "size" to apk.length(),
            )
            map
        }.distinctBy { it["packageName"] as String }
    }

    /// Rasterises an app's launcher icon to a small PNG so Flutter can show
    /// it in the share picker. Returns null when the icon can't be drawn.
    private fun appIconPng(packageName: String, sizePx: Int = 96): ByteArray? {
        return try {
            val drawable: Drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
                Bitmap.createScaledBitmap(drawable.bitmap, sizePx, sizePx, true)
            } else {
                val b = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(b)
                drawable.setBounds(0, 0, sizePx, sizePx)
                drawable.draw(canvas)
                b
            }
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 90, out)
            out.toByteArray()
        } catch (_: Exception) {
            null
        }
    }

    // ----- Media library (photos + videos) for the share picker -----

    /// Lists every image and video in MediaStore, newest first. Only items
    /// whose backing file is directly readable are returned (the sender
    /// streams from the file path), which is the normal case for the
    /// primary external volume once the media permission is granted.
    private fun listMediaItems(): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        out += queryMedia(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            isVideo = false,
        )
        out += queryMedia(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            isVideo = true,
        )
        out.sortByDescending { it["dateModified"] as Long }
        return out
    }

    private fun queryMedia(collection: Uri, isVideo: Boolean): List<Map<String, Any>> {
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
        )
        val items = mutableListOf<Map<String, Any>>()
        contentResolver.query(collection, projection, null, null, null)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val dataCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
            val dateCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val bucketCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                val path = cursor.getString(dataCol) ?: continue
                val file = File(path)
                if (!file.exists() || !file.canRead()) continue
                val size = cursor.getLong(sizeCol).takeIf { it > 0 } ?: file.length()
                if (size <= 0) continue
                items += mapOf(
                    "id" to cursor.getLong(idCol),
                    "name" to (cursor.getString(nameCol) ?: file.name),
                    "path" to path,
                    "size" to size,
                    "isVideo" to isVideo,
                    "dateModified" to cursor.getLong(dateCol),
                    "bucket" to (cursor.getString(bucketCol) ?: ""),
                )
            }
        }
        return items
    }

    /// Decodes a small JPEG thumbnail for a MediaStore item. Uses the
    /// modern loadThumbnail API on Android 10+, the legacy thumbnail
    /// providers before that.
    private fun mediaThumbnail(id: Long, isVideo: Boolean): ByteArray? {
        val collection = if (isVideo) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                contentResolver.loadThumbnail(
                    ContentUris.withAppendedId(collection, id),
                    Size(256, 256),
                    null,
                )
            } catch (_: Exception) {
                null
            }
        } else {
            @Suppress("DEPRECATION")
            if (isVideo) {
                MediaStore.Video.Thumbnails.getThumbnail(
                    contentResolver, id, MediaStore.Video.Thumbnails.MINI_KIND, null,
                )
            } else {
                MediaStore.Images.Thumbnails.getThumbnail(
                    contentResolver, id, MediaStore.Images.Thumbnails.MINI_KIND, null,
                )
            }
        }
        if (bitmap == null) return null
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 78, out)
        return out.toByteArray()
    }

    /**
     * Opens whichever Settings screen lets the user toggle the Wi-Fi
     * hotspot. Exact location varies per OEM and Android version; we try
     * the cleanest options first and fall back to the generic wireless
     * page so something always opens.
     */
    // ----- LocalOnlyHotspot (direct link without a shared Wi-Fi) -----

    /// The runtime permission required by startLocalOnlyHotspot:
    /// NEARBY_WIFI_DEVICES on Android 13+, fine location before that.
    private fun hotspotPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            android.Manifest.permission.NEARBY_WIFI_DEVICES
        } else {
            android.Manifest.permission.ACCESS_FINE_LOCATION
        }

    private fun hasHotspotPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, hotspotPermission()) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestHotspotPermission(result: MethodChannel.Result) {
        if (hasHotspotPermission()) {
            result.success(true)
            return
        }
        if (hotspotPermissionResult != null) {
            result.error("busy", "Permission request already in flight", null)
            return
        }
        hotspotPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(hotspotPermission()),
            HOTSPOT_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == HOTSPOT_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            hotspotPermissionResult?.success(granted)
            hotspotPermissionResult = null
        }
    }

    private fun startLocalHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported", "LocalOnlyHotspot needs Android 8+", null)
            return
        }
        if (hotspotReservation != null) {
            // Already running — report the live credentials again.
            val info = describeReservation(hotspotReservation!!)
            if (info != null) result.success(info)
            else result.error("state", "Hotspot running but unreadable", null)
            return
        }
        if (!hasHotspotPermission()) {
            result.error("permission", "Missing ${hotspotPermission()}", null)
            return
        }
        val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        var replied = false
        try {
            wifi.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(
                        reservation: WifiManager.LocalOnlyHotspotReservation,
                    ) {
                        hotspotReservation = reservation
                        val info = describeReservation(reservation)
                        if (replied) return
                        replied = true
                        if (info != null) {
                            result.success(info)
                        } else {
                            reservation.close()
                            hotspotReservation = null
                            result.error("state", "Could not read hotspot config", null)
                        }
                    }

                    override fun onFailed(reason: Int) {
                        if (replied) return
                        replied = true
                        result.error("failed", "LocalOnlyHotspot failed: $reason", null)
                    }

                    override fun onStopped() {
                        hotspotReservation = null
                    }
                },
                Handler(Looper.getMainLooper()),
            )
        } catch (e: Exception) {
            // SecurityException when location services are off, or
            // IllegalStateException when tethering is already active.
            if (!replied) {
                replied = true
                result.error("failed", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    /// Extracts SSID, passphrase and our own IPv4 addresses on the
    /// freshly created hotspot interface.
    private fun describeReservation(
        reservation: WifiManager.LocalOnlyHotspotReservation,
    ): Map<String, Any>? {
        var ssid: String? = null
        var passphrase: String? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val config = reservation.softApConfiguration
            ssid = config.ssid
            passphrase = config.passphrase
        } else {
            @Suppress("DEPRECATION")
            val config = reservation.wifiConfiguration
            ssid = config?.SSID
            @Suppress("DEPRECATION")
            passphrase = config?.preSharedKey
        }
        if (ssid.isNullOrEmpty() || passphrase.isNullOrEmpty()) return null
        return mapOf(
            "ssid" to ssid.removeSurrounding("\""),
            "password" to passphrase,
            "hostIps" to localIpv4Addresses(),
        )
    }

    /// All site-local IPv4 addresses, hotspot interface first
    /// (ap0 / swlan0 / wlan1-style names or the classic 192.168.43/49 nets).
    private fun localIpv4Addresses(): List<String> {
        val preferred = mutableListOf<String>()
        val others = mutableListOf<String>()
        try {
            for (nif in NetworkInterface.getNetworkInterfaces()) {
                if (!nif.isUp || nif.isLoopback) continue
                val name = nif.name.lowercase()
                for (addr in nif.inetAddresses) {
                    if (addr !is Inet4Address || addr.isLoopbackAddress) continue
                    val ip = addr.hostAddress ?: continue
                    val apLike = name.startsWith("ap") || name.contains("swlan") ||
                        ip.startsWith("192.168.43.") || ip.startsWith("192.168.49.")
                    if (apLike) preferred += ip else others += ip
                }
            }
        } catch (_: Exception) {
            // best effort
        }
        return preferred + others
    }

    private fun stopLocalHotspot() {
        try {
            hotspotReservation?.close()
        } catch (_: Exception) {
        }
        hotspotReservation = null
    }

    private fun openHotspotSettings(): Boolean {
        val attempts = mutableListOf<Intent>()
        attempts += Intent().apply {
            component = ComponentName(
                "com.android.settings",
                "com.android.settings.TetherSettings",
            )
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        attempts += Intent("android.settings.TETHER_SETTINGS").apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            attempts += Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
        }
        attempts += Intent(Settings.ACTION_WIRELESS_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        for (intent in attempts) {
            try {
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
                continue
            }
        }
        return false
    }

    /**
     * Opens the OS Wi-Fi settings page so the user can join the other
     * device's hotspot from the system UI.
     */
    private fun openWifiSettings(): Boolean {
        val attempts = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            attempts += Intent(Settings.Panel.ACTION_WIFI)
        }
        attempts += Intent(Settings.ACTION_WIFI_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        for (intent in attempts) {
            try {
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
                continue
            }
        }
        return false
    }

    /**
     * Drains any `EXTRA_STREAM`(s) on an incoming `ACTION_SEND` /
     * `ACTION_SEND_MULTIPLE` intent into [pendingShares] as cached app-
     * private files. The Flutter side will pick them up via the
     * `consume` method on `lanlink/incoming_share` once it's ready.
     */
    private fun capturePendingShare(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val uris: List<Uri> = when (action) {
            Intent.ACTION_SEND -> {
                val u: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                if (u != null) listOf(u) else emptyList()
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val list: List<Uri>? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                }
                list ?: emptyList()
            }
            else -> emptyList()
        }
        for (uri in uris) {
            val cached = copyIncomingUriToCache(uri) ?: continue
            pendingShares += cached
        }
    }

    private fun copyIncomingUriToCache(uri: Uri): Map<String, Any>? {
        return try {
            val resolver = contentResolver
            var displayName = "shared-file"
            var size: Long = -1L
            resolver.query(uri, null, null, null, null)?.use { c: Cursor ->
                val nameIx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIx = c.getColumnIndex(OpenableColumns.SIZE)
                if (c.moveToFirst()) {
                    if (nameIx >= 0) {
                        val v = c.getString(nameIx)
                        if (!v.isNullOrBlank()) displayName = v
                    }
                    if (sizeIx >= 0) {
                        size = c.getLong(sizeIx)
                    }
                }
            }
            val outDir = File(cacheDir, "incoming_share").apply { mkdirs() }
            val safeName = displayName.replace(File.separatorChar, '_')
            val out = File(outDir, "${System.currentTimeMillis()}_$safeName")
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(out).use { output ->
                    input.copyTo(output)
                }
            } ?: return null
            if (size < 0) size = out.length()
            mapOf(
                "path" to out.absolutePath,
                "fileName" to displayName,
                "size" to size,
            )
        } catch (_: Exception) {
            null
        }
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
    private fun publishToDownloads(sourcePath: String, fileName: String, subDir: String?): String? {
        val source = File(sourcePath)
        if (!source.exists()) return null
        val safeSub = sanitizeSubDir(subDir)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            publishViaMediaStore(source, fileName, safeSub)
        } else {
            publishViaLegacyPath(source, fileName, safeSub)
        }
    }

    // Re-sanitizes a folder-transfer relative dir on the platform side so a
    // malicious peer can never steer the copy outside Downloads/LanLink.
    private fun sanitizeSubDir(subDir: String?): String? {
        if (subDir.isNullOrBlank()) return null
        val parts = subDir.split('/', '\\')
            .map { it.trim().replace(Regex("[\\\\/:*?\"<>|]"), "_") }
            .filter { it.isNotEmpty() && it != "." && it != ".." }
        return if (parts.isEmpty()) null else parts.joinToString("/")
    }

    private fun publishViaMediaStore(source: File, fileName: String, subDir: String?): String? {
        val resolver = contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val relativeDir = if (subDir == null) {
            "${Environment.DIRECTORY_DOWNLOADS}/LanLink"
        } else {
            "${Environment.DIRECTORY_DOWNLOADS}/LanLink/$subDir"
        }
        val displayName = uniqueDisplayName(fileName) { candidate ->
            isDisplayNameTaken(resolver, candidate)
        }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.MIME_TYPE, mimeTypeFor(displayName))
            put(MediaStore.Downloads.RELATIVE_PATH, relativeDir)
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
            return "$relativeDir/$displayName"
        } catch (e: Exception) {
            try {
                resolver.delete(itemUri, null, null)
            } catch (_: Exception) {
            }
            throw e
        }
    }

    private fun publishViaLegacyPath(source: File, fileName: String, subDir: String?): String? {
        @Suppress("DEPRECATION")
        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val targetDir =
            if (subDir == null) File(downloads, "LanLink") else File(File(downloads, "LanLink"), subDir)
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
