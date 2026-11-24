package com.idrish.dd8max

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.AudioManager
import android.media.audiofx.NoiseSuppressor
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.pow

class LiveAudioEngine {
    @Volatile private var running = false
    private var recorder: AudioRecord? = null
    private var track: AudioTrack? = null
    private var worker: Thread? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var gainController: AutomaticGainControl? = null

    @Volatile private var delaySamples = 14112
    @Volatile private var feedbackValue = 0.38f
    @Volatile private var mixValue = 0.45f
    @Volatile private var levelValue = 0.8f
    @Volatile private var noiseReductionValue = true
    @Volatile private var noiseGateValue = true
    @Volatile private var ancLevelValue = 0.65f
    @Volatile private var dualValue = false
    @Volatile private var pingPongValue = false
    @Volatile private var bypassValue = false
    @Volatile private var modeValue = 0
    @Volatile private var eqGains = FloatArray(5)

    @Volatile var noiseSuppressorActive: Boolean = false
        private set
    @Volatile var echoCancelerActive: Boolean = false
        private set

    @Synchronized fun update(
        delayMs: Int, feedback: Double, mix: Double, level: Double,
        noiseReduction: Boolean, noiseGate: Boolean, ancLevel: Double,
        dual: Boolean, pingPong: Boolean, bypass: Boolean, eq: List<Double>, mode: Int
    ) {
        delaySamples = (44100L * delayMs.coerceIn(40, 1200) / 1000L).toInt().coerceAtLeast(1)
        feedbackValue = feedback.coerceIn(0.0, 0.92).toFloat()
        mixValue = mix.coerceIn(0.0, 1.0).toFloat()
        levelValue = level.coerceIn(0.0, 1.5).toFloat()
        noiseReductionValue = noiseReduction
        noiseGateValue = noiseGate
        ancLevelValue = ancLevel.coerceIn(0.0, 1.0).toFloat()
        dualValue = dual
        pingPongValue = pingPong
        bypassValue = bypass
        modeValue = mode.coerceIn(0, 5)
        eqGains = FloatArray(5) { i -> (eq.getOrNull(i) ?: 0.0).coerceIn(-12.0, 12.0).toFloat() }
    }

    @Synchronized fun start(
        delayMs: Int, feedback: Double, mix: Double, level: Double,
        noiseReduction: Boolean, noiseGate: Boolean, ancLevel: Double,
        dual: Boolean, pingPong: Boolean, bypass: Boolean, eq: List<Double>, mode: Int
    ) {
        stop()
        update(delayMs, feedback, mix, level, noiseReduction, noiseGate, ancLevel, dual, pingPong, bypass, eq, mode)
        val rate = 44100
        val minIn = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val minOut = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        if (minIn <= 0 || minOut <= 0) throw IllegalStateException("Audio device unavailable")
        val size = max(8192, max(minIn, minOut))
        val input = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size)
        val output = AudioTrack(AudioManager.STREAM_MUSIC, rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT, size, AudioTrack.MODE_STREAM)
        if (input.state != AudioRecord.STATE_INITIALIZED || output.state != AudioTrack.STATE_INITIALIZED) {
            input.release()
            output.release()
            throw IllegalStateException("Mic ya speaker initialize nahi hua")
        }
        recorder = input
        track = output

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

        val ring = FloatArray(rate * 3 + 1)
        val inputSamples = ShortArray(512)
        val outputSamples = ShortArray(1024)
        val lowPass = FloatArray(5)
        val cutoffs = floatArrayOf(100f, 350f, 1000f, 3500f, 9000f)
        val alphas = FloatArray(5) { i -> (1.0 - exp((-2.0 * PI * cutoffs[i] / rate))).toFloat() }
        var gateGain = 1.0f
        var echoTone = 0.0f

