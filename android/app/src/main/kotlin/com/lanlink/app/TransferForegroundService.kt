package com.lanlink.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
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

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }
        ensureChannel()
        val active = intent?.getIntExtra(EXTRA_ACTIVE_COUNT, 1) ?: 1
        startForegroundCompat(active)
        // If the system kills us we don't want to be restarted automatically —
        // the Dart side will re-start us if there is still a live transfer.
        return START_NOT_STICKY
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
    }
}
