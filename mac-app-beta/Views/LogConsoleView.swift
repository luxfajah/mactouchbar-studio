import SwiftUI
import AppKit

struct LogConsoleView: View {
    @EnvironmentObject var monitor: SystemMonitor
    
    @State private var selectedCategory: LogEntry.LogCategory? = nil
    @State private var searchText: String = ""
    
    var filteredLogs: [LogEntry] {
        monitor.logs.filter { entry in
            let matchesCategory = selectedCategory == nil || entry.category == selectedCategory
            let matchesSearch = searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Category Filter Pills
                Button(action: { selectedCategory = nil }) {
                    Text("Todos (\(monitor.logs.count))")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(selectedCategory == nil ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .foregroundColor(selectedCategory == nil ? .white : .primary)
                }
                .buttonStyle(.plain)
                
                ForEach(LogEntry.LogCategory.allCases, id: \.self) { cat in
                    Button(action: { selectedCategory = cat }) {
                        Text(cat.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(selectedCategory == cat ? Color(hex: cat.color) ?? .accentColor : Color.secondary.opacity(0.15)))
                            .foregroundColor(selectedCategory == cat ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filtrar logs...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
                .frame(width: 180)
                
                // Clear Button
                Button(action: {
                    monitor.logs.removeAll()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Limpar logs")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
            .overlay(Divider(), alignment: .bottom)
            
            // Console Stream
            if filteredLogs.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Nenhum registro de log encontrado")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredLogs) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.timestamp, style: .time)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 65, alignment: .leading)
                            
                            Text(entry.category.rawValue)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(hex: entry.category.color) ?? .gray).opacity(0.2))
                                .foregroundColor(Color(hex: entry.category.color) ?? .primary)
                                .frame(width: 60)
                            
                            Text(entry.message)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}
