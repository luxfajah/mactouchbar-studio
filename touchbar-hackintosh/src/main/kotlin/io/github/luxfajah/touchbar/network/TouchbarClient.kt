package io.github.luxfajah.touchbar.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.*
import org.json.JSONObject
import java.util.concurrent.TimeUnit

data class DeckButtonItem(
    val id: String = "",
    val label: String = "App",
    val icon: String = "💻",
    val iconUrl: String = "",
    val iconBase64: String = "",
    val actionType: String = "launch_app",
    val payload: String = "",
    val colorHex: String = "#1F1F24"
)

data class TouchbarMediaInfo(
    val player: String = "None",
    val state: String = "stopped",
    val title: String = "Nenhuma reprodução",
    val artist: String = "Mac Pronto",
    val artworkUrl: String = ""
)

data class TouchbarState(
    val isConnected: Boolean = false,
    val macName: String = "Buscando Mac...",
    val macIp: String = "192.168.1.6",
    val volume: Int = 50,
    val isMuted: Boolean = false,
    val brightness: Int = 75,
    val battery: Int = 100,
    val isWifiEnabled: Boolean = true,
    val isBluetoothEnabled: Boolean = true,
    val isAirDropEnabled: Boolean = false,
    val isFocusSleepEnabled: Boolean = false,
    val isStageManagerEnabled: Boolean = false,
    val frontmostApp: String = "Finder",
    val media: TouchbarMediaInfo = TouchbarMediaInfo(),
    val deckButtons: List<DeckButtonItem> = defaultDeckButtons()
)

fun defaultDeckButtons(): List<DeckButtonItem> = listOf(
    // Row 1: Chrome, Música, Discord, Photoshop, Illustrator, InDesign
    DeckButtonItem("chrome", "Chrome", "🌐", "icons/chrome.png", "", "launch_app", "/Applications/Google Chrome.app", "#1F1F24"),
    DeckButtonItem("music", "Música", "🎵", "icons/music.png", "", "launch_app", "/System/Applications/Music.app", "#1F1F24"),
    DeckButtonItem("discord", "Discord", "🎮", "icons/discord.png", "", "launch_app", "/Applications/Discord.app", "#1F1F24"),
    DeckButtonItem("photoshop", "Photoshop", "🖼️", "icons/photoshop.png", "", "launch_app", "/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app", "#1F1F24"),
    DeckButtonItem("illustrator", "Illustrator", "✒️", "icons/illustrator.png", "", "launch_app", "/Applications/Adobe Illustrator 2026/Adobe Illustrator.app", "#1F1F24"),
    DeckButtonItem("indesign", "InDesign", "📑", "icons/indesign.png", "", "launch_app", "/Applications/Adobe InDesign 2026/Adobe InDesign 2026.app", "#1F1F24"),
    
    // Row 2: Figma, Affinity, Antigravity, WhatsApp, Finder, Ajustes
    DeckButtonItem("figma", "Figma", "🎨", "icons/figma.png", "", "launch_app", "/Applications/Figma.app", "#1F1F24"),
    DeckButtonItem("affinity", "Affinity", "💎", "icons/affinity.png", "", "launch_app", "/Applications/Affinity.app", "#1F1F24"),
    DeckButtonItem("antigravity", "Antigravity", "🚀", "icons/antigravity.png", "", "launch_app", "/Applications/Antigravity.app", "#1F1F24"),
    DeckButtonItem("whatsapp", "WhatsApp", "💬", "icons/whatsapp.png", "", "launch_app", "/Applications/WhatsApp.app", "#1F1F24"),
    DeckButtonItem("finder", "Finder", "📁", "icons/finder.png", "", "launch_app", "/System/Library/CoreServices/Finder.app", "#1F1F24"),
    DeckButtonItem("settings", "Ajustes", "⚙️", "icons/settings.png", "", "launch_app", "/System/Applications/System Settings.app", "#1F1F24")
)

class TouchbarClient(private val context: Context) {

    private val tag = "TouchbarClient"
    private val scope = CoroutineScope(Dispatchers.IO)

    private val prefs = context.getSharedPreferences("touchbar_prefs", Context.MODE_PRIVATE)

    private val _state = MutableStateFlow(TouchbarState(macIp = prefs.getString("saved_mac_ip", "192.168.1.6") ?: "192.168.1.6"))
    val state = _state.asStateFlow()

    var onRawMessage: ((String) -> Unit)? = null
    var onConnectionChanged: ((Boolean, String) -> Unit)? = null

