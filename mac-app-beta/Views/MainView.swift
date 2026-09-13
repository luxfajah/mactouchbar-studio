import SwiftUI
import AppKit

enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case profiles = "Perfis de Apps"
    case shortcuts = "Testador de Atalhos"
    case logs = "Logs & Diagnóstico"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle"
        case .profiles: return "square.grid.2x2"
        case .shortcuts: return "keyboard"
        case .logs: return "terminal"
        }
    }
}

struct MainView: View {
    @State private var selectedItem: NavigationItem? = .dashboard
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var profileManager: ProfileManager
    
    var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, selection: $selectedItem) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.body.weight(.medium))
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Divider()
                    HStack(spacing: 8) {
                        Circle()
                            .fill(monitor.isServerRunning ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(monitor.isServerRunning ? "Daemon Ativo (:9876)" : "Modo Isolado")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("v1.0-beta")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        } detail: {
            Group {
                switch selectedItem ?? .dashboard {
                case .dashboard:
                    DashboardView()
                case .profiles:
                    ProfileEditorView()
                case .shortcuts:
                    ShortcutTesterView()
                case .logs:
                    LogConsoleView()
                }
            }
            .frame(minWidth: 700, minHeight: 520)
        }
    }
}
