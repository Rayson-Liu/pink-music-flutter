package com.pinkmusic.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var equalizerPlugin: EqualizerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = EqualizerPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        plugin.onAttachedToEngine()
        equalizerPlugin = plugin
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        equalizerPlugin?.onDetachedFromEngine()
        equalizerPlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}