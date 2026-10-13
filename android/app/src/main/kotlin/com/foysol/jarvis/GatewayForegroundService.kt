package com.foysol.jarvis

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlin.concurrent.thread

class GatewayForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "jarvis_offline_gateway"
        const val NOTIFICATION_ID = 4201
        const val ACTION_START = "com.foysol.jarvis.action.START_GATEWAY"
        const val ACTION_STOP = "com.foysol.jarvis.action.STOP_GATEWAY"
        private const val TAG = "GatewayService"
        private const val WATCHDOG_INTERVAL_MS = 5_000L

        fun isPythonReady(): Boolean = Python.isStarted()

        fun isGatewayRunning(): Boolean {
            return try {
                if (!Python.isStarted()) return false
                val py = Python.getInstance()
                val module: PyObject = py.getModule("offline_server")
                module.callAttr("is_running").toBoolean()
            } catch (e: Exception) {
                false
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var watchdogActive = false
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private val watchdogRunnable = object : Runnable {
        override fun run() {
            if (watchdogActive) {
                try {
                    if (Python.isStarted() && !isGatewayRunning()) {
                        Log.w(TAG, "Gateway dropped - GOD RESTARTING")
                        startOfflineGateway()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Watchdog failed", e)
                }
                handler.postDelayed(this, WATCHDOG_INTERVAL_MS)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        // GOD MODE LOCKS - Prevents CPU sleep
        val powerManager = getSystemService(PowerManager::class.java)
        wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Maya::GatewayLock")?.apply {
            acquire(10*60*60*1000L /*10 hours*/)
        }

        val wifiManager = applicationContext.getSystemService(WifiManager::class.java)
        wifiLock = wifiManager?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Maya::GatewayWifi")?.apply {
            acquire()
        }

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(applicationContext))
        }
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopWatchdog()
                releaseLocks()
                stopOfflineGateway()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val notification = buildNotification()
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startForeground(
                            NOTIFICATION_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or 
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                        )
                    } else {
                        startForeground(NOTIFICATION_ID, notification)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "startForeground failed", e)
                    // Fallback for Android 14 crash
                    try { startForeground(NOTIFICATION_ID, notification) } catch (_: Exception) {}
                }
                startOfflineGateway()
                startWatchdog()
            }
        }
        return START_REDELIVER_INTENT // GOD MODE: If killed, Android will re-deliver last intent
    }

    private fun startOfflineGateway() {
        thread(isDaemon = false, name = "Maya-Gateway-Thread") {
            try {
                // Set thread priority to max
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)
                val py = Python.getInstance()
                val module: PyObject = py.getModule("offline_server")
                module.callAttr("start_server")
                Log.i(TAG, "Offline gateway GOD started")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start gateway", e)
                // Auto retry in 3 sec
                handler.postDelayed({ startOfflineGateway() }, 3000)
            }
        }
    }

    private fun stopOfflineGateway() {
        if (!Python.isStarted()) return
        try {
            val py = Python.getInstance()
            val module: PyObject = py.getModule("offline_server")
            module.callAttr("stop_server")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping gateway", e)
        }
    }

    private fun startWatchdog() {
        if (!watchdogActive) {
            watchdogActive = true
            handler.postDelayed(watchdogRunnable, WATCHDOG_INTERVAL_MS)
        }
    }

    private fun stopWatchdog() {
        watchdogActive = false
        handler.removeCallbacks(watchdogRunnable)
    }

    private fun releaseLocks() {
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        try { if (wifiLock?.isHeld == true) wifiLock?.release() } catch (_: Exception) {}
    }

    override fun onDestroy() {
        stopWatchdog()
        releaseLocks()
        stopOfflineGateway()
        // GOD MODE RESURRECTION - If system kills us, restart in 1 sec
        val restartIntent = Intent(this, BootReceiver::class.java).apply {
            action = Intent.ACTION_BOOT_COMPLETED
        }
        sendBroadcast(restartIntent)
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // User swiped away app - DON'T DIE, restart
        val restartIntent = Intent(applicationContext, GatewayForegroundService::class.java).apply {
            action = ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            applicationContext.startForegroundService(restartIntent)
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Maya Offline Gateway",
            NotificationManager.IMPORTANCE_LOW // Changed from MIN to LOW so user sees it's alive
        ).apply {
            description = "Quantum AI Core - Unkillable"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent, 
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MAYA NEXØRA • Quantum Core")
            .setContentText("Offline gateway active • God Mode")
            .setSubText("Unkillable • ${if(isGatewayRunning()) "AI Online" else "AI Booting..."}")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .setOnlyAlertOnce(true)
            .build()
    }
}