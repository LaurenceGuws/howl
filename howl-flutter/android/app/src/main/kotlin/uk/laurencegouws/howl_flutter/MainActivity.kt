package uk.laurencegouws.howl_flutter

import android.content.Context
import android.util.Log
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "HowlIme"
        private const val CHANNEL = "howl.flutter/android_ime"
        private const val SHOW_DELAY_MS = 300L
    }

    private var imeChannel: MethodChannel? = null
    private var pendingShowView: FlutterView? = null
    private val showImeRunnable = Runnable {
        val flutterView = pendingShowView ?: return@Runnable
        pendingShowView = null
        if (!flutterView.isAttachedToWindow || flutterView.windowToken == null) return@Runnable

        val inputMethodManager =
            getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        val focusAcquired = flutterView.requestFocus()
        inputMethodManager.restartInput(flutterView)
        if (!inputMethodManager.showSoftInput(flutterView, 0)) {
            Log.w(
                TAG,
                "show rejected: focusAcquired=$focusAcquired active=${inputMethodManager.isActive(flutterView)}",
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        imeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        scheduleTerminalIme()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        cancelPendingImeShow()
        imeChannel?.setMethodCallHandler(null)
        imeChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun scheduleTerminalIme() {
        val flutterView = findViewById<FlutterView>(FLUTTER_VIEW_ID)
        if (flutterView == null) {
            Log.w(TAG, "show skipped: FlutterView unavailable")
            return
        }

        cancelPendingImeShow()
        pendingShowView = flutterView
        flutterView.postDelayed(showImeRunnable, SHOW_DELAY_MS)
    }

    private fun cancelPendingImeShow() {
        pendingShowView?.removeCallbacks(showImeRunnable)
        pendingShowView = null
    }
}
