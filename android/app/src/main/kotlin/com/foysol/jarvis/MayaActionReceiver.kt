package com.foysol.jarvis
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit
class MayaActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getStringExtra("taskId") ?: return
        if (intent.action == "ACTION_SNOOZE") {
            val req = OneTimeWorkRequestBuilder<MayaScheduledWorker>().setInitialDelay(10, TimeUnit.MINUTES).setInputData(workDataOf("title" to "Snoozed", "body" to "10m snooze", "taskId" to taskId)).build()
            WorkManager.getInstance(context).enqueue(req)
        }
    }
}
