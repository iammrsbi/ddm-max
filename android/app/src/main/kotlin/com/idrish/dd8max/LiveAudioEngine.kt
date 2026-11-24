package com.idrish.dd8max

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.AudioManager
import android.media.audiofx.NoiseSuppressor
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import kotlin.math.max

class LiveAudioEngine {
    @Volatile private var running = false
    private var recorder: AudioRecord? = null
    private var track: AudioTrack? = null
    private var worker: Thread? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var gainController: AutomaticGainControl? = null
    @Volatile var noiseSuppressorActive: Boolean = false
        private set
    @Volatile var echoCancelerActive: Boolean = false
        private set

    @Synchronized fun start(delayMs: Int, feedback: Double, mix: Double, level: Double, noiseReduction: Boolean, noiseGate: Boolean, ancLevel: Double) {
        stop()
        val rate = 44100
        val minIn = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val minOut = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minIn <= 0 || minOut <= 0) throw IllegalStateException("Audio device unavailable")
        val size = max(4096, max(minIn, minOut))
        val input = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size)
        val output = AudioTrack(AudioManager.STREAM_MUSIC, rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT, size, AudioTrack.MODE_STREAM)
        if (input.state != AudioRecord.STATE_INITIALIZED || output.state != AudioTrack.STATE_INITIALIZED) {
            input.release(); output.release()
            throw IllegalStateException("Mic ya speaker initialize nahi hua")
        }
        recorder = input; track = output
        // Enable Android device voice-processing effects when available.
        try {
            if (NoiseSuppressor.isAvailable()) {
                noiseSuppressor = NoiseSuppressor.create(input.audioSessionId)
                noiseSuppressor?.enabled = true
                noiseSuppressorActive = noiseSuppressor?.enabled == true
            }
        } catch (_: Exception) { noiseSuppressorActive = false }
        try {
            if (AcousticEchoCanceler.isAvailable()) {
                echoCanceler = AcousticEchoCanceler.create(input.audioSessionId)
                echoCanceler?.enabled = true
                echoCancelerActive = echoCanceler?.enabled == true
            }
        } catch (_: Exception) { echoCancelerActive = false }
        try {
            if (AutomaticGainControl.isAvailable()) {
                gainController = AutomaticGainControl.create(input.audioSessionId)
                gainController?.enabled = true
            }
        } catch (_: Exception) {}
        val delaySamples = max(1, rate * delayMs.coerceIn(40,1200) / 1000)
        val ring = FloatArray(delaySamples)
        val fb = feedback.coerceIn(0.0,0.92).toFloat()
        val wet = mix.coerceIn(0.0,1.0).toFloat()
        val gain = level.coerceIn(0.0,1.5).toFloat()
        running = true
        input.startRecording(); output.play()
        worker = Thread {
            val ins = ShortArray(512); val outs = ShortArray(512); var cursor = 0; var previousInput = 0.0f; var previousHigh = 0.0f
            while (running) {
                val count = input.read(ins,0,ins.size)
                if (count <= 0) continue
                for (i in 0 until count) {
                    val raw = ins[i] / 32768.0f
                    val high = if (noiseReduction) {
                        val filtered = 0.995f * (previousHigh + raw - previousInput)
                        previousInput = raw
                        previousHigh = filtered
                        filtered
                    } else raw
                    val strength = ancLevel.coerceIn(0.0, 1.0).toFloat()
                    val cleaned = raw * (1.0f - strength) + high * strength
                    val magnitude = kotlin.math.abs(cleaned)
                    val threshold = 0.004f + 0.018f * strength
                    val gate = if (!noiseGate) 1.0f else if (magnitude < threshold) 0.10f else if (magnitude < threshold * 2.2f) 0.10f + (magnitude - threshold) / (threshold * 1.2f) * 0.90f else 1.0f
                    val dry = cleaned * gate
                    val echo = ring[cursor]
                    ring[cursor] = (dry + echo * fb).coerceIn(-1.0f,1.0f)
                    val mixed = ((dry * (1.0f-wet)) + ((dry+echo)*wet))*gain
                    outs[i] = (mixed.coerceIn(-1.0f,0.999969f)*32767.0f).toInt().toShort()
                    cursor++; if(cursor>=ring.size) cursor=0
                }
                output.write(outs,0,count)
            }
        }.apply { name="DDM-Live-Audio"; start() }
    }
    @Synchronized fun stop() {
        running=false
        try { worker?.join(500) } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
        worker=null
        try { recorder?.stop() } catch (_: Exception) {}
        try { track?.pause(); track?.flush(); track?.stop() } catch (_: Exception) {}
        try { noiseSuppressor?.release() } catch (_: Exception) {}
        try { echoCanceler?.release() } catch (_: Exception) {}
        try { gainController?.release() } catch (_: Exception) {}
        noiseSuppressor=null; echoCanceler=null; gainController=null
        noiseSuppressorActive=false; echoCancelerActive=false
        recorder?.release(); track?.release(); recorder=null; track=null
    }
}