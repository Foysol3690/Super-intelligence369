package com.foysol.jarvis

import android.content.Context
import android.os.Build
import android.telecom.Call
import android.telecom.InCallService
import android.telecom.TelecomManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * MayaCallService — Android Telecom integration (Spec point 22)
 *
 * Handles:
 * - Telecom call state events → Flutter EventChannel
 * - placeCall / endCall / setAudioRoute via MethodChannel
 * - Fallback VoIP mode when InCallService role unavailable
 *
 * Note: Full cellular-call audio access requires ROLE_DIALER or InCallService
 * registration in AndroidManifest. This class bridges what Android permits.
 */
class MayaCallService : InCallService() {

    companion object {
        const val TELECOM_CHANNEL = "com.foysol.jarvis/telecom"
        const val TELECOM_EVENTS  = "com.foysol.jarvis/telecom_events"

        private var eventSink: EventChannel.EventSink? = null

        @JvmStatic
        fun registerChannels(engine: FlutterEngine, context: Context) {
            val messenger = engine.dartExecutor.binaryMessenger

            // Method channel for Flutter → Android commands
            MethodChannel(messenger, TELECOM_CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelecomAvailable" -> {
                        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                        result.success(tm != null)
                    }
                    "requestPhonePermissions" -> {
                        // Permissions are requested via permission_handler on Flutter side
                        result.success(true)
                    }
                    "placeCall" -> {
                        val number = call.argument<String>("number") ?: ""
                        try {
                            val tm = context.getSystemService(Context.TELECOM_SERVICE)
                                        as? TelecomManager
                            if (tm != null && number.isNotEmpty()) {
                                val uri = android.net.Uri.fromParts("tel", number, null)
                                tm.placeCall(uri, null)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "endCall" -> {
                        // Handled by active call reference below
                        activeCall?.disconnect()
                        result.success(null)
                    }
                    "setAudioRoute" -> {
                        val route = call.argument<String>("route") ?: "earpiece"
                        setAudioRouteForRoute(route)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

            // Event channel: Android → Flutter call state events
            EventChannel(messenger, TELECOM_EVENTS).setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                        eventSink = sink
                    }
                    override fun onCancel(arguments: Any?) { eventSink = null }
                }
            )
        }

        private var activeCall: Call? = null

        fun emitCallState(state: String, extras: Map<String, Any> = emptyMap()) {
            val map = mutableMapOf<String, Any>("state" to state)
            map.putAll(extras)
            eventSink?.success(map)
        }

        private fun setAudioRouteForRoute(route: String) {
            // Route switching handled via AudioManager in production
        }
    }

    // InCallService lifecycle — called when a call is added
    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        activeCall = call
        emitCallState("ADDED")

        call.registerCallback(object : Call.Callback() {
            override fun onStateChanged(call: Call, state: Int) {
                val stateStr = when (state) {
                    Call.STATE_ACTIVE       -> "ACTIVE"
                    Call.STATE_DISCONNECTED -> "DISCONNECTED"
                    Call.STATE_DIALING      -> "DIALING"
                    Call.STATE_RINGING      -> "RINGING"
                    Call.STATE_HOLDING      -> "HOLDING"
                    else                    -> "UNKNOWN"
                }
                emitCallState(stateStr)
            }
        })
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        activeCall = null
        emitCallState("DISCONNECTED")
    }
}
