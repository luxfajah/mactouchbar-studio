package io.github.luxfajah.touchbar

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.github.luxfajah.touchbar.audio.MicStreamer
import io.github.luxfajah.touchbar.network.TouchbarClient
import io.github.luxfajah.touchbar.ui.theme.TouchBarBackground
import io.github.luxfajah.touchbar.ui.theme.TouchBarTheme
import org.json.JSONObject

class MainActivity : ComponentActivity() {

    private lateinit var client: TouchbarClient
    private lateinit var micStreamer: MicStreamer
    private var webView: WebView? = null

    private val requestMicPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted: Boolean ->
        runOnUiThread {
            webView?.evaluateJavascript(
                "if (window.onMicPermissionResult) window.onMicPermissionResult($isGranted);",
                null
            )
            if (isGranted) {
                val macIp = client.state.value.macIp.ifBlank {
                    getSharedPreferences("touchbar_prefs", Context.MODE_PRIVATE)
                        .getString("saved_mac_ip", "192.168.1.6") ?: "192.168.1.6"
                }
                micStreamer.startStreaming(macIp)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Force Landscape Orientation
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        
        // Keep screen awake while using Touch Bar
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        
        // Notch / Display Cutout Fullscreen
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        
        enableEdgeToEdge()
        hideSystemUI()

        client = TouchbarClient(this)
        micStreamer = MicStreamer(this)

        // Wire audio callbacks to WebView
        micStreamer.onAudioLevelChanged = { level, isStreaming ->
            runOnUiThread {
                webView?.evaluateJavascript(
                    "if (window.onMicLevelUpdate) window.onMicLevelUpdate($level, $isStreaming, ${micStreamer.isMuted()});",
                    null
                )
            }
        }

        micStreamer.onStreamStateChanged = { isStreaming ->
            runOnUiThread {
                webView?.evaluateJavascript(
                    "if (window.onMicStateChanged) window.onMicStateChanged($isStreaming);",
                    null
                )
            }
        }
        
        // Wire events from client to WebView
        client.onConnectionChanged = { connected, ip ->
            runOnUiThread {
                if (connected) {
                    webView?.evaluateJavascript(
                        "if (window.onMacConnected) window.onMacConnected('$ip', 'Mac');",
                        null
                    )
                } else {
                    webView?.evaluateJavascript(
                        "if (window.onMacDisconnected) window.onMacDisconnected();",
                        null
                    )
                }
            }
        }

        client.onRawMessage = { rawJson ->
            runOnUiThread {
                webView?.evaluateJavascript(
                    "if (window.onMacStateUpdate) window.onMacStateUpdate(${JSONObject.quote(rawJson)});",
                    null
                )
            }
        }

        // Register Battery Receiver for real-time Phone Battery tracking
        registerReceiver(batteryReceiver, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))

        setContent {
            TouchBarTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = TouchBarBackground
                ) {
                    IPadOSWebViewContainer(
                        activity = this@MainActivity,
                        client = client,
                        micStreamer = micStreamer,
                        onRequestMicPermission = { requestMicPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO) },
                        onWebViewReady = { wv ->
                            webView = wv
                        }
                    )
                }
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            hideSystemUI()
        }
    }

    override fun onResume() {
        super.onResume()
        hideSystemUI()
        webView?.onResume()
    }

    override fun onPause() {
        super.onPause()
        webView?.onPause()
    }

    private val batteryReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: android.content.Intent?) {
            if (intent?.action == android.content.Intent.ACTION_BATTERY_CHANGED) {
                val level = intent.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1)
                val pct = if (level >= 0 && scale > 0) ((level.toFloat() / scale.toFloat()) * 100).toInt() else 100
                val status = intent.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1)
                val isCharging = status == android.os.BatteryManager.BATTERY_STATUS_CHARGING || status == android.os.BatteryManager.BATTERY_STATUS_FULL
                runOnUiThread {
                    webView?.evaluateJavascript(
                        "if (window.onPhoneBatteryUpdate) window.onPhoneBatteryUpdate($pct, $isCharging);",
                        null
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(batteryReceiver)
        } catch (e: Exception) {
            // ignore
        }
        micStreamer.release()
        client.release()
        webView?.destroy()
    }

    private fun hideSystemUI() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun IPadOSWebViewContainer(
    activity: Activity,
    client: TouchbarClient,
    micStreamer: MicStreamer,
    onRequestMicPermission: () -> Unit,
    onWebViewReady: (WebView) -> Unit
) {
    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { context ->
            WebView(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )

                // High-performance hardware acceleration & rendering
                setLayerType(View.LAYER_TYPE_HARDWARE, null)
                setBackgroundColor(0xFF000000.toInt())

                settings.apply {
                    javaScriptEnabled = true
                    domStorageEnabled = true
                    databaseEnabled = true
                    allowFileAccess = true
                    allowContentAccess = true
                    allowFileAccessFromFileURLs = true
                    allowUniversalAccessFromFileURLs = true
                    useWideViewPort = true
                    loadWithOverviewMode = true
                    cacheMode = WebSettings.LOAD_DEFAULT
                    setSupportZoom(false)
                    builtInZoomControls = false
                    displayZoomControls = false
                }

                webChromeClient = WebChromeClient()
                webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        val currentIp = client.state.value.macIp
                        if (currentIp.isNotBlank()) {
                            view?.evaluateJavascript(
                                "if (window.onMacDiscovered) window.onMacDiscovered('$currentIp');",
                                null
                            )
                        }
                    }
                }

                // Add Javascript Bridge
                addJavascriptInterface(
                    AndroidBridge(activity, client, micStreamer, onRequestMicPermission, this),
                    "AndroidBridge"
                )

                loadUrl("file:///android_asset/ipados/index.html")
                onWebViewReady(this)
            }
        }
    )
}

