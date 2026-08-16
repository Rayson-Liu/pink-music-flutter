package com.pinkmusic.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var equalizerPlugin: EqualizerPlugin? = null
    private var permissionChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = EqualizerPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        plugin.onAttachedToEngine()
        equalizerPlugin = plugin

        permissionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pinkmusic.app/permissions",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < 33) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        permissionChannel?.setMethodCallHandler(null)
        permissionChannel = null
        equalizerPlugin?.onDetachedFromEngine()
        equalizerPlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
