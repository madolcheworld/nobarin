package com.nobarin.app

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "watch_party/pip"
    private val ACTION_MEDIA_CONTROL = "com.nobarin.app.MEDIA_CONTROL"
    private val EXTRA_CONTROL_TYPE = "control_type"
    private val CONTROL_TYPE_PLAY = 1
    private val CONTROL_TYPE_PAUSE = 2
    private val CONTROL_TYPE_STOP_SCREENSHARE = 3

    private var methodChannel: MethodChannel? = null
    private var isAutoEnterPipEnabled = false
    private var isPlayingState = false
    private var isSharingLocallyState = false
    private var currentNumerator = 16
    private var currentDenominator = 9
    private var mediaReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerMediaReceiver()
    }

    private fun registerMediaReceiver() {
        if (mediaReceiver == null) {
            mediaReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent == null || intent.action != ACTION_MEDIA_CONTROL) return
                    val controlType = intent.getIntExtra(EXTRA_CONTROL_TYPE, 0)
                    if (controlType == CONTROL_TYPE_PLAY) {
                        methodChannel?.invokeMethod("onPipAction", "play")
                        updatePipParams(true)
                    } else if (controlType == CONTROL_TYPE_PAUSE) {
                        methodChannel?.invokeMethod("onPipAction", "pause")
                        updatePipParams(false)
                    } else if (controlType == CONTROL_TYPE_STOP_SCREENSHARE) {
                        methodChannel?.invokeMethod("onPipAction", "stop_screenshare")
                    }
                }
            }
            val filter = IntentFilter(ACTION_MEDIA_CONTROL)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(mediaReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(mediaReceiver, filter)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        mediaReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // Ignore
            }
            mediaReceiver = null
        }
    }

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
                    val numerator = call.argument<Int>("numerator") ?: currentNumerator
                    val denominator = call.argument<Int>("denominator") ?: currentDenominator
                    currentNumerator = numerator
                    currentDenominator = denominator
                    val success = enterPipMode(numerator, denominator)
                    result.success(success)
                }
                "setPipAspectRatio" -> {
                    val numerator = call.argument<Int>("numerator") ?: currentNumerator
                    val denominator = call.argument<Int>("denominator") ?: currentDenominator
                    currentNumerator = numerator
                    currentDenominator = denominator
                    updatePipParams(isPlayingState)
                    result.success(true)
                }
                "setAutoEnterPip" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isAutoEnterPipEnabled = enabled
                    updateAutoPipParams(enabled)
                    result.success(true)
                }
                "updatePlaybackState" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    isPlayingState = isPlaying
                    updatePipParams(isPlaying)
                    result.success(true)
                }
                "updateScreenShareState" -> {
                    val isSharing = call.argument<Boolean>("isSharingLocally") ?: false
                    isSharingLocallyState = isSharing
                    updatePipParams(isPlayingState)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun buildPipParams(numerator: Int = currentNumerator, denominator: Int = currentDenominator): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            currentNumerator = numerator
            currentDenominator = denominator
            val num = numerator.coerceAtLeast(1)
            val den = denominator.coerceAtLeast(1)
            val rawRatio = num.toFloat() / den.toFloat()
            // Android limits aspect ratio between 1/2.39 (~0.41841) and 2.39 inclusive
            val minRatio = 1f / 2.39f
            val maxRatio = 2.39f
            val rational = if (rawRatio < minRatio) {
                Rational(100, 239)
            } else if (rawRatio > maxRatio) {
                Rational(239, 100)
            } else {
                Rational(num, den)
            }
            val builder = PictureInPictureParams.Builder().setAspectRatio(rational)

            val actions = ArrayList<RemoteAction>()
            if (isSharingLocallyState) {
                val iconResId = android.R.drawable.ic_menu_close_clear_cancel
                val title = "Hentikan"
                val controlType = CONTROL_TYPE_STOP_SCREENSHARE

                val intent = Intent(ACTION_MEDIA_CONTROL).apply {
                    putExtra(EXTRA_CONTROL_TYPE, controlType)
                    setPackage(packageName)
                }
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val pendingIntent = PendingIntent.getBroadcast(this, controlType, intent, flags)
                val icon = Icon.createWithResource(this, iconResId)
                val action = RemoteAction(icon, title, title, pendingIntent)
                actions.add(action)
            } else {
                val iconResId = if (isPlayingState) {
                    android.R.drawable.ic_media_pause
                } else {
                    android.R.drawable.ic_media_play
                }
                val title = if (isPlayingState) "Pause" else "Play"
                val controlType = if (isPlayingState) CONTROL_TYPE_PAUSE else CONTROL_TYPE_PLAY

                val intent = Intent(ACTION_MEDIA_CONTROL).apply {
                    putExtra(EXTRA_CONTROL_TYPE, controlType)
                    setPackage(packageName)
                }
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val pendingIntent = PendingIntent.getBroadcast(this, controlType, intent, flags)
                val icon = Icon.createWithResource(this, iconResId)
                val action = RemoteAction(icon, title, title, pendingIntent)
                actions.add(action)
            }
            builder.setActions(actions)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(isAutoEnterPipEnabled)
            }
            return builder.build()
        }
        return null
    }

    private fun enterPipMode(numerator: Int = currentNumerator, denominator: Int = currentDenominator): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            // Guard: don't re-enter if already in PiP
            if (isInPictureInPictureMode) {
                return true
            }
            return try {
                val params = buildPipParams(numerator, denominator)
                if (params != null) {
                    enterPictureInPictureMode(params)
                } else {
                    enterPictureInPictureMode()
                    true
                }
            } catch (e: Exception) {
                e.printStackTrace()
                false
            }
        }
        return false
    }

    private fun updatePipParams(isPlaying: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            isPlayingState = isPlaying
            try {
                val params = buildPipParams(currentNumerator, currentDenominator)
                if (params != null) {
                    setPictureInPictureParams(params)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun updateAutoPipParams(enabled: Boolean) {
        updatePipParams(isPlayingState)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isAutoEnterPipEnabled) {
            // Android 12+ (API 31+) handles auto-enter natively via setAutoEnterEnabled(true).
            // Calling enterPipMode() here on Android 12+ causes duplicate transition / conflict.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                enterPipMode(currentNumerator, currentDenominator)
            }
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
