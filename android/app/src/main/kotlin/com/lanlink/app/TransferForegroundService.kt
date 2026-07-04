package com.lanlink.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * A short-lived foreground service that LanLink starts while at least one
 * transfer is in flight. The service exists so Android does not kill our
 * process while the user backgrounds the app — e.g. they tap home or lock
 * the screen during a multi-gigabyte send.
 *
 * The summary notification shown by this service is intentionally separate
 * from the per-session progress notifications posted by [TransferNotifier].
 * Per-session notifications keep ticking through the shade, while this
 * service notification is a single "LanLink is transferring files…" row
 * that exists for as long as any transfer is active.
 */
class TransferForegroundService : Service() {

    /**
     * Held while at least one transfer is active. Without these, Android's
     * Wi-Fi power-save and CPU throttling kick in the moment the screen dims
     * or the app is backgrounded, which in the field looks like throughput
     * oscillating between ~KB/s and ~MB/s and transfers stalling mid-stream —
     * exactly the hotspot-mode symptom reports. The foreground service only
     * keeps the *process* alive; these locks keep the radio and CPU awake.
     */
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    /**
     * Re-arms the timed wake lock while the service lives. The Dart side
     * only syncs the service on session lifecycle changes, so a long
     * multi-gigabyte transfer would otherwise outlive a single timed
     * acquisition.
     */
    private val rearmHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val rearmRunnable = object : Runnable {
        override fun run() {
            acquireLocks()
            rearmHandler.postDelayed(this, WAKE_LOCK_REARM_MS)
        }
    }
    private var rearmScheduled = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                releaseLocks()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }
        ensureChannel()
        val active = intent?.getIntExtra(EXTRA_ACTIVE_COUNT, 1) ?: 1
        startForegroundCompat(active)
        acquireLocks()
        if (!rearmScheduled) {
            rearmScheduled = true
            rearmHandler.postDelayed(rearmRunnable, WAKE_LOCK_REARM_MS)
        }
        // If the system kills us we don't want to be restarted automatically —
        // the Dart side will re-start us if there is still a live transfer.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    private fun acquireLocks() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LanLink:transfer")
                    .apply { setReferenceCounted(false) }
            }
            // Timed acquisition as a leak guard: [rearmRunnable] re-acquires
            // while the service is alive, so a crashed run can never pin the
            // CPU for more than the timeout after the service dies.
            wakeLock?.acquire(WAKE_LOCK_TIMEOUT_MS)
        } catch (_: Throwable) {
            // Locks are an optimisation; never take the service down for one.
        }
        try {
            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                // WIFI_MODE_FULL_LOW_LATENCY is only honoured while the
                // screen is on AND the acquiring app is in the foreground —
                // exactly the opposite of a background transfer (user pockets
                // the phone or watches the receiving PC), where Wi-Fi
                // power-save then throttles throughput to tens of KB/s.
                // HIGH_PERF disables power-save regardless of screen state.
                // It is deprecated from API 34, where the platform treats it
                // as LOW_LATENCY anyway, so use it everywhere below 34.
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(mode, "LanLink:transfer")
                    .apply { setReferenceCounted(false) }
            }
            if (wifiLock?.isHeld != true) wifiLock?.acquire()
        } catch (_: Throwable) {
        }
    }

    private fun releaseLocks() {
        rearmScheduled = false
        rearmHandler.removeCallbacks(rearmRunnable)
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Throwable) {
        }
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Throwable) {
        }
    }

    private fun startForegroundCompat(activeCount: Int) {
        val notification = buildNotification(activeCount)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
                return
            } catch (_: Throwable) {
                // Fall through to the legacy two-arg form.
            }
        }
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(activeCount: Int): Notification {
        val text = if (activeCount <= 1) {
            "Transferring 1 file batch in the background."
        } else {
            "Transferring $activeCount file batches in the background."
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val tapIntent = PendingIntent.getActivity(this, 0, launch, pendingFlags)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle("LanLink is transferring")
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(tapIntent)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Active transfers",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Lets LanLink keep transferring while the app is in the background."
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_START = "com.lanlink.app.action.START_FOREGROUND"
        const val ACTION_STOP = "com.lanlink.app.action.STOP_FOREGROUND"
        const val EXTRA_ACTIVE_COUNT = "activeCount"
        private const val CHANNEL_ID = "lanlink_active_transfers"
        private const val NOTIFICATION_ID = 0x2A41

        /**
         * Upper bound on a single wake-lock acquisition. The Dart side syncs
         * the service on every session lifecycle change, re-arming the
         * timeout, so long multi-gigabyte transfers stay covered while a
         * crashed/wedged run can only over-hold by this much.
         */
        private const val WAKE_LOCK_TIMEOUT_MS = 30L * 60L * 1000L

        /** How often the service re-arms the timed wake lock while alive. */
        private const val WAKE_LOCK_REARM_MS = 10L * 60L * 1000L
    }
}
