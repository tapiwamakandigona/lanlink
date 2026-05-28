package com.lanlink.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Thin wrapper over [NotificationManagerCompat] that LanLink uses to surface
 * receive progress in the system notification shade. The Dart side calls
 * through a MethodChannel as transfers start, progress, and finish.
 *
 * On Android 8.0+ we route everything through a single high-importance
 * channel so OEM skins that hide low-importance notifications still show
 * progress. The user can mute the channel from Settings -> Apps -> LanLink
 * -> Notifications if they don't want it.
 */
class TransferNotifier(private val context: Context) {

    init {
        ensureChannel()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Transfers",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Progress and completion of LanLink file transfers."
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    fun showProgress(
        notificationId: Int,
        title: String,
        text: String,
        progress: Int,
        max: Int,
        indeterminate: Boolean,
    ) {
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(launchAppIntent())
            .setProgress(
                if (indeterminate) 0 else max.coerceAtLeast(1),
                if (indeterminate) 0 else progress.coerceAtMost(max),
                indeterminate,
            )
        try {
            NotificationManagerCompat.from(context)
                .notify(notificationId, builder.build())
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS denied on Android 13+ — silently skip.
        }
    }

    fun showFinal(
        notificationId: Int,
        title: String,
        text: String,
        success: Boolean,
    ) {
        val icon =
            if (success) android.R.drawable.stat_sys_download_done
            else android.R.drawable.stat_notify_error
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setOngoing(false)
            .setOnlyAlertOnce(false)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(launchAppIntent())
        try {
            NotificationManagerCompat.from(context)
                .notify(notificationId, builder.build())
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS denied on Android 13+ — silently skip.
        }
    }

    fun cancel(notificationId: Int) {
        NotificationManagerCompat.from(context).cancel(notificationId)
    }

    private fun launchAppIntent(): PendingIntent {
        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(context, 0, launch, flags)
    }

    companion object {
        private const val CHANNEL_ID = "lanlink_transfers"
    }
}
