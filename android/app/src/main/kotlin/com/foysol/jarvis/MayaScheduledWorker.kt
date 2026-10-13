package com.foysol.jarvis

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.Locale

class MayaScheduledWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {

    override fun doWork(): Result {
        val title = inputData.getString("title")?.take(120) ?: "Maya reminder"
        val body = inputData.getString("body")?.take(1000) ?: "Your scheduled task is ready."
        val taskId = inputData.getString("taskId") ?: System.currentTimeMillis().toString()
        val speak = inputData.getBoolean("speak", true)
        
        val channelId = "maya_scheduled_jobs_god_v2"
        val manager = applicationContext.getSystemService(NotificationManager::class.java)

        manager?.createNotificationChannel(
            NotificationChannel(channelId, "Maya Quantum Reminders V2", NotificationManager.IMPORTANCE_HIGH).apply { 
                description = "God mode V2 with voice"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 1000)
                enableLights(true)
                setBypassDnd(true)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            },
        )

        // Vibrate like crazy
        try {
            val vib = applicationContext.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vib.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 200, 500), -1))
            } else {
                @Suppress("DEPRECATION") vib.vibrate(longArrayOf(0, 500, 200, 500), -1)
            }
        } catch (_: Exception) {}

        // Speak the reminder - NEW IN V2
        if (speak) {
            try {
                lateinit var tts: TextToSpeech
                tts = TextToSpeech(applicationContext) { status ->
                    if (status == TextToSpeech.SUCCESS) {
                        try {
                            tts.language = Locale("en", "IN")
                            tts.speak(
                                "$title. $body",
                                TextToSpeech.QUEUE_FLUSH,
                                null,
                                "maya_reminder_$taskId",
                            )
                        } catch (_: Exception) {}
                    }
                }
            } catch (_: Exception) {}
        }

        val launchIntent = applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("from_reminder", true)
            putExtra("taskId", taskId)
        }

        val pendingIntent = PendingIntent.getActivity(applicationContext, taskId.hashCode(), launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val fullScreenIntent = PendingIntent.getActivity(applicationContext, taskId.hashCode() + 1, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val snoozeIntent = Intent(applicationContext, MayaActionReceiver::class.java).apply { action = "ACTION_SNOOZE"; putExtra("taskId", taskId) }
        val snoozePending = PendingIntent.getBroadcast(applicationContext, taskId.hashCode() + 2, snoozeIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val doneIntent = Intent(applicationContext, MayaActionReceiver::class.java).apply { action = "ACTION_DONE"; putExtra("taskId", taskId) }
        val donePending = PendingIntent.getBroadcast(applicationContext, taskId.hashCode() + 3, doneIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val notification = NotificationCompat.Builder(applicationContext, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("⚡ $title")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(fullScreenIntent, true)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVibrate(longArrayOf(0, 500, 200, 500, 200, 1000))
            .addAction(android.R.drawable.ic_popup_reminder, "Snooze 10m", snoozePending)
            .addAction(android.R.drawable.checkbox_on_background, "Done", donePending)
            .build()

        val notifId = (taskId.hashCode() + System.currentTimeMillis() % 10000).toInt()
        manager?.notify(notifId, notification)

        return Result.success()
    }
}