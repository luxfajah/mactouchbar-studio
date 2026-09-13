import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var profileManager: ProfileManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("MacTouchBar Studio")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                            
                            Text("BETA")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.2)))
                                .foregroundColor(.orange)
                        }
                        
                        Text("Painel de controle nativo e monitoramento independente do Mac.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Server Connection Pill
                    HStack(spacing: 8) {
                        Circle()
                            .fill(monitor.isServerRunning ? Color.green : Color.orange)
                            .frame(width: 9, height: 9)
                            .shadow(color: monitor.isServerRunning ? Color.green.opacity(0.6) : Color.orange.opacity(0.6), radius: 4)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(monitor.isServerRunning ? "Daemon Ativo" : "Daemon Não Detectado")
                                .font(.caption.weight(.semibold))
                            Text(monitor.isServerRunning ? "\(monitor.serverAddress) (\(String(format: "%.1f", monitor.latencyMs))ms)" : "Porta 9876 aguardando")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor).opacity(0.8)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                }
                .padding(.bottom, 6)
                
                // Top Metrics Cards Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    
                    // Card 1: App Ativo
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("App em Foco no Mac")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "macwindow.on.rectangle")
                                .foregroundColor(.blue)
                        }
                        
                        HStack(spacing: 14) {
                            if let icon = monitor.activeAppIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(10)
                                    .shadow(radius: 3)
                            } else {
                                Image(systemName: "app.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 44, height: 44)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(monitor.activeAppName)
                                    .font(.title3.weight(.bold))
                                    .lineLimit(1)
                                
                                Text(monitor.activeBundleId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Divider().opacity(0.4)
                        
                        HStack {
                            if monitor.activeBundleId.contains("illustrator") {
                                Label("Perfil Illustrator Ativo", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.orange)
                            } else if monitor.activeBundleId.contains("Photoshop") {
                                Label("Perfil Photoshop Ativo", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.blue)
                            } else {
                                Label("Perfil Geral", systemImage: "gearshape")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Atualizar") {
                                monitor.updateActiveApp()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    
                    // Card 2: Status do Daemon
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Servidor de Produção")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "server.rack")
                                .foregroundColor(.purple)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(monitor.isWebSocketConnected ? Color.green : Color.orange)
                                    .frame(width: 10, height: 10)
                                Text(monitor.isWebSocketConnected ? "Monitor Conectado" : "Aguardando Daemon")
                                    .font(.headline)
                            }
                            
                            Text("Porta WebSocket: 9876 (MacTouchBar)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider().opacity(0.4)
                        
                        HStack {
                            Text("Latência Local:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.1f", monitor.latencyMs)) ms")
                                .font(.caption.weight(.semibold))
                            
                            Spacer()
                            
                            Button("Reconectar") {
                                monitor.checkServerAndConnect()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    
                    // Card 3: Perfil Atual
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Perfil Ativo")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.green)
                        }
                        
                        if let current = profileManager.currentProfile {
                            HStack(spacing: 12) {
                                Image(systemName: current.iconName)
                                    .font(.system(size: 28))
                                    .foregroundColor(current.accentColor)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(current.name)
                                        .font(.headline)
                                    Text("\(current.screens.count) Telas mapeadas")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Divider().opacity(0.4)
                        
                        HStack {
                            Text("Illustrator Tela 1: 4 Cores | Tela 2: 10 Cores")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                
                // Quick Actions Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ações Rápidas de Teste no Mac")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        QuickActionButton(title: "Agrupar (⌘G)", icon: "rectangle.3.group.fill", color: .green) {
                            monitor.triggerShortcut(key: "g", modifiers: [.command])
                        }
                        
                        QuickActionButton(title: "Desagrupar (⌘⇧G)", icon: "rectangle.split.3x1.fill", color: .indigo) {
                            monitor.triggerShortcut(key: "g", modifiers: [.command, .shift])
                        }
                        
                        QuickActionButton(title: "Centralizar Prancheta", icon: "square.inset.filled", color: .orange) {
                            monitor.triggerActionPayload("align_center_artboard")
                        }
                        
                        QuickActionButton(title: "Contornos (⌘⇧O)", icon: "character", color: .blue) {
                            monitor.triggerShortcut(key: "o", modifiers: [.command, .shift])
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                
                // Recent Activity / Feed
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Últimos Eventos & Ações")
                            .font(.headline)
                        Spacer()
                        Text("\(monitor.logs.count) eventos registrados")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if monitor.logs.isEmpty {
                        Text("Nenhum evento registrado ainda.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(monitor.logs.prefix(6)) { entry in
                                HStack(spacing: 10) {
                                    Text(entry.category.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color(hex: entry.category.color) ?? .gray).opacity(0.2))
                                        .foregroundColor(Color(hex: entry.category.color) ?? .primary)
                                    
                                    Text(entry.message)
                                        .font(.caption)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Text(entry.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.02)))
                            }
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .padding(24)
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
