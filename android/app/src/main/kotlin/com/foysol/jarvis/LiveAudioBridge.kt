package com.foysol.jarvis

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Native full-duplex PCM bridge used by Maya's Gemini Live session. */
class LiveAudioBridge(private val activity: Activity) {
    companion object {
        const val METHOD_CHANNEL = "com.foysol.jarvis/live_audio"
        const val EVENT_CHANNEL = "com.foysol.jarvis/live_audio_input"
        private const val INPUT_RATE = 16000
        private const val OUTPUT_RATE = 24000
    }

    private var eventSink: EventChannel.EventSink? = null
    private var recorder: AudioRecord? = null
    private var player: AudioTrack? = null
    private val capturing = AtomicBoolean(false)
    private var captureExecutor: ExecutorService? = null
    private var playbackExecutor: ExecutorService? = null
    private var previousAudioMode: Int? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null

    fun configure(messenger: BinaryMessenger) {
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCapture" -> try {
                    startCapture()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("CAPTURE_START_FAILED", e.message, null)
                }
                "stopCapture" -> {
                    stopCapture()
                    result.success(true)
                }
                "playPcm" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("EMPTY_AUDIO", "No PCM bytes supplied", null)
                    } else try {
                        playPcm(bytes)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PLAYBACK_FAILED", e.message, null)
                    }
                }
                "clearPlayback" -> {
                    clearPlayback()
                    result.success(true)
                }
                "stopAll" -> {
                    release()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Synchronized
    private fun startCapture() {
        if (capturing.get()) return
        if (ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.RECORD_AUDIO,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Microphone permission is required for live audio")
        }
        try {
            ContextCompat.startForegroundService(
                activity,
                Intent(activity, MayaVoiceForegroundService::class.java),
            )
        } catch (_: Exception) {
            // Capture can continue while the Activity remains foreground.
        }
        configureCommunicationAudio()
        val minimum = AudioRecord.getMinBufferSize(
            INPUT_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        require(minimum > 0) { "16 kHz microphone PCM is unsupported" }
        val bufferSize = maxOf(minimum * 2, 3200)
        val audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            INPUT_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )
        if (audioRecord.state != AudioRecord.STATE_INITIALIZED) {
            audioRecord.release()
            error("Microphone could not initialize")
        }
        // Hardware AEC/NS is the first defence against Maya hearing her
        // own speaker audio. The Dart queue guard is the reliable fallback
        // on devices whose vendor AEC implementation is weak.
        try {
            if (AcousticEchoCanceler.isAvailable()) {
                echoCanceler = AcousticEchoCanceler.create(audioRecord.audioSessionId)?.apply {
                    enabled = true
                }
            }
            if (NoiseSuppressor.isAvailable()) {
                noiseSuppressor = NoiseSuppressor.create(audioRecord.audioSessionId)?.apply {
                    enabled = true
                }
            }
        } catch (_: Exception) {
            // Some vendor audio HALs reject effects; PCM capture still works.
        }
        recorder = audioRecord
        capturing.set(true)
        audioRecord.startRecording()
        captureExecutor?.shutdownNow()
        captureExecutor = Executors.newSingleThreadExecutor().also { executor ->
            executor.execute {
                // Exact supplied Maya voice transport: 320 PCM16 frames = 20 ms at 16 kHz.
                val chunk = ByteArray(640)
                try {
                    while (capturing.get()) {
                        val read = audioRecord.read(chunk, 0, chunk.size)
                        if (read > 0) {
                            val payload = if (read == chunk.size) chunk.clone() else chunk.copyOf(read)
                            activity.runOnUiThread { eventSink?.success(payload) }
                        } else if (read < 0) {
                            activity.runOnUiThread {
                                eventSink?.error("CAPTURE_READ_FAILED", "AudioRecord error $read", null)
                            }
                            break
                        }
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread {
                        eventSink?.error("CAPTURE_EXCEPTION", e.message, null)
                    }
                }
            }
        }
    }

    @Synchronized
    private fun stopCapture() {
        capturing.set(false)
        try { recorder?.stop() } catch (_: Exception) {}
        try { recorder?.release() } catch (_: Exception) {}
        try { echoCanceler?.release() } catch (_: Exception) {}
        try { noiseSuppressor?.release() } catch (_: Exception) {}
        echoCanceler = null
        noiseSuppressor = null
        recorder = null
        captureExecutor?.shutdownNow()
        captureExecutor = null
    }

    @Synchronized
    private fun ensurePlayer(): AudioTrack {
        val existing = player
        if (existing != null && existing.state == AudioTrack.STATE_INITIALIZED) return existing
        configureCommunicationAudio()
        val minimum = AudioTrack.getMinBufferSize(
            OUTPUT_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        require(minimum > 0) { "24 kHz speaker PCM is unsupported" }
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(OUTPUT_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(maxOf(minimum * 4, 19200))
            .build()
        if (track.state != AudioTrack.STATE_INITIALIZED) {
            track.release()
            error("Speaker output could not initialize")
        }
        track.play()
        player = track
        playbackExecutor?.shutdownNow()
        playbackExecutor = Executors.newSingleThreadExecutor()
        return track
    }

    private fun playPcm(bytes: ByteArray) {
        val track = ensurePlayer()
        val executor = playbackExecutor ?: Executors.newSingleThreadExecutor().also {
            playbackExecutor = it
        }
        executor.execute {
            var offset = 0
            while (offset < bytes.size) {
                val written = track.write(bytes, offset, bytes.size - offset, AudioTrack.WRITE_BLOCKING)
                if (written <= 0) break
                offset += written
            }
        }
    }

    @Synchronized
    private fun clearPlayback() {
        try {
            player?.pause()
            player?.flush()
            player?.play()
        } catch (_: Exception) {}
    }

    private fun configureCommunicationAudio() {
        val manager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (previousAudioMode == null) previousAudioMode = manager.mode
        manager.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        run { manager.isSpeakerphoneOn = true }
    }

    @Synchronized
    fun release() {
        stopCapture()
        try {
            activity.stopService(Intent(activity, MayaVoiceForegroundService::class.java))
        } catch (_: Exception) {}
        playbackExecutor?.shutdownNow()
        playbackExecutor = null
        try {
            player?.pause()
            player?.flush()
            player?.stop()
            player?.release()
        } catch (_: Exception) {}
        player = null
        val manager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        previousAudioMode?.let { manager.mode = it }
        previousAudioMode = null
    }
}
