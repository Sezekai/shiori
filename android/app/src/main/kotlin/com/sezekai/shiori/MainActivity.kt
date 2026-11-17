package com.sezekai.shiori

import android.os.Build
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity so the fingerprint / face / PIN app lock works.
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var volumeKeys = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiori/native").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "volumeKeys" -> {
                        volumeKeys = call.arguments as Boolean
                        result.success(null)
                    }
                    "secure" -> {
                        // Hides the app's content in Recents (and blocks screenshots).
                        if (call.arguments as Boolean) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "deviceName" -> {
                        val name = try {
                            Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
                        } catch (e: Exception) {
                            null
                        }
                        result.success(name ?: "${Build.MANUFACTURER} ${Build.MODEL}")
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // Volume keys turn pages while the reader is open.
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeys && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) {
            channel?.invokeMethod("volume", if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) "down" else "up")
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeys && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) return true
        return super.onKeyUp(keyCode, event)
    }
}
