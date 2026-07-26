package com.gcctbc.attendanceapp

import android.app.ActivityManager
import android.content.Context
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL = "msce/device_performance"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceProfile" -> result.success(deviceProfile())
                    "getSecurityFlags" -> result.success(securityFlags())
                    else -> result.notImplemented()
                }
            }
    }

    private fun deviceProfile(): Map<String, Any> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        return mapOf(
            "isLowRamDevice" to activityManager.isLowRamDevice,
            "memoryClassMb" to activityManager.memoryClass,
            "largeMemoryClassMb" to activityManager.largeMemoryClass,
            "totalRamMb" to (memoryInfo.totalMem / (1024 * 1024)).toInt(),
        )
    }

    private fun securityFlags(): Map<String, Any> {
        val developerOptionsEnabled = try {
            Settings.Global.getInt(
                contentResolver,
                Settings.Global.DEVELOPMENT_SETTINGS_ENABLED,
                0
            ) == 1
        } catch (_: Exception) {
            false
        }

        val adbEnabled = try {
            Settings.Global.getInt(
                contentResolver,
                Settings.Global.ADB_ENABLED,
                0
            ) == 1
        } catch (_: Exception) {
            false
        }

        return mapOf(
            "developerOptionsEnabled" to developerOptionsEnabled,
            "adbEnabled" to adbEnabled,
        )
    }
}
