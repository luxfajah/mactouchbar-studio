import Cocoa
import Foundation
import Network
import CoreAudio
import Carbon.HIToolbox

// MARK: - App Delegate & Menu Bar Manager
@main
class AppDelegate: NSObject, NSApplicationDelegate, NetServiceDelegate {
    
    var statusItem: NSStatusItem!
    var server: TouchBarServer?
    var netService: NetService?
    var statusMenuItem: NSMenuItem!
    var ipMenuItem: NSMenuItem!
    var clientMenuItem: NSMenuItem!
    var appMenuItem: NSMenuItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupBonjour()
        startServer()
        observeActiveApps()
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = " 💻 TouchBar"
            button.toolTip = "Mac Touch Bar Server"
        }
        
        let menu = NSMenu(title: "Mac Touch Bar")
        
        statusMenuItem = NSMenuItem(title: "🟢 Servidor: Ativo", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        ipMenuItem = NSMenuItem(title: "🌐 IP: Obtendo...", action: nil, keyEquivalent: "")
        ipMenuItem.isEnabled = false
        menu.addItem(ipMenuItem)
        
        clientMenuItem = NSMenuItem(title: "📱 Dispositivos: Nenhum conectado", action: nil, keyEquivalent: "")
        clientMenuItem.isEnabled = false
        menu.addItem(clientMenuItem)
        
        appMenuItem = NSMenuItem(title: "🖥️ App Ativo: Finder", action: nil, keyEquivalent: "")
        appMenuItem.isEnabled = false
        menu.addItem(appMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let restartItem = NSMenuItem(title: "🔄 Reiniciar Servidor", action: #selector(restartServer), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)
        
        let accessibilityItem = NSMenuItem(title: "⚙️ Permissões de Acessibilidade...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Encerrar Mac Touch Bar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    func setupBonjour() {
        netService = NetService(domain: "local.", type: "_macdeck._tcp.", name: "Mac TouchBar (\(Host.current().localizedName ?? "Mac"))", port: 9876)
        netService?.delegate = self
        netService?.publish()
    }
    
    func startServer() {
        server = TouchBarServer(port: 9876)
        server?.onClientConnected = { [weak self] count, clientIp in
            DispatchQueue.main.async {
                self?.clientMenuItem.title = count > 0 ? "📱 Dispositivo Conectado (\(clientIp))" : "📱 Dispositivos: Nenhum conectado"
            }
        }
        server?.start()
        
        // Update local IP in menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let ip = self?.getLocalIPAddress() ?? "127.0.0.1"
            self?.ipMenuItem.title = "🌐 IP: \(ip):9876"
        }
    }
    
    @objc func restartServer() {
        server?.stop()
        startServer()
    }
    
    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func quitApp() {
        netService?.stop()
        server?.stop()
        NSApplication.shared.terminate(nil)
    }
    
    func observeActiveApps() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let appName = app.localizedName else { return }
            self?.appMenuItem.title = "🖥️ App Ativo: \(appName)"
            self?.server?.broadcastStatus(frontmostApp: appName)
        }
    }
    
    func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" || name == "bridge0" || name == "wlan0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    if !address!.starts(with: "127.") { break }
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}

