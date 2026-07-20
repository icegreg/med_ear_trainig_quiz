package com.tnoise.patient

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val configChannel = "com.tnoise.patient/config"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, configChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // API-хост зашит в текущий product flavor (см. build.gradle).
                    "getApiBaseUrl" -> result.success(BuildConfig.API_BASE_URL)
                    else -> result.notImplemented()
                }
            }
    }
}
