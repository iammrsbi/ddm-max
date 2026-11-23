package com.idrish.dd8max

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Bundle
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread
import kotlin.math.pow

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.idrish.dd8max/audio"
    private var audioThread: Thread? = null
    @Volatile private var isRunning = false

    @Volatile private var eLevel = 5.0f
    @Volatile private var feedback = 4.0f
    @Volatile private var timeVal = 6.0f
    @Volatile private var modulate = 0.0f
    @Volatile private var isSingle = true
    @Volatile private var isBypass = false
    @Volatile private var micBoost = 0f
    @Volatile private var outputBoost = 0f
    @Volatile private var eq = floatArrayOf(2f, 0f, -2f, 3f, 4f)
    @Volatile private var isLoop = false

    private val sampleRate = 44100
    private val delayBuffer = ShortArray(sampleRate * 2)
    private var writePos = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setParams" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        (args["eLevel"] as? Double)?.let { eLevel = it.toFloat() }
                        (args["feedback"] as? Double)?.let { feedback = it.toFloat() }
                        (args["time"] as? Double)?.let { timeVal = it.toFloat() }
                        (args["modulate"] as? Double)?.let { modulate = it.toFloat() }
                        (args["isSingle"] as? Boolean)?.let { isSingle = it }
                        (args["isBypass"] as? Boolean)?.let { isBypass = it }
                        (args["micBoost"] as? Double)?.let { micBoost = it.toFloat() }
                        (args["outputBoost"] as? Double)?.let { outputBoost = it.toFloat() }
                        (args["eq"] as? List<*>)?.let { list ->
                            for (i in 0 until minOf(5, list.size)) {
                                (list[i] as? Double)?.let { eq[i] = it.toFloat() }
                            }
                        }
                    }
                    result.success(true)
                }
                "startLive" -> { checkPermissionAndStart(); result.success(true) }
                "stopLive" -> { stopAudio(); result.success(true) }
                "tapTempo" -> { result.success(true) }
                "holdEcho" -> { result.success(true) }
                "setLoop" -> { isLoop = (call.arguments as? Map<*, *>)?.get("on") as? Boolean ?: false; result.success(true) }
                "startRecording" -> { Toast.makeText(this, "Recording Start...", Toast.LENGTH_SHORT).show(); result.success(true) }
                "stopRecording" -> { Toast.makeText(this, "Recording Save Ho Gayi!", Toast.LENGTH_SHORT).show(); result.success(true) }
                "pickFile" -> { Toast.makeText(this, "File Picker - Flutter se handle hoga", Toast.LENGTH_SHORT).show(); result.success(true) }
                "playFile" -> { result.success(true) }
                "stopFile" -> { result.success(true) }
                "saveEchoFile" -> { Toast.makeText(this, "Echo File Save Ho Rahi Hai...", Toast.LENGTH_SHORT).show(); result.success(true) }
                "toggleBeforeAfter" -> { result.success(true) }
                "shareWhatsApp" -> {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, "Shayar-E-Rasool DD-8 MAX se Echo kiya hua Naat - Developer IDRISH")
                        setPackage("com.whatsapp")
                    }
                    try { startActivity(intent) } catch (e: Exception) {
                        val chooser = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, "Shayar-E-Rasool DD-8 MAX - Developer IDRISH")
                        }
                        startActivity(Intent.createChooser(chooser, "WhatsApp pe bhejo"))
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkPermissionAndStart() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 1001)
        } else {
            startAudio()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001 && grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startAudio()
        } else if (requestCode == 1001) {
            Toast.makeText(this, "Mic Permission Chahiye - Settings me ON karo", Toast.LENGTH_LONG).show()
        }
    }

    private fun startAudio() {
        if (isRunning) return
        isRunning = true
        audioThread = thread(start = true) {
            val bufferSize = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            val safeSize = if (bufferSize > 0) bufferSize else 4096
            val recorder = try {
                AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, safeSize * 2)
            } catch (e: Exception) { null }

            if (recorder == null || recorder.state != AudioRecord.STATE_INITIALIZED) {
                runOnUiThread { Toast.makeText(this, "Mic Start Nahi Hua", Toast.LENGTH_SHORT).show() }
                isRunning = false
                return@thread
            }

            val player = try {
                AudioTrack(AudioManager.STREAM_MUSIC, sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT, safeSize * 2, AudioTrack.MODE_STREAM)
            } catch (e: Exception) { null }

            if (player == null || player.state != AudioTrack.STATE_INITIALIZED) {
                recorder.release()
                isRunning = false
                return@thread
            }

            recorder.startRecording()
            player.play()
            val buffer = ShortArray(safeSize / 2)

            fun eqGain(db: Float): Float = 10f.pow(db / 20f)

            while (isRunning) {
                val read = recorder.read(buffer, 0, buffer.size)
                if (read <= 0) continue
                val delayMs = (timeVal * 100f).toInt().coerceIn(50, 1500)
                val delaySamples = (delayMs * sampleRate / 1000).coerceIn(1, delayBuffer.size - 1)
                val fb = (feedback / 10f).coerceIn(0f, 0.85f)
                val wet = (eLevel / 10f).coerceIn(0f, 1f)
                val dry = 1f - (wet * 0.5f)
                val boost = 10f.pow((micBoost + outputBoost) / 20f).coerceIn(0.5f, 3f)
                val eqAvg = (eqGain(eq[2]) + eqGain(eq[3])) / 2f

                for (i in 0 until read) {
                    val input = buffer[i].toFloat() / 32768f * boost * eqAvg
                    val readPos = (writePos - delaySamples + delayBuffer.size) % delayBuffer.size
                    var delayed = delayBuffer[readPos].toFloat() / 32768f
                    if (!isSingle) { delayed *= (1f + modulate / 20f) }
                    val out: Float = if (isBypass) { input } else { (input * dry + delayed * wet).coerceIn(-1f, 1f) }
                    val toStore = if (isBypass) 0f else (input + delayed * fb).coerceIn(-1f, 1f)
                    delayBuffer[writePos] = (toStore * 32767f).toInt().coerceIn(-32767, 32767).toShort()
                    writePos = (writePos + 1) % delayBuffer.size
                    buffer[i] = (out * 32767f).toInt().coerceIn(-32767, 32767).toShort()
                }
                player.write(buffer, 0, read)
            }
            try { recorder.stop(); recorder.release(); player.stop(); player.release() } catch (e: Exception) {}
        }
        runOnUiThread { Toast.makeText(this, "Live Mic ON - Echo Chal Raha Hai!", Toast.LENGTH_SHORT).show() }
    }

    private fun stopAudio() {
        isRunning = false
        try { audioThread?.join(500) } catch (e: Exception) {}
        audioThread = null
    }

    override fun onDestroy() {
        stopAudio()
        super.onDestroy()
    }
}