class AndroidBridge(
    private val activity: Activity,
    private val client: TouchbarClient,
    private val micStreamer: MicStreamer,
    private val onRequestMicPermission: () -> Unit,
    private val webView: WebView
) {
    private val prefs = activity.getSharedPreferences("touchbar_prefs", Context.MODE_PRIVATE)

    @JavascriptInterface
    fun performHapticFeedback() {
        activity.runOnUiThread {
            try {
                activity.window.decorView.performHapticFeedback(
                    HapticFeedbackConstants.KEYBOARD_TAP,
                    HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
                )
            } catch (e: Exception) {
                // fallback
            }
        }
    }

    @JavascriptInterface
    fun sendMacAction(jsonStr: String) {
        try {
            client.sendRawJson(jsonStr)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    @JavascriptInterface
    fun getSavedIp(): String {
        return prefs.getString("saved_mac_ip", "192.168.1.6") ?: "192.168.1.6"
    }

    @JavascriptInterface
    fun getMacIp(): String {
        return client.state.value.macIp.ifBlank {
            prefs.getString("saved_mac_ip", "192.168.1.6") ?: "192.168.1.6"
        }
    }

    @JavascriptInterface
    fun saveIp(ip: String) {
        prefs.edit().putString("saved_mac_ip", ip).apply()
        client.connect(ip, 9876)
    }

    @JavascriptInterface
    fun connectToMac(ip: String) {
        client.connect(ip, 9876)
    }

    @JavascriptInterface
    fun getDeviceBattery(): String {
        try {
            val bm = activity.getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
            val level = bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
            val isCharging = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                bm?.isCharging ?: false
            } else {
                val intent = activity.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
                val status = intent?.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1) ?: -1
                status == android.os.BatteryManager.BATTERY_STATUS_CHARGING || status == android.os.BatteryManager.BATTERY_STATUS_FULL
            }
            val json = JSONObject()
            json.put("level", level)
            json.put("charging", isCharging)
            return json.toString()
        } catch (e: Exception) {
            return "{\"level\": 100, \"charging\": false}"
        }
    }

    // MARK: - Wireless Microphone Bridge Methods
    @JavascriptInterface
    fun hasMicPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    @JavascriptInterface
    fun requestMicPermission() {
        activity.runOnUiThread {
            onRequestMicPermission()
        }
    }

    @JavascriptInterface
    fun startMic(): Boolean {
        if (!hasMicPermission()) {
            requestMicPermission()
            return false
        }
        val macIp = getMacIp()
        return micStreamer.startStreaming(macIp)
    }

    @JavascriptInterface
    fun stopMic() {
        micStreamer.stopStreaming()
    }

    @JavascriptInterface
    fun toggleMic(): Boolean {
        if (micStreamer.isStreaming()) {
            micStreamer.stopStreaming()
            return false
        } else {
            return startMic()
        }
    }

    @JavascriptInterface
    fun isMicActive(): Boolean {
        return micStreamer.isStreaming()
    }

    @JavascriptInterface
    fun isMicMuted(): Boolean {
        return micStreamer.isMuted()
    }

    @JavascriptInterface
    fun setMicMute(muted: Boolean) {
        micStreamer.setMute(muted)
    }

    @JavascriptInterface
    fun toggleMicMute(): Boolean {
        return micStreamer.toggleMute()
    }

    @JavascriptInterface
    fun setMicGain(gain: Float) {
        micStreamer.setGain(gain)
    }

    @JavascriptInterface
    fun getMicGain(): Float {
        return micStreamer.getGain()
    }

    @JavascriptInterface
    fun setNoiseReduction(enabled: Boolean) {
        micStreamer.setNoiseSuppression(enabled)
    }
}
