package com.watchparty.watch_party

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "watch_party/pip"
    private var methodChannel: MethodChannel? = null
    private var isAutoEnterPipEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    result.success(supported)
                }
                "enterPip" -> {
                    val numerator = call.argument<Int>("numerator") ?: 16
                    val denominator = call.argument<Int>("denominator") ?: 9
                    val success = enterPipMode(numerator, denominator)
                    result.success(success)
                }
                "setAutoEnterPip" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isAutoEnterPipEnabled = enabled
                    updateAutoPipParams(enabled)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPipMode(numerator: Int, denominator: Int): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            return try {
                val num = numerator.coerceAtLeast(1)
                val den = denominator.coerceAtLeast(1)
                val rational = Rational(num, den)
                val builder = PictureInPictureParams.Builder().setAspectRatio(rational)
                enterPictureInPictureMode(builder.build())
            } catch (e: Exception) {
                e.printStackTrace()
                false
            }
        }
        return false
    }

    private fun updateAutoPipParams(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            try {
                val builder = PictureInPictureParams.Builder()
                    .setAutoEnterEnabled(enabled)
                    .setAspectRatio(Rational(16, 9))
                setPictureInPictureParams(builder.build())
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isAutoEnterPipEnabled) {
            enterPipMode(16, 9)
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }
}
