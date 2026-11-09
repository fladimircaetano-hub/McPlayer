package com.mcplayer.app.mcplayer

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mcplayer/device"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "soc" -> result.success(
                    listOf(Build.HARDWARE, Build.BOARD, Build.MODEL).joinToString("|")
                )
                else -> result.notImplemented()
            }
        }
    }
}
