package com.nodeman24.nowave

import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var speech: TextToSpeech? = null
    private var channel: MethodChannel? = null
    private var initializing = false
    private var ready = false
    private var destroyed = false
    private val initializationResults = mutableListOf<MethodChannel.Result>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "belog/read_aloud")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> initializeSpeech(result)
                "stop" -> {
                    speech?.stop()
                    result.success(null)
                }
                "speak" -> {
                    val id = call.argument<String>("id")
                    val text = call.argument<String>("text")
                    val language = call.argument<String>("language")
                    val voiceName = call.argument<String>("voice")
                    val rate = call.argument<Double>("rate")
                    val engine = speech
                    if (!ready || engine == null || id == null || text.isNullOrEmpty() ||
                        language == null || rate == null
                    ) {
                        result.success(false)
                    } else {
                        val selected = engine.voices?.firstOrNull { it.name == voiceName }
                        if (selected != null) {
                            engine.voice = selected
                        } else {
                            engine.language = Locale.forLanguageTag(language)
                        }
                        engine.setSpeechRate(rate.toFloat().coerceIn(0.5f, 2.0f))
                        val status = engine.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), id)
                        result.success(status == TextToSpeech.SUCCESS)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initializeSpeech(result: MethodChannel.Result) {
        if (ready) {
            result.success(capabilities())
            return
        }
        initializationResults.add(result)
        if (initializing) return
        initializing = true
        speech = TextToSpeech(applicationContext) { status ->
            runOnUiThread {
                if (destroyed) return@runOnUiThread
                initializing = false
                ready = status == TextToSpeech.SUCCESS
                if (ready) {
                    speech?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String) = emit(utteranceId, "started")
                        override fun onDone(utteranceId: String) = emit(utteranceId, "completed")
                        @Deprecated("Android's legacy error callback")
                        override fun onError(utteranceId: String) = emit(utteranceId, "error")
                        override fun onError(utteranceId: String, errorCode: Int) = emit(utteranceId, "error")
                        override fun onStop(utteranceId: String, interrupted: Boolean) = emit(utteranceId, "cancelled")
                        override fun onRangeStart(utteranceId: String, start: Int, end: Int, frame: Int) {
                            // Engines on Android 8+ can report UTF-16 word ranges;
                            // engines without range support use passage highlighting.
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                emit(utteranceId, "range", start, end)
                            }
                        }
                    })
                } else {
                    speech?.shutdown()
                    speech = null
                }
                val response = capabilities()
                initializationResults.forEach { it.success(response) }
                initializationResults.clear()
            }
        }
    }

    private fun capabilities(): Map<String, Any> {
        val voices = if (ready) {
            speech?.voices.orEmpty()
                .sortedWith(compareBy({ it.isNetworkConnectionRequired }, { it.name }))
                .map { mapOf("id" to it.name, "language" to it.locale.toLanguageTag()) }
        } else {
            emptyList()
        }
        return mapOf("available" to ready, "voices" to voices)
    }

    private fun emit(id: String?, type: String, start: Int = 0, end: Int = 0) {
        if (id == null) return
        runOnUiThread {
            if (!destroyed) channel?.invokeMethod(
                "event", mapOf("id" to id, "type" to type, "start" to start, "end" to end)
            )
        }
    }

    override fun onDestroy() {
        destroyed = true
        initializationResults.forEach { it.success(mapOf("available" to false)) }
        initializationResults.clear()
        channel?.setMethodCallHandler(null)
        speech?.stop()
        speech?.shutdown()
        speech = null
        super.onDestroy()
    }
}
