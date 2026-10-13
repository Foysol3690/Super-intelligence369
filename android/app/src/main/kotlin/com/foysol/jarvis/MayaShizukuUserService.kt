package com.foysol.jarvis
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.os.Binder
import android.os.PowerManager
import android.os.SystemClock
import org.json.JSONObject
class MayaShizukuUserService : IMayaShizukuService.Stub() {
    override fun execute(requestJson: String): String {
        return try {
            val req = JSONObject(requestJson)
            val ctx = MayaApp.appContext
            when (req.optString("action")) {
                "lock" -> {
                    val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    try { dpm.lockNow() } catch(_:Exception){ Runtime.getRuntime().exec(arrayOf("input","keyevent","26")).waitFor() }
                    JSONObject().put("success", true).toString()
                }
                "unlock" -> {
                    val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                    val wl = pm.newWakeLock(PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "Maya:Unlock")
                    wl.acquire(5000L)
                    Runtime.getRuntime().exec(arrayOf("input","keyevent","224")).waitFor()
                    SystemClock.sleep(400)
                    Runtime.getRuntime().exec(arrayOf("input","swipe","500","1800","500","600","300")).waitFor()
                    wl.release()
                    JSONObject().put("success", true).toString()
                }
                else -> JSONObject().put("success", true).toString()
            }
        } catch(e:Exception){ JSONObject().put("success", false).put("error", e.message).toString() }
    }
}
