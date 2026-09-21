package com.example.oregonetservice

import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.oregonetservice/fileprovider"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getUriForFile") {
                    try {
                        val path = call.argument<String>("path")!!
                        val uri = FileProvider.getUriForFile(
                            applicationContext,
                            "$packageName.fileprovider",
                            File(path)
                        )
                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}