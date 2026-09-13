import SwiftUI
import AppKit

struct ShortcutTesterView: View {
    @EnvironmentObject var monitor: SystemMonitor
    
    @State private var customKey: String = "G"
    @State private var useCommand: Bool = true
    @State private var useShift: Bool = false
    @State private var useOption: Bool = false
    @State private var useControl: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcut Studio")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Teste disparos de teclas e atalhos diretamente no Mac para validar o comportamento dos apps.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Target App Notice
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.title2)
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alvo Atual: \(monitor.activeAppName)")
                            .font(.headline)
                        Text("Os atalhos abaixo serão injetados diretamente na janela ativa do macOS.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    Button("Recarregar App") {
                        monitor.updateActiveApp()
                    }
                    .font(.caption)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                
                // Custom Shortcut Inserter
                VStack(alignment: .leading, spacing: 14) {
                    Text("Injetor de Teclas Customizadas")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        // Modifiers Toggles
                        Toggle("⌘ Cmd", isOn: $useCommand)
                            .toggleStyle(.button)
                        Toggle("⇧ Shift", isOn: $useShift)
                            .toggleStyle(.button)
                        Toggle("⌥ Opt", isOn: $useOption)
                            .toggleStyle(.button)
                        Toggle("⌃ Ctrl", isOn: $useControl)
                            .toggleStyle(.button)
                        
                        TextField("Tecla", text: $customKey)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .font(.system(.body, design: .monospaced).weight(.bold))
                        
                        Spacer()
                        
                        Button(action: sendCustomShortcut) {
                            Label("Disparar no Mac", systemImage: "bolt.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                
                // Predefined Groups
                VStack(alignment: .leading, spacing: 16) {
                    Text("Atalhos do Illustrator Cadastrados")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ShortcutTestCard(title: "Agrupar", keys: "⌘G", description: "Agrupa os objetos selecionados") {
                            monitor.triggerShortcut(key: "g", modifiers: [.command])
                        }
                        
                        ShortcutTestCard(title: "Desagrupar", keys: "⌘⇧G", description: "Desfaz o grupo da seleção") {
                            monitor.triggerShortcut(key: "g", modifiers: [.command, .shift])
                        }
                        
                        ShortcutTestCard(title: "Centralizar Prancheta", keys: "C-Pranch", description: "Centraliza horizontal e vertical na prancheta") {
                            monitor.triggerActionPayload("align_center_artboard")
                        }
                        
                        ShortcutTestCard(title: "Contornos de Texto", keys: "⌘⇧O", description: "Converte fonte em curvas vetoriais") {
                            monitor.triggerShortcut(key: "o", modifiers: [.command, .shift])
                        }
                        
                        ShortcutTestCard(title: "Criar Máscara", keys: "⌘7", description: "Cria máscara de recorte no Illustrator") {
                            monitor.triggerShortcut(key: "7", modifiers: [.command])
                        }
                        
                        ShortcutTestCard(title: "Liberar Máscara", keys: "⌘⌥7", description: "Solta máscara de recorte") {
                            monitor.triggerShortcut(key: "7", modifiers: [.command, .option])
                        }
                        
                        ShortcutTestCard(title: "Bloquear Seleção", keys: "⌘2", description: "Trava elementos para não mover") {
                            monitor.triggerShortcut(key: "2", modifiers: [.command])
                        }
                        
                        ShortcutTestCard(title: "Desbloquear Tudo", keys: "⌘⌥2", description: "Libera todas as camadas bloqueadas") {
                            monitor.triggerShortcut(key: "2", modifiers: [.command, .option])
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private func sendCustomShortcut() {
        var mods: KeyModifiers = []
        if useCommand { mods.insert(.command) }
        if useShift   { mods.insert(.shift) }
        if useOption  { mods.insert(.option) }
        if useControl { mods.insert(.control) }
        
        monitor.triggerShortcut(key: customKey, modifiers: mods)
    }
}

struct ShortcutTestCard: View {
    let title: String
    let keys: String
    let description: String
    let onFire: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(keys)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.2)))
                        .foregroundColor(.orange)
                }
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: onFire) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Disparar agora")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}