        running = true
        input.startRecording()
        output.play()
        worker = Thread {
            var cursor = 0
            var previousInput = 0.0f
            var previousHigh = 0.0f
            while (running) {
                val count = input.read(inputSamples, 0, inputSamples.size)
                if (count <= 0) continue
                for (i in 0 until count) {
                    val raw = inputSamples[i] / 32768.0f
                    val strength = ancLevelValue
                    // Adjustable speech high-pass: stronger setting removes more low-frequency rumble.
                    val cutoffHz = 75.0f + 135.0f * strength
                    val hpAlpha = (rate / (rate + 2.0 * PI * cutoffHz)).toFloat()
                    val high = if (noiseReductionValue) {
                        val filtered = hpAlpha * (previousHigh + raw - previousInput)
                        previousInput = raw
                        previousHigh = filtered
                        filtered
                    } else raw
                    val cleaned = raw * (1.0f - strength) + high * strength
                    val magnitude = abs(cleaned)
                    val threshold = 0.0018f + 0.009f * strength
                    val targetGate = if (!noiseGateValue) 1.0f else if (magnitude < threshold) 0.06f else if (magnitude < threshold * 2.0f) {
                        0.06f + (magnitude - threshold) / threshold * 0.94f
                    } else 1.0f
                    // Fast attenuation, slower recovery to avoid chopping the start of words.
                    val smoothing = if (targetGate < gateGain) 0.24f else 0.035f
                    gateGain += (targetGate - gateGain) * smoothing

                    var dry = cleaned * gateGain
                    if (!bypassValue) {
                        val gains = eqGains
                        val bands = FloatArray(5)
                        for (band in 0..4) {
                            lowPass[band] += alphas[band] * (dry - lowPass[band])
                            bands[band] = if (band == 0) lowPass[0] else lowPass[band] - lowPass[band - 1]
                        }
                        var equalized = dry
                        for (band in 0..4) {
                            val linearGain = 10.0.pow(gains[band] / 20.0).toFloat()
                            equalized += bands[band] * (linearGain - 1.0f)
                        }
                        dry = equalized.coerceIn(-1.0f, 1.0f)
                    }

                    val delay = delaySamples.coerceIn(1, ring.size / 2)
                    val firstIndex = (cursor - delay + ring.size) % ring.size
                    val secondIndex = (cursor - delay * 2 + ring.size * 2) % ring.size
                    val firstEcho = if (bypassValue) 0.0f else ring[firstIndex]
                    val secondEcho = if (!bypassValue && dualValue) ring[secondIndex] * 0.55f else 0.0f
                    var echo = firstEcho + secondEcho
                    when (modeValue) {
                        1 -> { echoTone += 0.20f * (echo - echoTone); echo = echoTone }
                        2 -> { echoTone += 0.12f * (echo - echoTone); echo = (kotlin.math.tanh(echoTone * 1.25f)).toFloat() }
                        3 -> { echoTone += 0.075f * (echo - echoTone); echo = echoTone }
                        4 -> {
                            echoTone += 0.24f * (echo - echoTone)
                            val wobble = 0.88f + 0.12f * kotlin.math.sin(2.0 * PI * cursor / (rate * 2.8)).toFloat()
                            echo = echoTone * wobble
                        }
                    }
                    ring[cursor] = (dry + (firstEcho + secondEcho) * feedbackValue).coerceIn(-1.0f, 1.0f)

                    val wet = if (bypassValue) 0.0f else mixValue
                    val gain = levelValue
                    val mono = ((dry * (1.0f - wet)) + ((dry + echo) * wet)) * gain
                    val left: Float
                    val right: Float
                    if (pingPongValue && !bypassValue) {
                        val repeatNumber = (cursor.toLong() / delay.toLong()).toInt()
                        val panRight = repeatNumber % 2 == 1
                        left = (if (panRight) dry * (1.0f - wet) else mono).coerceIn(-1.0f, 0.999969f)
                        right = (if (panRight) mono else dry * (1.0f - wet)).coerceIn(-1.0f, 0.999969f)
                    } else {
                        left = mono.coerceIn(-1.0f, 0.999969f)
                        right = mono.coerceIn(-1.0f, 0.999969f)
                    }
                    outputSamples[i * 2] = (left * 32767.0f).toInt().toShort()
                    outputSamples[i * 2 + 1] = (right * 32767.0f).toInt().toShort()
                    cursor++
                    if (cursor >= ring.size) cursor = 0
                }
                output.write(outputSamples, 0, count * 2)
            }
        }.apply { name = "DDM-Live-Audio"; start() }
    }

    @Synchronized fun stop() {
        running = false
        try { recorder?.stop() } catch (_: Exception) {}
        try { worker?.join(700) } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
        worker = null
        try { track?.pause(); track?.flush(); track?.stop() } catch (_: Exception) {}
        try { noiseSuppressor?.release() } catch (_: Exception) {}
        try { echoCanceler?.release() } catch (_: Exception) {}
        try { gainController?.release() } catch (_: Exception) {}
        noiseSuppressor = null
        echoCanceler = null
        gainController = null
        noiseSuppressorActive = false
        echoCancelerActive = false
        try { recorder?.release() } catch (_: Exception) {}
        try { track?.release() } catch (_: Exception) {}
        recorder = null
        track = null
    }
}
