package com.foysol.jarvis

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.util.ArrayDeque

/** Keeps a small in-memory notification history after the user grants access. */
class MayaNotificationListenerService : NotificationListenerService() {
    companion object {
        private const val MAX_ITEMS = 100
        private val recent = ArrayDeque<String>()

        @Synchronized
        fun recentNotifications(): List<String> = recent.toList()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val extras = sbn.notification.extras
        val payload = JSONObject().apply {
            put("package", sbn.packageName)
            put("title", extras.getCharSequence("android.title")?.toString() ?: "")
            put("text", extras.getCharSequence("android.text")?.toString() ?: "")
            put("time", sbn.postTime)
        }.toString()
        synchronized(MayaNotificationListenerService::class.java) {
            recent.addFirst(payload)
            while (recent.size > MAX_ITEMS) recent.removeLast()
        }
    }
}