    private var okHttpClient = OkHttpClient.Builder()
        .pingInterval(4, TimeUnit.SECONDS)
        .connectTimeout(3, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    private var webSocket: WebSocket? = null
    private var nsdManager: NsdManager? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    init {
        val initialIp = prefs.getString("saved_mac_ip", "192.168.1.6") ?: "192.168.1.6"
        connect(initialIp, 9876)
        startDiscovery()
    }

    fun startDiscovery() {
        if (nsdManager != null) return
        try {
            nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
            discoveryListener = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(regType: String) {
                    Log.d(tag, "Bonjour discovery started for $regType")
                }

                override fun onServiceFound(service: NsdServiceInfo) {
                    if (service.serviceType.contains("_macdeck._tcp")) {
                        try {
                            nsdManager?.resolveService(service, object : NsdManager.ResolveListener {
                                override fun onResolveFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) {}
                                override fun onServiceResolved(serviceInfo: NsdServiceInfo?) {
                                    val host = serviceInfo?.host?.hostAddress ?: return
                                    val port = serviceInfo.port
                                    Log.i(tag, "NSD Discovered Mac at $host:$port")
                                    connect(host, port)
                                }
                            })
                        } catch (e: Exception) {
                            Log.w(tag, "Resolve error: ${e.message}")
                        }
                    }
                }

                override fun onServiceLost(service: NsdServiceInfo) {}
                override fun onDiscoveryStopped(serviceType: String) {}
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                    nsdManager?.stopServiceDiscovery(this)
                }
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                    nsdManager?.stopServiceDiscovery(this)
                }
            }
            nsdManager?.discoverServices("_macdeck._tcp.", NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        } catch (e: Exception) {
            Log.e(tag, "Discovery error: ${e.message}")
        }
    }

    fun connect(host: String, port: Int = 9876) {
        if (host.isBlank() || host == "127.0.0.1" || host == "localhost") {
            val targetIp = "192.168.1.6"
            connect(targetIp, port)
            return
        }

        prefs.edit().putString("saved_mac_ip", host).apply()

        webSocket?.close(1000, "Reconnecting")
        val url = "ws://$host:$port"
        Log.i(tag, "Connecting to Mac TouchBar at $url")

        val request = Request.Builder().url(url).build()
        webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.i(tag, "✅ Connected to Mac at $host")
                _state.value = _state.value.copy(
                    isConnected = true,
                    macIp = host
                )
                onConnectionChanged?.invoke(true, host)
                sendAction("get_status")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                onRawMessage?.invoke(text)
                handleServerMessage(text)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                _state.value = _state.value.copy(isConnected = false)
                onConnectionChanged?.invoke(false, host)
                scheduleReconnect(host, port)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                _state.value = _state.value.copy(isConnected = false)
                onConnectionChanged?.invoke(false, host)
                scheduleReconnect(host, port)
            }
        })
    }

    private fun scheduleReconnect(host: String, port: Int) {
        scope.launch {
            kotlinx.coroutines.delay(2500)
            if (!_state.value.isConnected) {
                connect(host, port)
            }
        }
    }

    private fun handleServerMessage(jsonText: String) {
        try {
            val json = JSONObject(jsonText)
            val type = json.optString("type")

            if (type == "deck_config_update") {
                val btnsArray = json.optJSONArray("buttons")
                if (btnsArray != null) {
                    val list = mutableListOf<DeckButtonItem>()
                    for (i in 0 until btnsArray.length()) {
                        val obj = btnsArray.getJSONObject(i)
                        list.add(
                            DeckButtonItem(
                                id = obj.optString("id", "$i"),
                                label = obj.optString("label", "App"),
                                icon = obj.optString("icon", "💻"),
                                iconUrl = obj.optString("iconUrl", "icons/${obj.optString("id")}.png"),
                                iconBase64 = obj.optString("iconBase64", ""),
                                actionType = obj.optString("actionType", "launch_app"),
                                payload = obj.optString("payload", ""),
                                colorHex = obj.optString("colorHex", "#1F1F24")
                            )
                        )
                    }
                    _state.value = _state.value.copy(deckButtons = list)
                }
            } else if (type == "status_update" || json.has("volume")) {
                val macName = json.optString("mac_name", _state.value.macName)
                val volume = json.optInt("volume", _state.value.volume)
                val isMuted = json.optBoolean("is_muted", _state.value.isMuted)
                val brightness = json.optInt("brightness", _state.value.brightness)
                val battery = json.optInt("battery", _state.value.battery)
                val wifi = json.optBoolean("wifi_connected", _state.value.isWifiEnabled)
                val bt = json.optBoolean("bluetooth_connected", _state.value.isBluetoothEnabled)
                val frontApp = json.optString("frontmost_app", _state.value.frontmostApp)

                val mediaObj = json.optJSONObject("media")
                val mediaInfo = if (mediaObj != null) {
                    TouchbarMediaInfo(
                        player = mediaObj.optString("player", "None"),
                        state = mediaObj.optString("state", "stopped"),
                        title = mediaObj.optString("title", "Nenhuma reprodução"),
                        artist = mediaObj.optString("artist", "Mac Pronto")
                    )
                } else _state.value.media

                _state.value = _state.value.copy(
                    isConnected = true,
                    macName = macName,
                    volume = volume,
                    isMuted = isMuted,
                    brightness = brightness,
                    battery = battery,
                    isWifiEnabled = wifi,
                    isBluetoothEnabled = bt,
                    frontmostApp = frontApp,
                    media = mediaInfo
                )
            }
        } catch (e: Exception) {
            Log.e(tag, "Error parsing server message: ${e.message}")
        }
    }

    fun sendRawJson(rawJson: String) {
        scope.launch {
            try {
                webSocket?.send(rawJson)
            } catch (e: Exception) {
                Log.e(tag, "Error sending raw json: ${e.message}")
            }
        }
    }

    fun sendAction(action: String, params: Map<String, Any> = emptyMap()) {
        scope.launch {
            try {
                val json = JSONObject()
                json.put("action", action)
                val paramObj = JSONObject()
                params.forEach { (k, v) -> paramObj.put(k, v) }
                json.put("params", paramObj)
                webSocket?.send(json.toString())
            } catch (e: Exception) {
                Log.e(tag, "Error sending action: ${e.message}")
            }
        }
    }

    // High-Level Actions
    fun pressEsc() = sendAction("press_esc")
    fun setVolume(volume: Int) {
        _state.value = _state.value.copy(volume = volume)
        sendAction("set_volume", mapOf("volume" to volume))
    }
    fun setBrightness(brightness: Int) {
        _state.value = _state.value.copy(brightness = brightness)
        sendAction("set_brightness", mapOf("brightness" to brightness))
    }
    fun toggleMute() {
        _state.value = _state.value.copy(isMuted = !_state.value.isMuted)
        sendAction("toggle_mute")
    }
    fun toggleWifi() = sendAction("system_action", mapOf("command" to "toggle_wifi"))
    fun toggleBluetooth() = sendAction("system_action", mapOf("command" to "toggle_bluetooth"))
    fun toggleAirDrop() = sendAction("system_action", mapOf("command" to "toggle_airdrop"))
    fun toggleFocusSleep() = sendAction("system_action", mapOf("command" to "toggle_sleep_focus"))
    fun toggleStageManager() = sendAction("system_action", mapOf("command" to "stage_manager"))
    fun toggleScreenMirror() = sendAction("system_action", mapOf("command" to "screen_mirror"))
    fun mediaPlayPause() = sendAction("media_play_pause")
    fun mediaNext() = sendAction("media_next")
    fun mediaPrev() = sendAction("media_prev")
    fun typeEmoji(emoji: String) = sendAction("type_emoji", mapOf("text" to emoji))
    fun sendParsedHotkey(hotkey: String) = sendAction("parse_hotkey_string", mapOf("hotkey" to hotkey))
    fun sendTerminalCommand(cmd: String) = sendAction("terminal_cmd", mapOf("cmd" to cmd))
    fun sendSystemCommand(command: String) = sendAction("system_action", mapOf("command" to command))
    fun systemAction(command: String) = sendAction("system_action", mapOf("command" to command))
    fun sendHotkey(key: String, modifiers: List<String> = emptyList()) = sendAction("send_hotkey", mapOf("key" to key, "modifiers" to modifiers))
    fun playSound(soundName: String) = sendAction("play_sound", mapOf("sound" to soundName))
    fun launchApp(app: String) = sendAction("launch_app", mapOf("app" to app))
    fun executeDeckButton(item: DeckButtonItem) {
        when (item.actionType) {
            "launch_app" -> launchApp(item.payload)
            "hotkey" -> sendParsedHotkey(item.payload)
            "terminal_cmd" -> sendTerminalCommand(item.payload)
            "system" -> sendSystemCommand(item.payload)
            "sound" -> playSound(item.payload)
            else -> launchApp(item.payload)
        }
    }

    fun release() {
        try {
            discoveryListener?.let { nsdManager?.stopServiceDiscovery(it) }
        } catch (_: Exception) {}
        webSocket?.close(1000, "App closed")
        webSocket = null
        nsdManager = null
    }
}
