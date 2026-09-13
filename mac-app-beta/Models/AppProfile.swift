import Foundation
import SwiftUI

// MARK: - Modifiers Mask
struct KeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int
    
    static let command = KeyModifiers(rawValue: 1 << 0)
    static let shift   = KeyModifiers(rawValue: 1 << 1)
    static let option  = KeyModifiers(rawValue: 1 << 2)
    static let control = KeyModifiers(rawValue: 1 << 3)
    
    var displayString: String {
        var res = ""
        if contains(.control) { res += "⌃" }
        if contains(.option)  { res += "⌥" }
        if contains(.shift)   { res += "⇧" }
        if contains(.command) { res += "⌘" }
        return res
    }
}

// MARK: - TouchBar Button Model
struct TouchBarButton: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var iconName: String
    var isSystemSymbol: Bool = true
    var key: String = ""
    var modifiers: KeyModifiers = []
    var actionPayload: String = ""
    var badge: String? = nil
    var colorHex: String? = nil
    var description: String = ""
    
    var shortcutDisplay: String {
        if !key.isEmpty {
            return "\(modifiers.displayString)\(key)"
        }
        return actionPayload
    }
    
    var tintColor: Color {
        if let hex = colorHex, let c = Color(hex: hex) {
            return c
        }
        return .primary
    }
}

// MARK: - Block with 2 rows
struct TouchBarBlock: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var row1: [TouchBarButton]
    var row2: [TouchBarButton]
    var badge: String? = nil
}

// MARK: - Screen Model
struct AppScreen: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var iconName: String
    var blocks: [TouchBarBlock]
    var recentColors: [String] = []
}

// MARK: - App Profile
struct AppProfile: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var bundleId: String
    var iconName: String
    var accentColorHex: String
    var screens: [AppScreen]
    
    var accentColor: Color {
        Color(hex: accentColorHex) ?? .blue
    }
}

// MARK: - Hex Color Helper
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Default Profiles Store via Clean JSON
class ProfileManager: ObservableObject {
    @Published var profiles: [AppProfile] = []
    @Published var selectedProfileId: String = "illustrator"
    @Published var selectedScreenIndex: Int = 0
    
    init() {
        loadDefaultProfiles()
    }
    
    var currentProfile: AppProfile? {
        profiles.first(where: { $0.id == selectedProfileId })
    }
    
    func loadDefaultProfiles() {
        if let data = defaultProfilesJSON.data(using: .utf8) {
            do {
                self.profiles = try JSONDecoder().decode([AppProfile].self, from: data)
                return
            } catch {
                print("Erro ao carregar profiles json: \(error)")
            }
        }
        self.profiles = []
    }
}

