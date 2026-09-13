import SwiftUI
import AppKit

struct ProfileEditorView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var monitor: SystemMonitor
    
    @State private var selectedButton: TouchBarButton? = nil
    @State private var showingEditSheet: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Profile & Screen Selector Header
            HStack(spacing: 16) {
                // Profile Picker
                Picker("Perfil", selection: $profileManager.selectedProfileId) {
                    ForEach(profileManager.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                
                Spacer()
                
                // Screen Tabs if profile has multiple screens
                if let profile = profileManager.currentProfile, profile.screens.count > 1 {
                    Picker("Tela", selection: $profileManager.selectedScreenIndex) {
                        ForEach(0..<profile.screens.count, id: \.self) { idx in
                            Text(profile.screens[idx].title).tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 380)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .overlay(Divider(), alignment: .bottom)
            
            // Content Body
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let profile = profileManager.currentProfile,
                       profileManager.selectedScreenIndex < profile.screens.count {
                        
                        let currentScreen = profile.screens[profileManager.selectedScreenIndex]
                        
                        // Screen Header & Badge
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(currentScreen.title)
                                    .font(.title2.weight(.bold))
                                Text("Perfil: \(profile.name) • \(profile.bundleId)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Label("\(currentScreen.blocks.count) Blocos configurados", systemImage: "square.grid.2x2")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                        
                        // Recent Colors Preview Strip
                        if !currentScreen.recentColors.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Cores Recentes na Barra")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(currentScreen.recentColors.count) cores ativas")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack(spacing: 10) {
                                    ForEach(currentScreen.recentColors, id: \.self) { hex in
                                        Circle()
                                            .fill(Color(hex: hex) ?? .gray)
                                            .frame(width: 32, height: 32)
                                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
                                            .shadow(color: Color.black.opacity(0.2), radius: 3, y: 1)
                                            .help("Cor \(hex)")
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            }
                        }
                        
                        // Blocks Render (Rows of 3 and 4 buttons)
                        ForEach(currentScreen.blocks) { block in
                            TouchBarBlockCard(
                                block: block,
                                accentColor: profile.accentColor,
                                onSelectButton: { btn in
                                    selectedButton = btn
                                    showingEditSheet = true
                                },
                                onTestButton: { btn in
                                    triggerButton(btn)
                                }
                            )
                        }
                    }
                }
                .padding(24)
            }
        }
        .sheet(item: $selectedButton) { button in
            ButtonInspectorSheet(button: button) { testBtn in
                triggerButton(testBtn)
            }
        }
    }
    
    private func triggerButton(_ btn: TouchBarButton) {
        if !btn.key.isEmpty {
            monitor.triggerShortcut(key: btn.key, modifiers: btn.modifiers)
        } else if !btn.actionPayload.isEmpty {
            monitor.triggerActionPayload(btn.actionPayload)
        }
    }
}

// MARK: - Block Card with 2 rows of buttons
struct TouchBarBlockCard: View {
    let block: TouchBarBlock
    let accentColor: Color
    let onSelectButton: (TouchBarButton) -> Void
    let onTestButton: (TouchBarButton) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(block.title)
                    .font(.headline)
                
                if let badge = block.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accentColor.opacity(0.2)))
                        .foregroundColor(accentColor)
                }
                
                Spacer()
                
                Text("Clique para inspecionar ou use ▶ para testar")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                // Row 1: usually 3 buttons
                HStack(spacing: 8) {
                    ForEach(block.row1) { btn in
                        TouchBarButtonView(button: btn, onSelect: { onSelectButton(btn) }, onTest: { onTestButton(btn) })
                    }
                }
                
                // Row 2: 3 or 4 buttons
                HStack(spacing: 8) {
                    ForEach(block.row2) { btn in
                        TouchBarButtonView(button: btn, onSelect: { onSelectButton(btn) }, onTest: { onTestButton(btn) })
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3)))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Individual Button View
struct TouchBarButtonView: View {
    let button: TouchBarButton
    let onSelect: () -> Void
    let onTest: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: button.iconName)
                        .font(.system(size: 14))
                        .foregroundColor(button.colorHex != nil ? (Color(hex: button.colorHex!) ?? .primary) : .primary)
                    
                    Text(button.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                
                if !button.shortcutDisplay.isEmpty {
                    Text(button.shortcutDisplay)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(button.colorHex != nil ? (Color(hex: button.colorHex!) ?? .gray).opacity(0.18) : Color(NSColor.controlColor).opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
            )
            .overlay(
                // Small Play Test Button on hover
                HStack {
                    Spacer()
                    VStack {
                        Button(action: onTest) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Testar disparo no Mac")
                        .padding(4)
                        Spacer()
                    }
                }
                .opacity(isHovered ? 1.0 : 0.0)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Button Inspector Sheet
struct ButtonInspectorSheet: View {
    @Environment(\.dismiss) var dismiss
    let button: TouchBarButton
    let onTest: (TouchBarButton) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: button.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(button.colorHex != nil ? Color(hex: button.colorHex!) : .accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(button.title)
                        .font(.title2.weight(.bold))
                    Text(button.description.isEmpty ? "Ação rápida da TouchBar" : button.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Fechar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("ID da Ação:")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 120, alignment: .leading)
                    Text(button.id)
                        .font(.system(.body, design: .monospaced))
                }
                
                HStack {
                    Text("Atalho de Teclado:")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 120, alignment: .leading)
                    Text(button.shortcutDisplay.isEmpty ? "Nenhum (Ação interna)" : button.shortcutDisplay)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                }
                
                HStack {
                    Text("Payload da Ação:")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 120, alignment: .leading)
                    Text(button.actionPayload)
                        .font(.system(.body, design: .monospaced))
                }
                
                if let colorHex = button.colorHex {
                    HStack {
                        Text("Cor de Destaque:")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 120, alignment: .leading)
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: colorHex) ?? .clear).frame(width: 16, height: 16)
                            Text(colorHex)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            
            Spacer()
            
            HStack {
                Button(action: {
                    onTest(button)
                }) {
                    Label("Testar Disparo no Mac Agora", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
    }
}
