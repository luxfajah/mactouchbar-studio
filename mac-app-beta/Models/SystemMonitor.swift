import Foundation
import AppKit
import Combine
import Carbon.HIToolbox

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let category: LogCategory
    let message: String
    
    enum LogCategory: String, CaseIterable {
        case info = "INFO"
        case shortcut = "ATALHO"
        case network = "REDE"
        case app = "APP"
        case error = "ERRO"
        
        var color: String {
            switch self {
            case .info: return "#007AFF"
            case .shortcut: return "#34C759"
            case .network: return "#AF52DE"
            case .app: return "#FF9500"
            case .error: return "#FF3B30"
            }
        }
    }
}

class SystemMonitor: ObservableObject {
    @Published var activeAppName: String = "Finder"
    @Published var activeBundleId: String = "com.apple.finder"
    @Published var activeAppIcon: NSImage? = nil
    
    @Published var isServerRunning: Bool = false
    @Published var isWebSocketConnected: Bool = false
    @Published var serverAddress: String = "127.0.0.1:9876"
    @Published var latencyMs: Double = 0.0
    
    @Published var logs: [LogEntry] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession = URLSession(configuration: .default)
    private var pingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        updateActiveApp()
        setupAppObserver()
        checkServerAndConnect()
        
        addLog(.info, "MacTouchBar Beta Studio iniciado em modo de monitoramento isolado.")
    }
    
    deinit {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        pingTimer?.invalidate()
    }
    
    func addLog(_ category: LogEntry.LogCategory, _ message: String) {
        DispatchQueue.main.async {
            let entry = LogEntry(timestamp: Date(), category: category, message: message)
            self.logs.insert(entry, at: 0)
            if self.logs.count > 200 {
                self.logs.removeLast()
            }
        }
    }
    
    // MARK: - Active App Detection
    private func setupAppObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateActiveApp()
        }
    }
    
    func updateActiveApp() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            self.activeAppName = frontApp.localizedName ?? "Desconhecido"
            self.activeBundleId = frontApp.bundleIdentifier ?? ""
            self.activeAppIcon = frontApp.icon
            
            addLog(.app, "App em foco: \(self.activeAppName) (\(self.activeBundleId))")
        }
    }
    
    // MARK: - Safe Local WebSocket Monitor
    func checkServerAndConnect() {
        guard let url = URL(string: "ws://\(serverAddress)") else { return }
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        
        listenWebSocket()
        
        // Enviar identificação como cliente Beta Monitor
        let ident = "{\"type\":\"identify\",\"client\":\"MacTouchBarBetaMonitor\"}"
        webSocketTask?.send(.string(ident)) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.isWebSocketConnected = false
                    self?.isServerRunning = false
                    self?.addLog(.network, "Servidor 9876 indisponível: \(error.localizedDescription)")
                } else {
                    self?.isWebSocketConnected = true
                    self?.isServerRunning = true
                    self?.addLog(.network, "Conectado ao MacTouchBar Daemon em \(self?.serverAddress ?? "")")
                }
            }
        }
        
        startPingTimer()
    }
    
    private func listenWebSocket() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                DispatchQueue.main.async {
                    self?.isWebSocketConnected = true
                    self?.isServerRunning = true
                }
                switch message {
                case .string(let text):
                    self?.addLog(.network, "Msg recebida: \(text.prefix(60))")
                case .data(let data):
                    self?.addLog(.network, "Dados binários recebidos: \(data.count) bytes")
                @unknown default:
                    break
                }
                self?.listenWebSocket() // Continuar escutando
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.isWebSocketConnected = false
                }
                // Tentar reconectar suavemente após 5s
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.checkServerAndConnect()
                }
            }
        }
    }
    
    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            let start = Date()
            self?.webSocketTask?.sendPing { error in
                DispatchQueue.main.async {
                    if error == nil {
                        self?.latencyMs = Date().timeIntervalSince(start) * 1000.0
                        self?.isServerRunning = true
                    } else {
                        self?.isWebSocketConnected = false
                    }
                }
            }
        }
    }
    
    // MARK: - Execute / Test Shortcut
    func triggerShortcut(key: String, modifiers: KeyModifiers, appTarget: String? = nil) {
        addLog(.shortcut, "Disparando atalho: \(modifiers.displayString)\(key.uppercased()) para \(activeAppName)")
        
        let keyCode = keyCodeForChar(key)
        guard keyCode != 0xFFFF else {
            addLog(.error, "Código de tecla desconhecido para '\(key)'")
            return
        }
        
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift)   { flags.insert(.maskShift) }
        if modifiers.contains(.option)  { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        
        keyDown?.flags = flags
        keyUp?.flags = flags
        
        keyDown?.post(tap: .cghidEventTap)
        usleep(15000)
        keyUp?.post(tap: .cghidEventTap)
        
        addLog(.info, "✓ Atalho enviado com sucesso ao sistema")
    }
    
    func triggerActionPayload(_ payload: String) {
        addLog(.shortcut, "Disparando ação: \(payload)")
        
        // Se o WebSocket estiver ativo, podemos enviar a ação para o daemon executar nativamente
        if isWebSocketConnected {
            let msg = "{\"type\":\"action\",\"payload\":\"\(payload)\"}"
            webSocketTask?.send(.string(msg)) { [weak self] error in
                if let error = error {
                    self?.addLog(.error, "Falha ao enviar ação via WebSocket: \(error.localizedDescription)")
                } else {
                    self?.addLog(.info, "✓ Ação enviada ao daemon MacTouchBar")
                }
            }
        } else {
            addLog(.info, "Modo autônomo: simulando resposta de '\(payload)'")
        }
    }
    
    private func keyCodeForChar(_ char: String) -> CGKeyCode {
        guard let first = char.lowercased().first else { return 0xFFFF }
        switch first {
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
        default: return 0xFFFF
        }
    }
}
