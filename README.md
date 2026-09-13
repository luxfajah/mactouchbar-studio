<div align="center">

<img src="docs/screenshots/icon.png" alt="MacTouchBar Studio" width="120" />

# MacTouchBar Studio

**Transforme seu iPhone ou iPad em uma Touch Bar para o Mac.**

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?logo=apple)](https://apple.com/macos)
[![Language](https://img.shields.io/badge/language-Objective--C%20%7C%20WebKit-orange)](https://developer.apple.com/documentation/objectivec)
[![Architecture](https://img.shields.io/badge/arch-Native%20Cocoa%20%2B%20WKWebView-blue)](https://developer.apple.com/documentation/webkit/wkwebview)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Status](https://img.shields.io/badge/status-Beta-orange)](https://github.com/luxfajah/mactouchbar-studio)

</div>

---

## ✨ O que é

O **MacTouchBar Studio** é um app nativo para macOS que permite usar um **iPhone ou iPad como Touch Bar**, enviando atalhos de teclado, ações e macros em tempo real para aplicativos como Illustrator, Photoshop, Figma e outros — via **Cabo USB (1.2ms)** ou **Wi-Fi**.

A interface foi construída com tecnologia híbrida: o **shell nativo é Objective-C puro (Cocoa + WebKit)**, e a UI interna é um motor HTML/CSS/JS de alta fidelidade que respeita as [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/).

---

## 📸 Screenshots

<div align="center">

### Tela Principal — Simulador Interativo
<img src="docs/screenshots/home.png" alt="Home — Simulador Interativo" width="800" />

### Tela de Conexão — USB & Wi-Fi
<img src="docs/screenshots/connection.png" alt="Conexão USB e Wi-Fi" width="800" />

### Perfil Illustrator — Cores & Tipografia
<img src="docs/screenshots/illustrator.png" alt="Perfil Illustrator" width="800" />

### Editor de Dock — Atalhos Personalizados
<img src="docs/screenshots/dock.png" alt="Editor de Dock" width="800" />

</div>

---

## 🏗 Arquitetura

O projeto é dividido em **quatro camadas** que se comunicam em tempo real:

```
┌─────────────────────────────────────────────────────────┐
│                     MacTouchBar Studio                  │
│  ┌───────────────────┐   ┌──────────────────────────┐   │
│  │   Native Shell    │   │      WebKit UI Engine    │   │
│  │  (Objective-C)    │◄──►    (HTML + CSS + JS)     │   │
│  │                   │   │                          │   │
│  │ • NSWindow        │   │ • NavigationSidebar      │   │
│  │ • WKWebView       │   │ • SimulatorView          │   │
│  │ • JS Bridge       │   │ • DockEditor             │   │
│  │ • Wallpaper Sync  │   │ • ProfileManager         │   │
│  │ • Appearance      │   │ • ExtensionsPanel        │   │
│  └────────┬──────────┘   └──────────────────────────┘   │
│           │ WebSocket (porta 9876)                       │
│  ┌────────▼──────────┐                                   │
│  │   Python Daemon   │   (mac-companion)                 │
│  │  mac_deck_server  │◄── Executa atalhos no macOS       │
│  └────────┬──────────┘                                   │
└───────────┼─────────────────────────────────────────────┘
            │ USB (ADB / usbmuxd) ou Wi-Fi WebSocket
┌───────────▼─────────────────────────────────────────────┐
│            App Android / iOS                            │
│  ┌─────────────────────────────────────────────────┐    │
│  │  TouchBar Display  (DeXPlay AirPlay / WebView)  │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### Diagrama de Componentes Detalhado

```mermaid
graph TB
    subgraph macOS["🖥 macOS App (Objective-C + WebKit)"]
        direction TB
        MAIN["main.m\nBetaAppDelegate\n• Janela nativa NSWindow\n• Traffic lights customizados\n• WindowDragView"]
        WEBVIEW["WKWebView\n• index.html carregado\n• drawsBackground = NO\n• JS Bridge via macNative"]
        BRIDGE["JS Bridge\n• getSystemInfo\n• closeWindow / zoom\n• syncWallpaper\n• checkTechnicalStatus\n• restartDaemon"]
        MAIN --> WEBVIEW
        WEBVIEW --> BRIDGE
    end

    subgraph UI["🎨 UI Engine (HTML / CSS / JS)"]
        direction TB
        NAV["NavigationSidebar\n• Início\n• Conexão\n• Dock\n• Telas\n• Extensões\n• Configurações"]
        SIM["SimulatorView\n• Renderiza TouchBar real\n• Telas por perfil\n• Arraste para reordenar"]
        DOCK["DockEditor\n• 1 ou 2 linhas\n• Importar / Exportar\n• Comunidade"]
        EXT["ExtensionsPanel\n• Illustrator\n• Photoshop\n• Figma\n• Custom"]
        NAV --> SIM
        NAV --> DOCK
        NAV --> EXT
    end

    subgraph DAEMON["⚙️ Python Daemon (mac-companion)"]
        WS["WebSocket Server\nporta :9876"]
        AX["Accessibility API\nAXUIElement"]
        HK["HotKey Engine\nCGEvent / AppleScript"]
        WS --> AX
        WS --> HK
    end

    subgraph DEVICE["📱 Dispositivo Remoto"]
        ANDROID["Android App\nDeXPlay AirPlay\n(APK)"]
        IOS["iOS / iPadOS\nWebView Client"]
    end

    BRIDGE <-->|"JS ↔ ObjC\npostMessage"| UI
    BRIDGE <-->|"WebSocket\n127.0.0.1:9876"| DAEMON
    DAEMON <-->|"USB 1.2ms\nou Wi-Fi"| DEVICE

    style macOS fill:#1a1a2e,stroke:#6c63ff,color:#fff
    style UI fill:#16213e,stroke:#0f3460,color:#fff
    style DAEMON fill:#0f3460,stroke:#533483,color:#fff
    style DEVICE fill:#533483,stroke:#6c63ff,color:#fff
```

---

## 📁 Estrutura do Projeto

```
MacTouchBar-Studio/
│
├── mac-app-beta/               # 🍎 App macOS (foco principal)
│   ├── main.m                  # Entry point: NSWindow + WKWebView + JS Bridge
│   ├── index.html              # UI completa (15k+ linhas, HTML/CSS/JS)
│   ├── Info.plist              # Bundle metadata
│   ├── build_beta.sh           # Build + Install automático em /Applications
│   ├── Views/                  # SwiftUI views (draft / referência)
│   │   ├── MainView.swift      # NavigationSplitView
│   │   ├── DashboardView.swift # Painel de métricas
│   │   ├── ProfileEditorView.swift
│   │   ├── ShortcutTesterView.swift
│   │   └── LogConsoleView.swift
│   └── Models/
│       ├── SystemMonitor.swift # Monitor de sistema nativo
│       └── AppProfile.swift    # Modelo de perfis de apps
│
├── mac-companion/              # ⚙️ Daemon Python WebSocket (:9876)
│   └── mac_deck_server.py      # Servidor de execução de atalhos
│
├── touchbar-hackintosh/        # 📱 App Android (Kotlin + ADB)
│   └── src/main/               # Interface Touch Bar no Android
│
├── ipados-preview/             # 🎭 Simulador iPadOS no browser
├── docs/
│   └── screenshots/            # 📸 Capturas de tela para o README
│
├── DeXPlay-AirPlay.apk         # APK compilado (Android)
├── build.gradle.kts            # Gradle config (Android)
└── README.md
```

---

## 🛠 Stack Técnica

| Camada | Tecnologia |
|---|---|
| **Shell nativo** | Objective-C • Cocoa • AppKit • Carbon |
| **UI Engine** | HTML5 • CSS3 • Vanilla JS • WebKit |
| **Bridge** | `WKScriptMessageHandler` (JS ↔ ObjC) |
| **Daemon** | Python 3 • WebSockets • asyncio |
| **Android Client** | Kotlin • Jetpack Compose • ADB |
| **Transporte** | USB (usbmuxd, ~1.2ms) • Wi-Fi WebSocket |
| **Appearance** | Apple HIG Dark Mode • `color-scheme` • `NSAppearance` |

---

## 🚀 Build & Instalação

### Pré-requisitos

- macOS 13 Ventura ou superior
- Xcode Command Line Tools: `xcode-select --install`
- Python 3.9+ (para o daemon)

### Compilar e Instalar

```bash
# Clonar o repositório
git clone git@github.com:luxfajah/mactouchbar-studio.git
cd mactouchbar-studio

# Build + install automático em /Applications
bash mac-app-beta/build_beta.sh
```

O script:
1. 📁 Monta o bundle `.app`
2. 🔨 Compila `main.m` com `clang` (Cocoa + WebKit + Carbon)
3. 🔏 Assina o bundle com identidade ad-hoc
4. 📦 Instala automaticamente em `/Applications/MacTouchBarBeta.app`

### Iniciar o Daemon

```bash
# Iniciar o servidor WebSocket Python
python3 mac-companion/mac_deck_server.py
# Ou usar o script de conveniência:
bash Iniciar-MacDeck-Server.command
```

---

## 🔌 Protocolo de Comunicação

```
iPhone/iPad → WebSocket → Daemon Python → macOS Accessibility API
                                       ↘ CGEvent (teclado/mouse)
                                       ↘ AppleScript
                                       ↘ NSDistributedNotificationCenter
```

Mensagens trocadas via WebSocket são JSON simples:

```json
{ "action": "shortcut", "key": "g", "modifiers": ["cmd"] }
{ "action": "align_center_artboard" }
{ "action": "switch_profile", "appBundleId": "com.adobe.illustrator" }
```

---

## 🎨 Design System

A UI segue as [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/):

- **Dark Mode nativo**: `color-scheme: dark light` + `NSAppearanceNameDarkAqua` no `NSWindow`
- **Scrollbars**: Overlay scrollbars nativos do macOS (sem CSS customizado), adaptam-se automaticamente ao tema
- **Cores**: CSS Custom Properties com `@media (prefers-color-scheme)` e fallback JS via `body.theme-dark/light`
- **Tipografia**: `-apple-system, SF Pro Text, SF Pro Display`
- **Janela**: `NSWindowStyleMaskFullSizeContentView` com titlebar transparente e traffic lights reposicionados

---

## 📄 Licença

MIT © 2026 [luxfajah](https://github.com/luxfajah)

---

<div align="center">
  <sub>Feito com ❤️ para criadores que vivem no Mac.</sub>
</div>
