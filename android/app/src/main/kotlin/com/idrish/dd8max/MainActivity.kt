package com.idrish.dd8max

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall

class MainActivity : FlutterActivity() {
    private val liveAudioEngine = LiveAudioEngine()

    private fun applyAudioSettings(call: MethodCall) {
        liveAudioEngine.update(
            call.argument<Int>("delayMs") ?: 320,
            call.argument<Double>("feedback") ?: 0.38,
            call.argument<Double>("mix") ?: 0.45,
            call.argument<Double>("level") ?: 0.8,
            call.argument<Boolean>("noiseReduction") ?: true,
            call.argument<Boolean>("noiseGate") ?: true,
            call.argument<Double>("ancLevel") ?: 0.65,
            call.argument<Boolean>("dual") ?: false,
            call.argument<Boolean>("pingPong") ?: false,
            call.argument<Boolean>("bypass") ?: false,
            call.argument<List<Double>>("eq") ?: listOf(0.0, 0.0, 0.0, 0.0, 0.0)
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ddm.max/live_audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> try {
                        liveAudioEngine.start(
                            call.argument<Int>("delayMs") ?: 320,
                            call.argument<Double>("feedback") ?: 0.38,
                            call.argument<Double>("mix") ?: 0.45,
                            call.argument<Double>("level") ?: 0.8,
                            call.argument<Boolean>("noiseReduction") ?: true,
                            call.argument<Boolean>("noiseGate") ?: true,
                            call.argument<Double>("ancLevel") ?: 0.65,
                            call.argument<Boolean>("dual") ?: false,
                            call.argument<Boolean>("pingPong") ?: false,
                            call.argument<Boolean>("bypass") ?: false,
                            call.argument<List<Double>>("eq") ?: listOf(0.0, 0.0, 0.0, 0.0, 0.0)
                        )
                        result.success(mapOf(
                            "noiseSuppressor" to liveAudioEngine.noiseSuppressorActive,
                            "echoCanceler" to liveAudioEngine.echoCancelerActive
                        ))
                    } catch (e: Exception) {
                        result.error("LIVE_AUDIO_START", e.message, null)
                    }
                    "update" -> try {
                        applyAudioSettings(call)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LIVE_AUDIO_UPDATE", e.message, null)
                    }
                    "decodeToWav" -> {
                        val inputPath = call.argument<String>("inputPath")
                        val outputPath = call.argument<String>("outputPath")
                        if (inputPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                            result.error("AUDIO_DECODE_ARGS", "Input/output path missing", null)
                        } else {
                            Thread {
                                try {
                                    AudioTranscoder.decodeToWav(inputPath, outputPath)
                                    runOnUiThread { result.success(outputPath) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("AUDIO_DECODE_FAILED", e.message, null) }
                                }
                            }.apply { name = "DDM-Audio-Decoder"; start() }
                        }
                    }
                    "stop" -> {
                        liveAudioEngine.stop()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        liveAudioEngine.stop()
        super.onDestroy()
    }
}
