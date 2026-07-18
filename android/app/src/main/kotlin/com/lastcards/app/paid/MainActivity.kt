package com.lastcards.app.paid

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Backward-compatible edge-to-edge for pre-Android 15 (SDK 35 enforces it).
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // androidx.activity's enableEdgeToEdge() still sets SHORT_EDGES on API 28–29.
        // Play flags that deprecated constant — prefer ALWAYS (API 30+) everywhere
        // the platform supports it.
        applyAlwaysDisplayCutoutMode()
    }

    private fun applyAlwaysDisplayCutoutMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val attrs = window.attributes
        attrs.layoutInDisplayCutoutMode =
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        window.attributes = attrs
    }
}
