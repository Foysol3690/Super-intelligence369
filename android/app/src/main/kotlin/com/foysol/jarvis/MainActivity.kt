package com.foysol.jarvis

import android.Manifest
import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.admin.DevicePolicyManager
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.telecom.TelecomManager
import android.view.WindowManager
import androidx.biometric.BiometricManager.Authenticators
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import rikka.shizuku.Shizuku
import java.util.concurrent.TimeUnit

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.foysol.jarvis/accessibility_bridge"
    private val GATEWAY_CHANNEL = "com.foysol.jarvis/offline_gateway"
    private val DARK_SAFE_CHANNEL = "com.foysol.jarvis/dark_safe"
    private val OMEGA_CAPTURE_REQUEST = 9026
    private val SHIZUKU_PERMISSION_REQUEST = 9027
    private lateinit var liveAudioBridge: LiveAudioBridge
    private var pendingOmegaCaptureResult: MethodChannel.Result? = null
    private var pendingShizukuPermissionResult: MethodChannel.Result? = null
    private var pendingShizukuBindResult: MethodChannel.Result? = null
    private var shizukuService: IMayaShizukuService? = null
    private var shizukuBinding = false
    private val shizukuHandler = Handler(Looper.getMainLooper())
    private var shizukuBindTimeout: Runnable? = null

    private val shizukuPermissionListener = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
        if (requestCode != SHIZUKU_PERMISSION_REQUEST) return@OnRequestPermissionResultListener
        val pending = pendingShizukuPermissionResult
        pendingShizukuPermissionResult = null
        pending?.success(mapOf("success" to (grantResult == PackageManager.PERMISSION_GRANTED), "granted" to (grantResult == PackageManager.PERMISSION_GRANTED)))
        if (grantResult == PackageManager.PERMISSION_GRANTED) bindShizukuIfReady()
    }

    private val shizukuConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            cancelShizukuBindTimeout()
            shizukuBinding = false
            shizukuService = IMayaShizukuService.Stub.asInterface(binder)
            pendingShizukuBindResult?.success(shizukuStatus())
            pendingShizukuBindResult = null
        }
        override fun onServiceDisconnected(name: ComponentName) {
            cancelShizukuBindTimeout()
            shizukuBinding = false
            shizukuService = null
        }
        override fun onBindingDied(name: ComponentName) {
            cancelShizukuBindTimeout()
            shizukuBinding = false
            shizukuService = null
            pendingShizukuBindResult?.error("SHIZUKU_BINDER_DIED", "Shizuku died", null)
            pendingShizukuBindResult = null
            shizukuHandler.postDelayed({ bindShizukuIfReady() }, 750L)
        }
        override fun onNullBinding(name: ComponentName) {
            cancelShizukuBindTimeout()
            shizukuBinding = false
            shizukuService = null
            pendingShizukuBindResult?.error("SHIZUKU_NULL_BINDING", "Empty", null)
            pendingShizukuBindResult = null
        }
    }

    private val shizukuBinderReceivedListener = Shizuku.OnBinderReceivedListener { bindShizukuIfReady() }
    private val shizukuBinderDeadListener = Shizuku.OnBinderDeadListener {
        cancelShizukuBindTimeout()
        shizukuBinding = false
        shizukuService = null
        pendingShizukuBindResult?.error("SHIZUKU_NOT_RUNNING", "Stopped", null)
        pendingShizukuBindResult = null
    }

    private val shizukuArgs by lazy {
        Shizuku.UserServiceArgs(ComponentName(packageName, MayaShizukuUserService::class.java.name))
            .daemon(false).processNameSuffix("maya").debuggable(BuildConfig.DEBUG).version(BuildConfig.VERSION_CODE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Shizuku.addRequestPermissionResultListener(shizukuPermissionListener)
        Shizuku.addBinderReceivedListenerSticky(shizukuBinderReceivedListener)
        Shizuku.addBinderDeadListener(shizukuBinderDeadListener)
        liveAudioBridge = LiveAudioBridge(this)
        liveAudioBridge.configure(flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DARK_SAFE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestBiometric" -> requestBiometricConfirmation("Dark protocol verification", result)
                else -> result.notImplemented()
            }
        }

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            val service = JarvisAccessibilityService.instance
            try {
                when (call.method) {
                    "isServiceEnabled" -> result.success(service != null)
                    "openAccessibilitySettings" -> { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)); result.success(true) }
                    "openNotificationAccessSettings" -> { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)); result.success(true) }
                    "openHotspotSettings" -> { startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS)); result.success(true) }

                    // === GOD AUTO LOCK/UNLOCK ===
                    "lockScreen" -> {
                        var locked = false
                        try {
                            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                            val admin = ComponentName(this, MayaDeviceAdminReceiver::class.java)
                            if (dpm.isAdminActive(admin)) { dpm.lockNow(); locked = true }
                        } catch (_: Exception) {}
                        if (!locked) {
                            try { locked = JSONObject(shizukuService?.execute(JSONObject().put("action","lock").toString()) ?: "").optBoolean("success", false) } catch (_: Exception) {}
                        }
                        if (!locked) { locked = service?.performGlobalAction(8) ?: false }
                        result.success(locked)
                    }
                    "autoUnlock" -> {
                        // ownerAuthorized check from Dart
                        val ownerAuth = call.argument<Boolean>("ownerAuthorized") == true
                        if (!ownerAuth) { result.error("AUTH_REQUIRED", "Biometric required", null); return@setMethodCallHandler }
                        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                        @Suppress("DEPRECATION") val wl = power.newWakeLock(PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "MayaAI:AutoUnlock")
                        wl.acquire(5000L)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) { setShowWhenLocked(true); setTurnScreenOn(true) } else { @Suppress("DEPRECATION") window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON) }
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        try {
                            shizukuExecute(JSONObject().put("action", "unlock"))
                            keyguard.requestDismissKeyguard(this, null)
                            result.success(mapOf("success" to true, "method" to "shizuku_wake_swipe"))
                        } catch (_: Exception) {
                            keyguard.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback(){})
                            result.success(mapOf("success" to true, "method" to "keyguard"))
                        }
                    }
                    "isDeviceLocked" -> {
                        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                        result.success(mapOf("locked" to km.isKeyguardLocked, "secure" to km.isDeviceSecure))
                    }
                    "requestSecureUnlock" -> {
                        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        @Suppress("DEPRECATION") val wakeLock = pm.newWakeLock(PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "MayaAI:SecureUnlockRequest")
                        wakeLock.acquire(5000L)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) { setShowWhenLocked(true); setTurnScreenOn(true) } else { @Suppress("DEPRECATION") window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON) }
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        if (!km.isKeyguardLocked) result.success(mapOf("requested" to false, "alreadyUnlocked" to true))
                        else { km.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {}); result.success(mapOf("requested" to true)) }
                    }

                    "scheduleReminder" -> {
                        val id = call.argument<String>("id")?.trim().orEmpty()
                        val title = call.argument<String>("title")?.trim().orEmpty()
                        val body = call.argument<String>("body")?.trim().orEmpty()
                        val delayMinutes = (call.argument<Int>("delayMinutes")?.toLong() ?: 1L).coerceIn(1L, 525_600L)
                        require(id.isNotEmpty() && title.isNotEmpty())
                        val request = OneTimeWorkRequestBuilder<MayaScheduledWorker>().setInitialDelay(delayMinutes, TimeUnit.MINUTES).setInputData(workDataOf("title" to title, "body" to body, "taskId" to id)).addTag("maya_scheduled_job").addTag("maya_job_$id").build()
                        WorkManager.getInstance(this).enqueueUniqueWork("maya_job_$id", ExistingWorkPolicy.REPLACE, request)
                        result.success(mapOf("success" to true, "jobId" to id))
                    }
                    "cancelReminder" -> { val id = call.argument<String>("id")?.trim().orEmpty(); require(id.isNotEmpty()); WorkManager.getInstance(this).cancelUniqueWork("maya_job_$id"); result.success(true) }
                    "biometricConfirm" -> requestBiometricConfirmation(call.argument<String>("reason") ?: "Confirm", result)
                    "recognizeSpeech" -> startNativeSpeechRecognition(result)
                    "resourceSnapshot" -> {
                        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val memoryInfo = ActivityManager.MemoryInfo()
                        activityManager.getMemoryInfo(memoryInfo)
                        val stat = StatFs(filesDir.path)
                        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                        val batteryStatus = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                        val isCharging = batteryStatus == BatteryManager.BATTERY_STATUS_CHARGING || batteryStatus == BatteryManager.BATTERY_STATUS_FULL
                        result.success(mapOf("batteryPercent" to batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY), "isCharging" to isCharging, "lowMemory" to memoryInfo.lowMemory))
                    }
                    "requestOmegaScreenCapture" -> {
                        if (pendingOmegaCaptureResult != null) result.error("CAPTURE_REQUEST_ACTIVE", "Already visible", null)
                        else if (OmegaScreenCaptureService.status()["running"] == true) result.success(OmegaScreenCaptureService.status())
                        else {
                            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                            pendingOmegaCaptureResult = result
                            startActivityForResult(manager.createScreenCaptureIntent(), OMEGA_CAPTURE_REQUEST)
                        }
                    }
                    "omegaScreenCaptureStatus" -> result.success(OmegaScreenCaptureService.status())
                    "omegaTimeWarpInfo" -> result.success(OmegaScreenCaptureService.timeWarpInfo((call.argument<Int>("secondsAgo") ?: 0).coerceIn(0, 180)))
                    "stopOmegaScreenCapture" -> { startService(Intent(this, OmegaScreenCaptureService::class.java).setAction(OmegaScreenCaptureService.ACTION_STOP)); result.success(mapOf("success" to true)) }
                    "openApp" -> { val launch = resolveLaunchIntent(call.argument<String>("packageName")?.trim().orEmpty()); if (launch == null) result.error("APP_NOT_FOUND", "Not found", null) else { startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(true) } }
                    "openUrl" -> { val url = call.argument<String>("url") ?: ""; require(url.startsWith("https://") || url.startsWith("http://")); startActivity(Intent(Intent.ACTION_VIEW, url.toUri())); result.success(true) }
                    "searchWeb" -> { val query = call.argument<String>("query")?.trim().orEmpty(); require(query.isNotEmpty()); val uri = "https://www.google.com/search".toUri().buildUpon().appendQueryParameter("q", query).build(); startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(true) }
                    "openPlayStore" -> {
                        val query = call.argument<String>("query")?.trim().orEmpty()
                        val packageName = call.argument<String>("packageName")?.trim().orEmpty()
                        require(query.isNotEmpty())
                        val marketUri = if (packageName.isNotEmpty()) "market://details?id=${Uri.encode(packageName)}".toUri() else "market://search?q=${Uri.encode(query)}&c=apps".toUri()
                        val webUri = if (packageName.isNotEmpty()) Uri.Builder().scheme("https").authority("play.google.com").path("/store/apps/details").appendQueryParameter("id", packageName).build() else Uri.Builder().scheme("https").authority("play.google.com").path("/store/search").appendQueryParameter("q", query).appendQueryParameter("c", "apps").build()
                        try { startActivity(Intent(Intent.ACTION_VIEW, marketUri).setPackage("com.android.vending").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) { startActivity(Intent(Intent.ACTION_VIEW, webUri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                        result.success(mapOf("success" to true))
                    }
                    "playYouTube" -> {
                        val query = call.argument<String>("query")?.trim().orEmpty()
                        require(query.isNotEmpty())
                        val searchUri = "https://www.youtube.com/results".toUri().buildUpon().appendQueryParameter("search_query", query).build()
                        startActivity(Intent(Intent.ACTION_VIEW, searchUri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(mapOf("success" to true))
                    }
                    "resolveGalleryImages" -> result.success(resolveGalleryImages(call.argument<String>("query")?.trim().orEmpty()))
                    "placeCellularCall" -> { val phone = call.argument<String>("phone").orEmpty().filter(Char::isDigit); require(phone.length >= 7); startActivity(Intent(Intent.ACTION_CALL, "tel:$phone".toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(true) }
                    "resolveContacts" -> result.success(resolveContacts(call.argument<String>("query")?.trim().orEmpty()))
                    "sendWhatsAppMessage" -> {
                        val phone = call.argument<String>("phone").orEmpty().filter(Char::isDigit)
                        val message = call.argument<String>("message")?.trim().orEmpty()
                        require(phone.length >= 7); require(message.isNotEmpty())
                        val uri = "https://wa.me/$phone".toUri().buildUpon().appendQueryParameter("text", message).build()
                        startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    "getRecentNotifications" -> result.success(MayaNotificationListenerService.recentNotifications())
                    "getScreenNodeTree" -> { if (service != null) result.success(service.getActiveScreenNodeTree()) else result.error("SERVICE_INACTIVE", "Enable accessibility", null) }
                    "shizukuStatus" -> result.success(shizukuStatus())
                    "requestShizukuPermission" -> {
                        if (!Shizuku.pingBinder()) result.error("SHIZUKU_NOT_RUNNING", "Start Shizuku", null)
                        else if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) result.success(mapOf("success" to true, "granted" to true))
                        else { pendingShizukuPermissionResult = result; Shizuku.requestPermission(SHIZUKU_PERMISSION_REQUEST) }
                    }
                    "startShizukuBridge" -> {
                        require(Shizuku.pingBinder())
                        require(Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED)
                        if (shizukuService != null) result.success(shizukuStatus()) else { pendingShizukuBindResult = result; bindShizukuIfReady(); scheduleShizukuBindTimeout() }
                    }
                    "shizukuLock" -> result.success(shizukuExecute(JSONObject().put("action", "lock")))
                    "shizukuUnlock" -> result.success(shizukuExecute(JSONObject().put("action", "unlock")))
                    "shizukuInputTap" -> result.success(shizukuExecute(JSONObject().put("action", "tap").put("x", call.argument<Int>("x") ?: 0).put("y", call.argument<Int>("y") ?: 0)))
                    "shizukuInputSwipe" -> result.success(shizukuExecute(JSONObject().put("action", "swipe").put("startX", call.argument<Int>("startX") ?: 0).put("startY", call.argument<Int>("startY") ?: 0).put("endX", call.argument<Int>("endX") ?: 0).put("endY", call.argument<Int>("endY") ?: 0).put("durationMs", call.argument<Int>("durationMs") ?: 300)))
                    "shizukuKeyEvent" -> result.success(shizukuExecute(JSONObject().put("action", "key").put("keyCode", call.argument<Int>("keyCode") ?: 0)))
                    "answerCall" -> { val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager; @Suppress("DEPRECATION") telecom.acceptRingingCall(); result.success(true) }
                    "rejectCall" -> { val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager; if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) { @Suppress("DEPRECATION") result.success(telecom.endCall()) } else result.success(false) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("ANDROID_ACTION_FAILED", e.message, null) }
        }

        val gatewayChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GATEWAY_CHANNEL)
        gatewayChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startOfflineGateway" -> { startForegroundService(Intent(this, GatewayForegroundService::class.java).apply { action = GatewayForegroundService.ACTION_START }); result.success(true) }
                "stopOfflineGateway" -> { startService(Intent(this, GatewayForegroundService::class.java).apply { action = GatewayForegroundService.ACTION_STOP }); result.success(true) }
                "isOfflineGatewayRunning" -> result.success(GatewayForegroundService.isGatewayRunning())
                else -> result.notImplemented()
            }
        }
    }

    private fun shizukuStatus(): Map<String, Any?> {
        val running = Shizuku.pingBinder()
        val granted = running && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        val health = if (shizukuService != null) shizukuExecute(JSONObject().put("action", "status")) else mapOf("success" to false)
        return mapOf("success" to true, "running" to running, "permissionGranted" to granted, "bridgeConnected" to (shizukuService != null), "bridgeResponsive" to (health["success"] == true))
    }

    private fun bindShizukuIfReady() {
        if (shizukuService != null || shizukuBinding) return
        if (!Shizuku.pingBinder()) return
        if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) return
        try { shizukuBinding = true; Shizuku.bindUserService(shizukuArgs, shizukuConnection) } catch (e: Throwable) { shizukuBinding = false }
    }

    private fun scheduleShizukuBindTimeout() {
        cancelShizukuBindTimeout()
        val timeout = Runnable { if (shizukuService == null) { shizukuBinding = false; pendingShizukuBindResult?.error("SHIZUKU_BIND_TIMEOUT", "Timeout 8s", null); pendingShizukuBindResult = null } }
        shizukuBindTimeout = timeout
        shizukuHandler.postDelayed(timeout, 8000L)
    }

    private fun cancelShizukuBindTimeout() { shizukuBindTimeout?.let(shizukuHandler::removeCallbacks); shizukuBindTimeout = null }

    private fun shizukuExecute(request: JSONObject): Map<String, Any?> {
        val service = shizukuService ?: return mapOf("success" to false, "error" to "Not connected")
        return try { val response = JSONObject(service.execute(request.toString())); response.keys().asSequence().associateWith { response.opt(it) } } catch (e: Throwable) { mapOf("success" to false, "error" to (e.message ?: e.javaClass.simpleName)) }
    }

    private fun requestBiometricConfirmation(reason: String, result: MethodChannel.Result) {
        val executor = ContextCompat.getMainExecutor(this)
        var completed = false
        val prompt = BiometricPrompt(this, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(authenticationResult: BiometricPrompt.AuthenticationResult) { if (!completed) { completed = true; result.success(mapOf("success" to true, "authenticated" to true)) } }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) { if (!completed) { completed = true; result.success(mapOf("success" to false, "authenticated" to false, "message" to errString.toString())) } }
        })
        val builder = BiometricPrompt.PromptInfo.Builder().setTitle("Maya security").setSubtitle(reason.take(160)).setConfirmationRequired(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) builder.setAllowedAuthenticators(Authenticators.BIOMETRIC_STRONG or Authenticators.DEVICE_CREDENTIAL) else { @Suppress("DEPRECATION") builder.setDeviceCredentialAllowed(true) }
        prompt.authenticate(builder.build())
    }

    private fun resolveGalleryImages(query: String): List<Map<String, Any>> {
        val images = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DISPLAY_NAME, MediaStore.Images.Media.DATE_ADDED)
        contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, null, null, "${MediaStore.Images.Media.DATE_ADDED} DESC")?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            while (cursor.moveToNext() && images.size < 8) {
                val id = cursor.getLong(idIndex)
                val uri = Uri.withAppendedPath(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id.toString())
                images.add(mapOf("uri" to uri.toString(), "name" to cursor.getString(nameIndex).orEmpty()))
            }
        }
        return images
    }

    private fun resolveContacts(query: String): List<Map<String, String>> {
        if (query.isBlank()) return emptyList()
        val matches = mutableListOf<Map<String, String>>()
        val projection = arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER)
        val selection = "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?"
        val args = arrayOf("%$query%")
        contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, projection, selection, args, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val phoneIndex = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (cursor.moveToNext() && matches.size < 12) {
                val name = cursor.getString(nameIndex).orEmpty()
                val phone = cursor.getString(phoneIndex).orEmpty().filter(Char::isDigit)
                if (phone.length >= 7) matches.add(mapOf("name" to name, "phone" to phone))
            }
        }
        return matches
    }

    private fun resolveLaunchIntent(query: String): Intent? {
        if (query.isBlank()) return null
        packageManager.getLaunchIntentForPackage(query)?.let { return it }
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val candidates = packageManager.queryIntentActivities(launcher, 0)
        val match = candidates.firstOrNull { it.loadLabel(packageManager).toString().equals(query, ignoreCase = true) } ?: candidates.firstOrNull { it.loadLabel(packageManager).toString().startsWith(query, ignoreCase = true) } ?: return null
        return packageManager.getLaunchIntentForPackage(match.activityInfo.packageName)
    }

    private fun startNativeSpeechRecognition(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) { result.error("MIC_PERMISSION", "Mic required", null); return }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) { result.error("NATIVE_STT_UNAVAILABLE", "Unavailable", null); return }
        val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
        var completed = false
        fun finishSuccess(value: String?) { if (completed) return; completed = true; result.success(value?.trim().orEmpty()); recognizer.destroy() }
        fun finishError(code: Int) { if (completed) return; completed = true; result.error("NATIVE_STT_$code", "Failed $code", null); recognizer.destroy() }
        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = Unit
            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() = Unit
            override fun onError(error: Int) = finishError(error)
            override fun onResults(results: Bundle?) { finishSuccess(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()) }
            override fun onPartialResults(partialResults: Bundle?) = Unit
            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply { putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM) }
        recognizer.startListening(intent)
        Handler(Looper.getMainLooper()).postDelayed({ if (!completed) { recognizer.stopListening(); finishError(SpeechRecognizer.ERROR_SPEECH_TIMEOUT) } }, 12000L)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == OMEGA_CAPTURE_REQUEST) {
            val pending = pendingOmegaCaptureResult
            pendingOmegaCaptureResult = null
            if (resultCode == RESULT_OK && data != null) {
                val serviceIntent = Intent(this, OmegaScreenCaptureService::class.java).setAction(OmegaScreenCaptureService.ACTION_START).putExtra(OmegaScreenCaptureService.EXTRA_RESULT_CODE, resultCode).putExtra(OmegaScreenCaptureService.EXTRA_RESULT_DATA, data)
                ContextCompat.startForegroundService(this, serviceIntent)
                pending?.success(mapOf("success" to true, "status" to "starting"))
            } else pending?.success(mapOf("success" to false, "status" to "denied"))
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        pendingOmegaCaptureResult?.error("ACTIVITY_DESTROYED", "Interrupted", null)
        pendingOmegaCaptureResult = null
        try { if (shizukuService != null) Shizuku.unbindUserService(shizukuArgs, shizukuConnection, true) } catch (_: Throwable) {}
        shizukuService = null
        if (::liveAudioBridge.isInitialized) liveAudioBridge.release()
        super.onDestroy()
    }
}