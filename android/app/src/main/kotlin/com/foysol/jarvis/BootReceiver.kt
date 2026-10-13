package com.foysol.jarvis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.i(TAG, "Boot event received: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.PACKAGE_REPLACED"
        ) {
            // GOD MODE: Don't start service directly, use WorkManager to bypass Android 12+ ban
            try {
                val workRequest = OneTimeWorkRequestBuilder<BootWorker>().build()
                WorkManager.getInstance(context).enqueue(workRequest)
                Log.i(TAG, "Enqueued immortal boot worker")
            } catch (e: Exception) {
                Log.e(TAG, "WorkManager failed, falling back to direct", e)
                // Fallback for direct boot
                tryStartService(context)
            }
        }
    }

    private fun tryStartService(context: Context) {
        try {
            val serviceIntent = Intent(context, GatewayForegroundService::class.java).apply {
                action = GatewayForegroundService.ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start Gateway Service on boot", e)
        }
    }

    // IMMORTAL WORKER - This is what actually starts your service after boot
    class BootWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
        override fun doWork(): Result {
            Log.i(TAG, "BootWorker running - starting services")
            val context = applicationContext
            
            // Start ALL your core services
            val services = listOf(
                GatewayForegroundService::class.java,
                MayaVoiceForegroundService::class.java
            )

            for (serviceClass in services) {
                try {
                    val intent = Intent(context, serviceClass).apply {
                        action = GatewayForegroundService.ACTION_START
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start ${serviceClass.simpleName}", e)
                }
            }
            return Result.success()
        }
    }
}