// MARK: - Native WebSocket Server using Network.framework
class TouchBarServer {
    let port: UInt16
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "TouchBarServerQueue", attributes: .concurrent)
    var onClientConnected: ((Int, String) -> Void)?
    
    init(port: UInt16) {
        self.port = port
    }
    
    func start() {
        do {
            let parameters = NWParameters(tls: nil)
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("✅ Native Mac TouchBar Server listening on port \(self.port)")
                case .failed(let error):
                    print("❌ Server failed: \(error)")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] newConnection in
                self?.handleNewConnection(newConnection)
            }
            
            listener?.start(queue: queue)
        } catch {
            print("❌ Failed to start listener: \(error)")
        }
    }
    
    func stop() {
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        listener?.cancel()
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                var clientIp = "Dispositivo"
                if case let .hostPort(host, _) = connection.endpoint {
                    clientIp = "\(host)"
                }
                self.connections.append(connection)
                self.onClientConnected?(self.connections.count, clientIp)
                self.sendInitialStatus(to: connection)
                self.receiveMessage(from: connection)
            case .failed, .cancelled:
                self.connections.removeAll { $0 === connection }
                self.onClientConnected?(self.connections.count, "")
            default:
                break
            }
        }
    }
    
    private func receiveMessage(from connection: NWConnection) {
        connection.receiveMessage { [weak self] (content, context, isComplete, error) in
            guard let self = self else { return }
            if let data = content, let text = String(data: data, encoding: .utf8) {
                self.handleClientPayload(text)
            }
            if error == nil {
                self.receiveMessage(from: connection)
            }
        }
    }
    
    private func handleClientPayload(_ payload: String) {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else { return }
        
        let params = json["params"] as? [String: Any] ?? [:]
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.executeAction(action, params: params)
        }
    }
    
    private func executeAction(_ action: String, params: [String: Any]) {
        switch action {
        case "press_esc":
            simulateKey(keyCode: CGKeyCode(kVK_Escape))
            
        case "set_volume":
            if let vol = params["volume"] as? Int {
                setSystemVolume(vol)
                broadcastStatus()
            }
            
        case "toggle_mute":
            toggleMute()
            broadcastStatus()
            
        case "media_play_pause":
            runAppleScript("tell application \"System Events\" to key code 16 using {option down, shift down}") // Or media key
            runAppleScript("tell application \"Spotify\" to playpause\ntell application \"Music\" to playpause")
            
        case "media_next":
            runAppleScript("tell application \"Spotify\" to next track\ntell application \"Music\" to next track")
            
        case "media_prev":
            runAppleScript("tell application \"Spotify\" to previous track\ntell application \"Music\" to previous track")
            
        case "type_emoji", "type_text":
            if let text = params["text"] as? String {
                insertText(text)
            }
            
        case "send_hotkey":
            if let key = params["key"] as? String {
                let modifiers = params["modifiers"] as? [String] ?? []
                simulateHotkey(key: key, modifiers: modifiers)
            }
            
        case "play_sound":
            if let sound = params["sound"] as? String {
                NSSound(named: sound)?.play()
            }
            
        case "system_action":
            if let cmd = params["command"] as? String {
                handleSystemCommand(cmd)
            }
            
                case "shortcut", "run_shortcut":
            if let scName = params["shortcut"] as? String ?? params["name"] as? String ?? params["payload"] as? String {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                task.arguments = ["run", scName]
                try? task.run()
            }
            
        case "open_url":
            if let urlStr = params["url"] as? String ?? params["payload"] as? String, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }

        case "launch_app":
            if let app = params["app"] as? String {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/\(app).app"), configuration: NSWorkspace.OpenConfiguration())
            }
            
        case "get_status":
            broadcastStatus()
            
        default:
            break
        }
    }
    
    func broadcastStatus(frontmostApp: String? = nil) {
        let appName = frontmostApp ?? NSWorkspace.shared.frontmostApplication?.localizedName ?? "Finder"
        let volume = getSystemVolume()
        let isMuted = getIsMuted()
        let media = getMediaStatus()
        
        let status: [String: Any] = [
            "type": "status_update",
            "mac_name": Host.current().localizedName ?? "Hackintosh",
            "frontmost_app": appName,
            "volume": volume,
            "is_muted": isMuted,
            "media": media
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: status),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        for conn in connections {
            send(text: jsonString, to: conn)
        }
    }
    
    private func sendInitialStatus(to connection: NWConnection) {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Finder"
        let volume = getSystemVolume()
        let isMuted = getIsMuted()
        let media = getMediaStatus()
        
        let status: [String: Any] = [
            "type": "status_update",
            "mac_name": Host.current().localizedName ?? "Hackintosh",
            "frontmost_app": appName,
            "volume": volume,
            "is_muted": isMuted,
            "media": media
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: status),
           let jsonString = String(data: data, encoding: .utf8) {
            send(text: jsonString, to: connection)
        }
    }
    
    private func send(text: String, to connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "wsText", metadata: [metadata])
        connection.send(content: text.data(using: .utf8), contentContext: context, isComplete: true, completion: .idempotent)
    }
    
    // MARK: - Native Helpers
    private func simulateKey(keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    private func simulateHotkey(key: String, modifiers: [String]) {
        var flags: CGEventFlags = []
        if modifiers.contains("command") || modifiers.contains("cmd") { flags.insert(.maskCommand) }
        if modifiers.contains("option") || modifiers.contains("alt") { flags.insert(.maskAlternate) }
        if modifiers.contains("control") || modifiers.contains("ctrl") { flags.insert(.maskControl) }
        if modifiers.contains("shift") { flags.insert(.maskShift) }
        
        let keyCode = keyCodeFor(string: key)
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    private func insertText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        simulateHotkey(key: "v", modifiers: ["command"])
    }
    
    private func handleSystemCommand(_ cmd: String) {
        switch cmd {
        case "spotlight":
            simulateHotkey(key: "space", modifiers: ["command"])
        case "mission_control":
            runAppleScript("tell application \"Mission Control\" to launch")
        case "launchpad":
            runAppleScript("tell application \"Launchpad\" to launch")
        case "screenshot_interactive":
            simulateHotkey(key: "4", modifiers: ["command", "shift"])
        case "lock_screen":
            simulateHotkey(key: "q", modifiers: ["command", "control"])
        case "brightness_up":
            runAppleScript("tell application \"System Events\" to key code 144")
        case "brightness_down":
            runAppleScript("tell application \"System Events\" to key code 145")
        case "siri":
            simulateHotkey(key: "space", modifiers: ["option"])
        default:
            break
        }
    }
    
    private func getSystemVolume() -> Int {
        let script = "output volume of (get volume settings)"
        let result = runAppleScript(script)
        return Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 50
    }
    
    private func getIsMuted() -> Bool {
        let script = "output muted of (get volume settings)"
        let result = runAppleScript(script)
        return result.contains("true")
    }
    
    private func setSystemVolume(_ volume: Int) {
        let clamped = max(0, min(100, volume))
        runAppleScript("set volume output volume \(clamped)")
    }
    
    private func toggleMute() {
        let muted = getIsMuted()
        runAppleScript("set volume output muted \(muted ? "false" : "true")")
    }
    
    private func getMediaStatus() -> [String: String] {
        let spotifyScript = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    return (get artist of current track) & " - " & (get name of current track)
                end if
            end tell
        end if
        return ""
        """
        let track = runAppleScript(spotifyScript).trimmingCharacters(in: .whitespacesAndNewlines)
        if !track.isEmpty {
            let parts = track.components(separatedBy: " - ")
            return ["player": "Spotify", "artist": parts.first ?? "", "title": parts.last ?? "", "state": "playing"]
        }
        return ["player": "None", "artist": "", "title": "", "state": "stopped"]
    }
    
    @discardableResult
    private func runAppleScript(_ script: String) -> String {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return output.stringValue ?? ""
            }
        }
        return ""
    }
    
    private func keyCodeFor(string: String) -> CGKeyCode {
        switch string.lowercased() {
        case "a": return 0x00
        case "s": return 0x01
        case "d": return 0x02
        case "f": return 0x03
        case "h": return 0x04
        case "g": return 0x05
        case "z": return 0x06
        case "x": return 0x07
        case "c": return 0x08
        case "v": return 0x09
        case "b": return 0x0B
        case "q": return 0x0C
        case "w": return 0x0D
        case "e": return 0x0E
        case "r": return 0x0F
        case "y": return 0x10
        case "t": return 0x11
        case "1": return 0x12
        case "2": return 0x13
        case "3": return 0x14
        case "4": return 0x15
        case "6": return 0x16
        case "5": return 0x17
        case "9": return 0x19
        case "7": return 0x1A
        case "8": return 0x1C
        case "0": return 0x1D
        case "o": return 0x1F
        case "u": return 0x20
        case "i": return 0x22
        case "p": return 0x23
        case "l": return 0x25
        case "j": return 0x26
        case "k": return 0x28
        case "m": return 0x2E
        case "n": return 0x2D
        case "space": return 0x31
        case "delete", "backspace": return 0x33
        case "tab": return 0x30
        case "escape", "esc": return 0x35
        case "return", "enter": return 0x24
        case "f1": return 0x7A
        case "f2": return 0x78
        case "f3": return 0x63
        case "f4": return 0x76
        case "f5": return 0x60
        case "f6": return 0x61
        case "f7": return 0x62
        case "f8": return 0x64
        case "f9": return 0x65
        case "f10": return 0x6D
        case "f11": return 0x67
        case "f12": return 0x6F
        case "`": return 0x32
        case "[": return 0x21
        case "]": return 0x1E
        default: return 0x00
        }
    }
}
