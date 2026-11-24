package com.idrish.dd8max

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val liveAudioEngine = LiveAudioEngine()
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
                            call.argument<Double>("ancLevel") ?: 0.65
                        )
                        result.success(true)
                    } catch (e: Exception) { result.error("LIVE_AUDIO_START", e.message, null) }
                    "stop" -> { liveAudioEngine.stop(); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }
    override fun onDestroy() { liveAudioEngine.stop(); super.onDestroy() }
}