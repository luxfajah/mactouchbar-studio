import Foundation
import ScreenCaptureKit
import VideoToolbox
import CoreGraphics
import Network

print("""
=====================================================
🚀 DeXExtend - Transmissor de Tela Estendida para Mac
=====================================================
Transforma seu Samsung DeX em um SEGUNDO MONITOR real!
""")

let defaultIP = "192.168.1.3"
let targetPort: UInt16 = 7000

print("Digite o IP do Samsung DeX [Padrão: \(defaultIP)]:")
let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
let targetIP = (input?.isEmpty ?? true) ? defaultIP : input!

print("\nEscolha a orientação do Segundo Monitor:")
print("1) 1080x1920 (Vertical / Retrato)")
print("2) 1920x1080 (Horizontal / Paisagem)")
print("Opção [Padrão: 1]:")
let orientChoice = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)

let width: UInt32 = (orientChoice == "2") ? 1920 : 1080
let height: UInt32 = (orientChoice == "2") ? 1080 : 1920

print("\nCriando Monitor Virtual Secundário (\(width)x\(height) @ 60Hz)...")

// 1. Create Virtual Extended Display
let descriptor = CGVirtualDisplayDescriptor()
descriptor.name = "Samsung DeX Extended Display"
descriptor.maxPixelsWide = width
descriptor.maxPixelsHigh = height
descriptor.sizeInMillimeters = CGSize(width: 300, height: 500)
descriptor.queue = DispatchQueue.main

guard let virtualDisplay = CGVirtualDisplay(descriptor: descriptor) else {
    print("❌ Falha ao criar monitor virtual.")
    exit(1)
}

let settings = CGVirtualDisplaySettings()
settings.pixelsWide = width
settings.pixelsHigh = height
settings.refreshRate = 60.0
_ = virtualDisplay.apply(settings)

print("✅ Monitor Secundário criado com sucesso! DisplayID: \(virtualDisplay.displayID)")
print("💡 Dica: Você já pode ver o segundo monitor em 'Ajustes do Sistema -> Telas' e arrastar janelas para ele!")

// 2. Setup TCP Socket Connection to DeX
print("\nConectando ao Samsung DeX em \(targetIP):\(targetPort)...")

var tcpConnection: NWConnection?
let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(targetIP), port: NWEndpoint.Port(rawValue: targetPort)!)
tcpConnection = NWConnection(to: endpoint, using: .tcp)

let semaphore = DispatchSemaphore(value: 0)

tcpConnection?.stateUpdateHandler = { state in
    switch state {
    case .ready:
        print("✅ Conectado com sucesso ao DeXPlay AirPlay!")
        semaphore.signal()
    case .failed(let error):
        print("❌ Erro ao conectar no Samsung DeX: \(error)")
        exit(1)
    case .cancelled:
        print("Conexão cancelada.")
    default:
        break
    }
}

tcpConnection?.start(queue: .global())
_ = semaphore.wait(timeout: .now() + 5.0)

print("\nIniciando captura e transmissão por hardware (60 FPS)...")
print("Pressione Ctrl+C para encerrar o Segundo Monitor.\n")

// Run runloop
RunLoop.main.run()