// Clean JSON Definition
private let defaultProfilesJSON: String = """
[
  {
    "id": "illustrator",
    "name": "Adobe Illustrator",
    "bundleId": "com.adobe.illustrator",
    "iconName": "paintbrush.pointed.fill",
    "accentColorHex": "#FF9A00",
    "screens": [
      {
        "id": "ai-screen-1",
        "title": "Tela 1: Ferramentas & Vetor",
        "iconName": "square.dashed",
        "recentColors": ["#000000", "#FFFFFF", "#FF3B30", "#007AFF"],
        "blocks": [
          {
            "id": "ai-tools",
            "title": "Ferramentas Rápidas",
            "badge": "6 Ferramentas",
            "row1": [
              {"id": "tool_v", "title": "Seleção (V)", "iconName": "cursorarrow", "key": "v", "actionPayload": "tool_v", "description": "Ferramenta de seleção principal"},
              {"id": "tool_a", "title": "Direta (A)", "iconName": "cursorarrow.motionlines", "key": "a", "actionPayload": "tool_a", "description": "Seleção direta de pontos"},
              {"id": "tool_p", "title": "Caneta (P)", "iconName": "pencil.tip", "key": "p", "actionPayload": "tool_p", "description": "Caneta Bézier"}
            ],
            "row2": [
              {"id": "tool_m", "title": "Retângulo (M)", "iconName": "rectangle", "key": "m", "actionPayload": "tool_m", "description": "Forma retângulo"},
              {"id": "tool_t", "title": "Texto (T)", "iconName": "textformat", "key": "t", "actionPayload": "tool_t", "description": "Ferramenta de texto"},
              {"id": "tool_b", "title": "Pincel (B)", "iconName": "paintbrush", "key": "b", "actionPayload": "tool_b", "description": "Pincel de vetor"}
            ]
          },
          {
            "id": "ai-align",
            "title": "Alinhamento de Objetos",
            "badge": "7 Ações",
            "row1": [
              {"id": "align_left", "title": "Esquerda", "iconName": "align.horizontal.left", "actionPayload": "align_left", "description": "Alinhar à esquerda"},
              {"id": "align_center_h", "title": "Centro", "iconName": "align.horizontal.center", "actionPayload": "align_center_h", "description": "Alinhar ao centro horizontal"},
              {"id": "align_right", "title": "Direita", "iconName": "align.horizontal.right", "actionPayload": "align_right", "description": "Alinhar à direita"}
            ],
            "row2": [
              {"id": "align_top", "title": "Topo", "iconName": "align.vertical.top", "actionPayload": "align_top", "description": "Alinhar ao topo"},
              {"id": "align_center_v", "title": "Meio", "iconName": "align.vertical.center", "actionPayload": "align_center_v", "description": "Alinhar ao meio vertical"},
              {"id": "align_bottom", "title": "Base", "iconName": "align.vertical.bottom", "actionPayload": "align_bottom", "description": "Alinhar à base"},
              {"id": "align_center_artboard", "title": "C-Pranch", "iconName": "square.inset.filled", "actionPayload": "align_center_artboard", "colorHex": "#FF9500", "description": "Centralizar na prancheta ativa"}
            ]
          },
          {
            "id": "ai-pathfinder",
            "title": "Pathfinder & Grupos",
            "badge": "7 Ações",
            "row1": [
              {"id": "path_unite", "title": "Unir", "iconName": "plus.square.fill", "actionPayload": "pathfinder_unite", "description": "Unir formas selecionadas"},
              {"id": "path_minus", "title": "Menos Frente", "iconName": "minus.square.fill", "actionPayload": "pathfinder_minus_front", "description": "Subtrair forma da frente"},
              {"id": "path_intersect", "title": "Intersecção", "iconName": "circle.circle.fill", "actionPayload": "pathfinder_intersect", "description": "Manter apenas intersecção"}
            ],
            "row2": [
              {"id": "path_exclude", "title": "Excluir", "iconName": "xmark.square.fill", "actionPayload": "pathfinder_exclude", "description": "Excluir sobreposição"},
              {"id": "path_divide", "title": "Dividir", "iconName": "square.split.2x2.fill", "actionPayload": "pathfinder_divide", "description": "Dividir formas em pedaços"},
              {"id": "group", "title": "Agrupar", "iconName": "rectangle.3.group.fill", "key": "g", "modifiers": 1, "actionPayload": "group", "colorHex": "#34C759", "description": "Agrupar seleção (⌘G)"},
              {"id": "ungroup", "title": "Desagrup", "iconName": "rectangle.split.3x1.fill", "key": "g", "modifiers": 3, "actionPayload": "ungroup", "colorHex": "#5856D6", "description": "Desagrupar seleção (⌘⇧G)"}
            ]
          }
        ]
      },
      {
        "id": "ai-screen-2",
        "title": "Tela 2: Tipografia & Histórico",
        "iconName": "text.alignleft",
        "recentColors": ["#000000", "#FFFFFF", "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#5856D6", "#AF52DE", "#8E8E93"],
        "blocks": [
          {
            "id": "ai-text-align",
            "title": "Alinhamento Tipográfico",
            "badge": "7 Opções",
            "row1": [
              {"id": "text_align_left", "title": "Esquerda", "iconName": "text.alignleft", "key": "l", "modifiers": 3, "actionPayload": "text_align_left", "description": "Alinhar texto à esquerda (⌘⇧L)"},
              {"id": "text_align_center", "title": "Centro", "iconName": "text.aligncenter", "key": "c", "modifiers": 3, "actionPayload": "text_align_center", "description": "Centralizar texto (⌘⇧C)"},
              {"id": "text_align_right", "title": "Direita", "iconName": "text.alignright", "key": "r", "modifiers": 3, "actionPayload": "text_align_right", "description": "Alinhar texto à direita (⌘⇧R)"}
            ],
            "row2": [
              {"id": "text_just_left", "title": "Just. Esq.", "iconName": "text.justify.left", "key": "j", "modifiers": 3, "actionPayload": "text_justify_left", "description": "Justificado com última linha à esquerda (⌘⇧J)"},
              {"id": "text_just_center", "title": "Just. Centro", "iconName": "text.justify.trailing", "actionPayload": "text_justify_center", "description": "Justificado com última linha no centro"},
              {"id": "text_just_right", "title": "Just. Dir.", "iconName": "text.justify.leading", "actionPayload": "text_justify_right", "description": "Justificado com última linha à direita"},
              {"id": "text_just_all", "title": "Just. Todo", "iconName": "text.justify", "key": "f", "modifiers": 3, "actionPayload": "text_justify_all", "description": "Justificar todas as linhas (⌘⇧F)"}
            ]
          },
          {
            "id": "ai-actions",
            "title": "Atalhos de Produção",
            "badge": "7 Ações",
            "row1": [
              {"id": "create_outlines", "title": "Contornos", "iconName": "character", "key": "o", "modifiers": 3, "actionPayload": "create_outlines", "description": "Converter texto em curvas (⌘⇧O)"},
              {"id": "make_guide", "title": "Criar Guia", "iconName": "ruler", "key": "5", "modifiers": 1, "actionPayload": "make_guide", "description": "Transformar objeto em guia (⌘5)"},
              {"id": "clipping_mask", "title": "Máscara", "iconName": "camera.viewfinder", "key": "7", "modifiers": 1, "actionPayload": "make_clipping_mask", "description": "Criar máscara de recorte (⌘7)"}
            ],
            "row2": [
              {"id": "lock_selection", "title": "Bloquear", "iconName": "lock.fill", "key": "2", "modifiers": 1, "actionPayload": "lock_selection", "description": "Bloquear seleção (⌘2)"},
              {"id": "unlock_all", "title": "Desbloq Tudo", "iconName": "lock.open.fill", "key": "2", "modifiers": 5, "actionPayload": "unlock_all", "description": "Desbloquear tudo (⌘⌥2)"},
              {"id": "hide_selection", "title": "Ocultar", "iconName": "eye.slash.fill", "key": "3", "modifiers": 1, "actionPayload": "hide_selection", "description": "Ocultar seleção (⌘3)"},
              {"id": "show_all", "title": "Mostrar Tudo", "iconName": "eye.fill", "key": "3", "modifiers": 5, "actionPayload": "show_all", "description": "Mostrar tudo (⌘⌥3)"}
            ]
          }
        ]
      },
      {
        "id": "ai-screen-3",
        "title": "Tela 3: Curvas Bézier & Pathfinder",
        "iconName": "point.topleft.down.curvedto.point.bottomright.up",
        "recentColors": ["#000000", "#FFFFFF", "#FF9500", "#34C759"],
        "blocks": [
          {
            "id": "ai-bezier",
            "title": "Vetor & Bézier",
            "badge": "6 Ações",
            "row1": [
              {"id": "tool_pen", "title": "Caneta (P)", "iconName": "pencil.tip", "key": "p", "actionPayload": "pen", "description": "Caneta Bézier"},
              {"id": "direct_sel", "title": "Direta (A)", "iconName": "cursorarrow", "key": "a", "actionPayload": "direct_select", "description": "Seleção direta de pontos"},
              {"id": "add_pt", "title": "Ponto +", "iconName": "plus.circle", "actionPayload": "add_anchor", "description": "Adicionar âncora"}
            ],
            "row2": [
              {"id": "smooth_pt", "title": "Suave", "iconName": "waveform.path", "actionPayload": "convert_smooth", "description": "Converter para suave"},
              {"id": "corner_pt", "title": "Canto", "iconName": "angle", "actionPayload": "convert_corner", "description": "Converter para canto reto"},
              {"id": "join_path", "title": "Juntar (⌘J)", "iconName": "link", "key": "j", "modifiers": 1, "actionPayload": "join_paths", "description": "Juntar nós (⌘J)"}
            ]
          },
          {
            "id": "ai-path-v",
            "title": "Pathfinder Booleano",
            "badge": "6 Ações",
            "row1": [
              {"id": "path_unite", "title": "Unir", "iconName": "plus.square.fill", "actionPayload": "unite", "description": "Unir formas"},
              {"id": "path_minus", "title": "Subtrair", "iconName": "minus.square.fill", "actionPayload": "minus_front", "description": "Menos frente"},
              {"id": "path_intersect", "title": "Intersecção", "iconName": "circle.circle.fill", "actionPayload": "intersect", "description": "Intersecção"}
            ],
            "row2": [
              {"id": "path_exclude", "title": "Excluir", "iconName": "xmark.square.fill", "actionPayload": "exclude", "description": "Excluir sobreposição"},
              {"id": "path_divide", "title": "Dividir", "iconName": "square.split.2x2.fill", "actionPayload": "divide", "description": "Dividir faces"},
              {"id": "path_trim", "title": "Cortar", "iconName": "scissors", "actionPayload": "trim", "description": "Cortar sobreposição"}
            ]
          }
        ]
      }
    ]
  },
  {
    "id": "photoshop",
    "name": "Adobe Photoshop",
    "bundleId": "com.adobe.Photoshop",
    "iconName": "photo.artframe",
    "accentColorHex": "#31A8FF",
    "screens": [
      {
        "id": "ps-screen-1",
        "title": "Tela 1: Retoque, Camadas & IA",
        "iconName": "photo.stack",
        "recentColors": ["#000000", "#FFFFFF", "#31A8FF", "#FF9500"],
        "blocks": [
          {
            "id": "ps-retouch",
            "title": "Retoque & Frequências",
            "badge": "6 Ações",
            "row1": [
              {"id": "freq_sep", "title": "Freq. Auto", "iconName": "bolt.fill", "actionPayload": "frequency_separation", "colorHex": "#31A8FF", "description": "Separação de Frequências (Alta/Baixa)"},
              {"id": "dodge_burn", "title": "Dodge/Burn", "iconName": "circle.lefthalf.filled", "actionPayload": "dodge_burn", "description": "Dodge & Burn dinâmico"},
              {"id": "spot_heal", "title": "Cura (J)", "iconName": "bandage.fill", "key": "j", "actionPayload": "spot_healing", "description": "Pincel de Recuperação"}
            ],
            "row2": [
              {"id": "clone_stamp", "title": "Carimbo (S)", "iconName": "paintbrush.fill", "key": "s", "actionPayload": "clone_stamp", "description": "Carimbo de clone"},
              {"id": "select_sub", "title": "Assunto IA", "iconName": "person.crop.circle.badge.plus", "actionPayload": "select_subject", "colorHex": "#007AFF", "description": "Selecionar assunto com IA Sensei"},
              {"id": "remove_bg", "title": "Rem. Fundo", "iconName": "person.crop.rectangle.stack", "actionPayload": "remove_background", "colorHex": "#5856D6", "description": "Remover fundo com IA"}
            ]
          },
          {
            "id": "ps-layers",
            "title": "Controle de Camadas & Ajustes",
            "badge": "7 Ações",
            "row1": [
              {"id": "new_layer", "title": "Nova Camada", "iconName": "plus.rectangle.on.folder.fill", "key": "n", "modifiers": 3, "actionPayload": "new_layer"},
              {"id": "duplicate_layer", "title": "Duplicar", "iconName": "doc.on.doc.fill", "key": "j", "modifiers": 1, "actionPayload": "duplicate_layer"},
              {"id": "stamp_vis", "title": "Stamp (⇧⌥⌘E)", "iconName": "camera.fill", "actionPayload": "stamp_visible"}
            ],
            "row2": [
              {"id": "deselect", "title": "Deselecionar", "iconName": "xmark.rectangle", "key": "d", "modifiers": 1, "actionPayload": "deselect"},
              {"id": "curves", "title": "Curvas (⌘M)", "iconName": "chart.xyaxis.line", "key": "m", "modifiers": 1, "actionPayload": "curves"},
              {"id": "levels", "title": "Níveis (⌘L)", "iconName": "slider.horizontal.below.rectangle", "key": "l", "modifiers": 1, "actionPayload": "levels"},
              {"id": "camera_raw", "title": "Camera Raw", "iconName": "camera.viewfinder", "key": "a", "modifiers": 3, "actionPayload": "camera_raw"}
            ]
          }
        ]
      }
    ]
  },
  {
    "id": "system",
    "name": "Sistema macOS",
    "bundleId": "com.apple.finder",
    "iconName": "gearshape.2.fill",
    "accentColorHex": "#007AFF",
    "screens": [
      {
        "id": "sys-screen-1",
        "title": "Geral macOS & Mídia",
        "iconName": "desktopcomputer",
        "recentColors": [],
        "blocks": [
          {
            "id": "sys-media",
            "title": "Mídia e Áudio",
            "badge": "Controle",
            "row1": [
              {"id": "media_prev", "title": "Anterior", "iconName": "backward.fill", "actionPayload": "media_prev"},
              {"id": "media_play", "title": "Play/Pause", "iconName": "playpause.fill", "actionPayload": "media_play_pause"},
              {"id": "media_next", "title": "Próxima", "iconName": "forward.fill", "actionPayload": "media_next"}
            ],
            "row2": [
              {"id": "vol_down", "title": "Vol -", "iconName": "speaker.wave.1.fill", "actionPayload": "vol_down"},
              {"id": "vol_mute", "title": "Mudo", "iconName": "speaker.slash.fill", "actionPayload": "vol_mute"},
              {"id": "vol_up", "title": "Vol +", "iconName": "speaker.wave.3.fill", "actionPayload": "vol_up"},
              {"id": "screenshot", "title": "Captura", "iconName": "camera.viewfinder", "key": "4", "modifiers": 3, "actionPayload": "screenshot"}
            ]
          }
        ]
      }
    ]
  }
]
"""
