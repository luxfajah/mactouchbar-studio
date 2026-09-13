package io.github.luxfajah.touchbar.audio

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

class MicStreamer(private val context: Context) {

    private val tag = "MicStreamer"

    companion object {
        const val SAMPLE_RATE = 48000
        const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        const val UDP_PORT = 9878
        const val CHUNK_SIZE = 960 // 480 samples = 10.0ms @ 48kHz
    }

    private var audioRecord: AudioRecord? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var autoGainControl: AutomaticGainControl? = null
    private var streamingThread: Thread? = null

    private val isStreaming = AtomicBoolean(false)
    private var isMuted = AtomicBoolean(false)
    private var gainMultiplier: Float = 1.0f
    private var noiseSuppressionEnabled: Boolean = true

    var onAudioLevelChanged: ((levelPercent: Int, isStreaming: Boolean) -> Unit)? = null
    var onStreamStateChanged: ((isStreaming: Boolean) -> Unit)? = null

    fun isStreaming(): Boolean = isStreaming.get()
    fun isMuted(): Boolean = isMuted.get()

    fun setMute(muted: Boolean) {
        isMuted.set(muted)
    }

    fun toggleMute(): Boolean {
        val next = !isMuted.get()
        isMuted.set(next)
        return next
    }

    fun setGain(gain: Float) {
        gainMultiplier = gain.coerceIn(0.0f, 3.0f)
    }

    fun getGain(): Float = gainMultiplier

    fun setNoiseSuppression(enabled: Boolean) {
        noiseSuppressionEnabled = enabled
        try {
            noiseSuppressor?.enabled = enabled
        } catch (e: Exception) {
            Log.w(tag, "Failed to toggle noise suppressor: ${e.message}")
        }
    }

    @SuppressLint("MissingPermission")
    fun startStreaming(macIp: String, port: Int = UDP_PORT): Boolean {
        if (isStreaming.get()) {
            Log.d(tag, "Mic is already streaming")
            return true
        }

        if (macIp.isBlank()) {
            Log.e(tag, "Cannot stream: Mac IP is blank")
            return false
        }

        val minBufSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        if (minBufSize <= 0) {
            Log.e(tag, "Invalid min buffer size: $minBufSize")
            return false
        }

        val bufferSize = maxOf(minBufSize, CHUNK_SIZE * 4)

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                audioRecord?.release()
                audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    SAMPLE_RATE,
                    CHANNEL_CONFIG,
                    AUDIO_FORMAT,
                    bufferSize
                )
            }

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(tag, "AudioRecord failed to initialize")
                audioRecord?.release()
                audioRecord = null
                return false
            }

            val sessionId = audioRecord!!.audioSessionId
            if (NoiseSuppressor.isAvailable()) {
                try {
                    noiseSuppressor = NoiseSuppressor.create(sessionId)?.apply {
                        enabled = noiseSuppressionEnabled
                    }
                } catch (e: Exception) {
                    Log.w(tag, "NoiseSuppressor init error: ${e.message}")
                }
            }

            if (AcousticEchoCanceler.isAvailable()) {
                try {
                    echoCanceler = AcousticEchoCanceler.create(sessionId)?.apply {
                        enabled = true
                    }
                } catch (e: Exception) {
                    Log.w(tag, "AcousticEchoCanceler init error: ${e.message}")
                }
            }

            if (AutomaticGainControl.isAvailable()) {
                try {
                    autoGainControl = AutomaticGainControl.create(sessionId)?.apply {
                        enabled = true
                    }
                } catch (e: Exception) {
                    Log.w(tag, "AutomaticGainControl init error: ${e.message}")
                }
            }

            audioRecord!!.startRecording()
            isStreaming.set(true)
            onStreamStateChanged?.invoke(true)

            streamingThread = Thread({
                var socket: DatagramSocket? = null
                try {
                    socket = DatagramSocket()
                    socket.sendBufferSize = 65536
                    val targetAddress = InetAddress.getByName(macIp)
                    val buffer = ShortArray(CHUNK_SIZE / 2) // 480 shorts = 960 bytes
                    val byteBuffer = ByteArray(CHUNK_SIZE)

                    Log.i(tag, "🎙️ Streaming microphone to $macIp:$port (UDP 48.0kHz PCM 16-bit Mono)")

                    while (isStreaming.get() && audioRecord != null) {
                        val readShorts = audioRecord!!.read(buffer, 0, buffer.size)
                        if (readShorts <= 0) continue

                        var sumSquares = 0.0
                        val muted = isMuted.get()
                        val gain = gainMultiplier

                        for (i in 0 until readShorts) {
                            var sample = buffer[i].toInt()
                            if (muted) {
                                sample = 0
                            } else if (gain != 1.0f) {
                                sample = (sample * gain).toInt().coerceIn(-32768, 32767)
                            }
                            sumSquares += sample * sample

                            // Little-endian PCM 16-bit
                            byteBuffer[i * 2] = (sample and 0xFF).toByte()
                            byteBuffer[i * 2 + 1] = ((sample shr 8) and 0xFF).toByte()
                        }

                        // Calculate RMS volume level percentage (0 to 100)
                        val rms = sqrt(sumSquares / readShorts)
                        val normalizedLevel = (rms / 32768.0 * 100.0 * 3.5).toInt().coerceIn(0, 100)
                        onAudioLevelChanged?.invoke(if (muted) 0 else normalizedLevel, true)

                        val packet = DatagramPacket(byteBuffer, readShorts * 2, targetAddress, port)
                        socket.send(packet)
                    }
                } catch (e: Exception) {
                    Log.e(tag, "Audio streaming exception: ${e.message}")
                } finally {
                    try {
                        socket?.close()
                    } catch (_: Exception) {}
                    onAudioLevelChanged?.invoke(0, false)
                }
            }, "TouchBar-MicStreamer-Thread")

            streamingThread?.priority = Thread.MAX_PRIORITY
            streamingThread?.start()
            return true

        } catch (e: Exception) {
            Log.e(tag, "Failed to start microphone streaming: ${e.message}")
            stopStreaming()
            return false
        }
    }

    fun stopStreaming() {
        if (!isStreaming.getAndSet(false)) return

        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (e: Exception) {
            Log.w(tag, "Error stopping AudioRecord: ${e.message}")
        } finally {
            audioRecord = null
        }

        try {
            noiseSuppressor?.release()
            echoCanceler?.release()
            autoGainControl?.release()
        } catch (_: Exception) {}

        noiseSuppressor = null
        echoCanceler = null
        autoGainControl = null

        try {
            streamingThread?.interrupt()
            streamingThread = null
        } catch (_: Exception) {}

        onAudioLevelChanged?.invoke(0, false)
        onStreamStateChanged?.invoke(false)
        Log.i(tag, "🛑 Microphone streaming stopped")
    }

    fun release() {
        stopStreaming()
    }
}
