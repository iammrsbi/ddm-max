package com.idrish.dd8max

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.AudioManager
import kotlin.math.max

class LiveAudioEngine {
    @Volatile private var running = false
    private var recorder: AudioRecord? = null
    private var track: AudioTrack? = null
    private var worker: Thread? = null

    @Synchronized fun start(delayMs: Int, feedback: Double, mix: Double, level: Double) {
        stop()
        val rate = 44100
        val minIn = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val minOut = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minIn <= 0 || minOut <= 0) throw IllegalStateException("Audio device unavailable")
        val size = max(4096, max(minIn, minOut))
        val input = AudioRecord(MediaRecorder.AudioSource.MIC, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size)
        val output = AudioTrack(AudioManager.STREAM_MUSIC, rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT, size, AudioTrack.MODE_STREAM)
        if (input.state != AudioRecord.STATE_INITIALIZED || output.state != AudioTrack.STATE_INITIALIZED) {
            input.release(); output.release()
            throw IllegalStateException("Mic ya speaker initialize nahi hua")
        }
        recorder = input; track = output
        val delaySamples = max(1, rate * delayMs.coerceIn(40,1200) / 1000)
        val ring = FloatArray(delaySamples)
        val fb = feedback.coerceIn(0.0,0.92).toFloat()
        val wet = mix.coerceIn(0.0,1.0).toFloat()
        val gain = level.coerceIn(0.0,1.5).toFloat()
        running = true
        input.startRecording(); output.play()
        worker = Thread {
            val ins = ShortArray(512); val outs = ShortArray(512); var cursor = 0
            while (running) {
                val count = input.read(ins,0,ins.size)
                if (count <= 0) continue
                for (i in 0 until count) {
                    val dry = ins[i] / 32768.0f
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
        recorder?.release(); track?.release(); recorder=null; track=null
    }
}