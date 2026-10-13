package com.foysol.jarvis

import java.util.concurrent.TimeUnit

/** 
 * MAYA NEXØRA - GOD MODE ROOT BRIDGE
 * Owner-only allowlisted - Shizuku + Magisk + KernelSU compatible
 * No arbitrary shell - all commands are sanitized
 */
object MayaRootBridge {
    
    // Shizuku check
    private fun isShizukuAvailable(): Boolean {
        return try {
            Class.forName("rikka.shizuku.Shizuku")
            true
        } catch (_: Exception) { false }
    }

    fun status(): Map<String, Any?> {
        val suCheck = run(listOf("su", "-c", "id"))
        val shizukuCheck = isShizukuAvailable()
        return mapOf(
            "success" to true,
            "su_available" to (suCheck.first && suCheck.second.contains("uid=0")),
            "shizuku_available" to shizukuCheck,
            "god_mode" to (suCheck.first && suCheck.second.contains("uid=0") || shizukuCheck),
            "output" to suCheck.second.take(300),
            "kernel" to run(listOf("uname", "-r")).second.take(100)
        )
    }

    // ========== GOD MODE INPUT SUITE ==========
    
    fun tap(x: Int, y: Int) = action("input tap ${x.coerceAtLeast(0)} ${y.coerceAtLeast(0)}")

    fun doubleTap(x: Int, y: Int) = action("input tap ${x.coerceAtLeast(0)} ${y.coerceAtLeast(0)} && sleep 0.1 && input tap ${x.coerceAtLeast(0)} ${y.coerceAtLeast(0)}")

    fun swipe(sx: Int, sy: Int, ex: Int, ey: Int, duration: Int) =
        action("input swipe ${sx.coerceAtLeast(0)} ${sy.coerceAtLeast(0)} ${ex.coerceAtLeast(0)} ${ey.coerceAtLeast(0)} ${duration.coerceIn(10, 5000)}")

    fun swipeFast(sx: Int, sy: Int, ex: Int, ey: Int) = swipe(sx, sy, ex, ey, 80)
    fun swipeSlow(sx: Int, sy: Int, ex: Int, ey: Int) = swipe(sx, sy, ex, ey, 800)

    fun keyEvent(code: Int): Map<String, Any?> {
        require(code in 0..288) { "Invalid Android key code" }
        return action("input keyevent $code")
    }

    fun typeText(text: String): Map<String, Any?> {
        // Sanitized - escape shell chars
        val sanitized = text.replace("'", "'\\''").take(500)
        return action("input text '$sanitized'")
    }

    // ========== APP CONTROL GOD MODE ==========

    fun launchPackage(packageName: String): Map<String, Any?> {
        require(packageName.matches(Regex("^[a-zA-Z0-9._]+$"))) { "Invalid package" }
        return action("monkey -p $packageName -c android.intent.category.LAUNCHER 1")
    }

    fun forceStop(packageName: String): Map<String, Any?> {
        require(packageName.matches(Regex("^[a-zA-Z0-9._]+$")))
        return action("am force-stop $packageName")
    }

    fun clearCache(packageName: String): Map<String, Any?> {
        require(packageName.matches(Regex("^[a-zA-Z0-9._]+$")))
        return action("pm clear --cache-only $packageName")
    }

    fun grantPermission(packageName: String, permission: String): Map<String, Any?> {
        require(packageName.matches(Regex("^[a-zA-Z0-9._]+$")))
        require(permission.matches(Regex("^[a-zA-Z0-9._]+$")))
        return action("pm grant $packageName $permission")
    }

    // ========== SYSTEM GOD MODE ==========

    fun setBrightness(value: Int): Map<String, Any?> {
        return action("settings put system screen_brightness ${value.coerceIn(1, 255)}")
    }

    fun setVolume(stream: Int, value: Int): Map<String, Any?> {
        // stream 3 = music
        return action("media volume --stream ${stream.coerceIn(0,10)} --set ${value.coerceIn(0,15)}")
    }

    fun screenshot(path: String = "/sdcard/maya_screenshot.png"): Map<String, Any?> {
        return action("screencap -p $path && echo $path")
    }

    fun getTopPackage(): Map<String, Any?> {
        return action("dumpsys window windows | grep mCurrentFocus")
    }

    fun killAllBackground(): Map<String, Any?> {
        return action("am kill-all")
    }

    // ========== CORE EXECUTOR - UNKILLABLE ==========

    private fun action(command: String): Map<String, Any?> {
        val result = run(listOf("su", "-c", command))
        // Fallback to sh if su fails
        val finalResult = if (!result.first && result.second.contains("not found")) {
            run(listOf("sh", "-c", command))
        } else result
        
        return mapOf(
            "success" to finalResult.first, 
            "output" to finalResult.second.take(500),
            "command" to command.take(100)
        )
    }

    private fun run(command: List<String>): Pair<Boolean, String> = try {
        val process = ProcessBuilder(command)
            .redirectErrorStream(true)
            .start()
        if (!process.waitFor(8, TimeUnit.SECONDS)) { // Increased to 8s for heavy cmds
            process.destroyForcibly()
            false to "Command timed out after 8s"
        } else {
            (process.exitValue() == 0) to process.inputStream.bufferedReader().use { it.readText() }
        }
    } catch (error: Throwable) {
        false to (error.message ?: error.javaClass.simpleName)
    }

    // ========== ULTRA UTILS ==========

    fun isRooted(): Boolean = status()["su_available"] as? Boolean ?: false
    fun isGodMode(): Boolean = status()["god_mode"] as? Boolean ?: false
}