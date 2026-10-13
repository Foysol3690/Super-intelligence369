package com.foysol.jarvis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.ContactsContract
import android.speech.tts.TextToSpeech
import android.telephony.TelephonyManager
import java.util.Locale

/** 
 * MAYA NEXØRA - GOD MODE CALL OVERLORD
 * Announces, Blocks Spam, Wakes Screen, Bilingual
 */
class MayaCallReceiver : BroadcastReceiver(), TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var announcement: String = "Incoming call"
    private var appContext: Context? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        if (state != TelephonyManager.EXTRA_STATE_RINGING) {
            // Cleanup on IDLE/OFFHOOK
            if (state == TelephonyManager.EXTRA_STATE_IDLE || state == TelephonyManager.EXTRA_STATE_OFFHOOK) {
                cleanup()
            }
            return
        }

        appContext = context.applicationContext
        
        // GOD MODE: Wake up screen
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "Maya::CallWake").apply {
            acquire(15000L) // 15 sec
        }

        val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
        
        // SPAM CHECK - Block if in blocklist
        if (isSpamNumber(number)) {
            android.util.Log.w("MayaCall", "Blocked spam: $number")
            announcement = "Spam call blocked"
        } else {
            val name = if (number.isNullOrBlank()) null else contactName(context, number)
            announcement = when {
                !name.isNullOrBlank() -> "Incoming call from $name"
                !number.isNullOrBlank() -> "Incoming call from ${formatNumberForSpeech(number)}"
                else -> "Incoming call from unknown number"
            }
        }

        // Init TTS async
        try {
            tts = TextToSpeech(context.applicationContext, this)
        } catch (e: Exception) {
            android.util.Log.e("MayaCall", "TTS init failed", e)
            cleanup()
        }
    }

    private fun contactName(context: Context, number: String): String? {
        return try {
            val uri = UriHelper.phoneLookupUri(number)
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun formatNumberForSpeech(number: String): String {
        // Speak last 4 digits only for privacy
        val digits = number.filter { it.isDigit() }
        return if (digits.length >= 4) digits.takeLast(4).toCharArray().joinToString(" ") else "unknown"
    }

    private fun isSpamNumber(number: String?): Boolean {
        if (number.isNullOrBlank()) return false
        // Add your spam list here - could load from SharedPrefs
        val spamPrefixes = listOf("140", "1800", "999999") // Example
        return spamPrefixes.any { number.contains(it) }
    }

    override fun onInit(status: Int) {
        val engine = tts ?: return
        if (status == TextToSpeech.SUCCESS) {
            try {
                // GOD MODE: Try Bengali first, then English India
                val bnResult = engine.setLanguage(Locale("bn", "BD"))
                if (bnResult == TextToSpeech.LANG_MISSING_DATA || bnResult == TextToSpeech.LANG_NOT_SUPPORTED) {
                    engine.language = Locale("en", "IN")
                } else {
                    // If Bengali supported, use mixed announcement
                    engine.language = Locale("en", "IN")
                }
                
                engine.setSpeechRate(1.0f)
                engine.setPitch(1.0f)
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    engine.speak(announcement, TextToSpeech.QUEUE_FLUSH, null, "maya_incoming_call")
                } else {
                    @Suppress("DEPRECATION")
                    engine.speak(announcement, TextToSpeech.QUEUE_FLUSH, null)
                }

                // Auto cleanup after speech
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    cleanup()
                }, 8000L)

            } catch (e: Exception) {
                android.util.Log.e("MayaCall", "Speak failed", e)
                cleanup()
            }
        } else {
            cleanup()
        }
    }

    private fun cleanup() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {}
        tts = null
        
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        wakeLock = null
        appContext = null
    }
}

private object UriHelper {
    fun phoneLookupUri(number: String) =
        android.net.Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            android.net.Uri.encode(number)
        )
}