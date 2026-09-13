<div align="center">

<img src="docs/screenshots/icon.png" alt="MacTouchBar Studio" width="120" />

# MacTouchBar Studio

**Transforme seu iPhone ou iPad em uma Touch Bar para o Mac.**

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?logo=apple)](https://apple.com/macos)
[![Android](https://img.shields.io/badge/client-Android%20APK-green?logo=android)](TouchbarHackintosh.apk)
[![Language](https://img.shields.io/badge/language-Objective--C%20%7C%20WebKit-orange)](https://developer.apple.com/documentation/objectivec)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Status](https://img.shields.io/badge/status-Beta-orange)](https://github.com/luxfajah/mactouchbar-studio)

</div>

---

## ✨ O que é

O **MacTouchBar Studio** é composto de dois componentes que funcionam juntos:

| Componente | Descrição |
|---|---|
| 🍎 **Mac App** (`mac-app-beta/`) | App nativo macOS — painel de controle, simulador e ponte de atalhos |
| 📱 **Android APK** (`TouchbarHackintosh.apk`) | App Android que exibe a Touch Bar no dispositivo em tempo real |

A comunicação acontece via **Cabo USB (~1.2ms)** ou **Wi-Fi WebSocket**, com o Mac app fazendo a ponte entre o dispositivo e os aplicativos do macOS (Illustrator, Photoshop, Figma, etc.).

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

```mermaid
graph LR
    subgraph MAC["🖥 Mac App (Objective-C + WebKit)"]
        NATIVE["Native Shell\nNSWindow + WKWebView"]
        BRIDGE["JS Bridge\nWKScriptMessageHandler"]
        UI["UI Engine\nHTML + CSS + JS"]
        NATIVE --> UI
        UI <--> BRIDGE
    end

    subgraph MACOS["⚙️ macOS"]
        AX["Accessibility API"]
        HOTKEY["CGEvent / HotKeys"]
    end

    subgraph DEVICE["📱 Android"]
        APK["TouchbarHackintosh.apk\nDisplay da Touch Bar"]
    end

    BRIDGE <-->|"WebSocket :9876"| MACOS
    MAC <-->|"USB 1.2ms\nou Wi-Fi"| DEVICE
```

### Como funciona

```
[Android/iOS]  ──USB/Wi-Fi──►  [Mac App]  ──WebSocket──►  [macOS API]
   Exibe a                      Recebe o                    Executa o
   Touch Bar                    comando                     atalho
```

1. O **APK Android** exibe a Touch Bar customizada na tela do dispositivo
2. Ao tocar em um botão, envia um comando via USB ou Wi-Fi para o Mac
3. O **Mac App** recebe via WebSocket (porta 9876) e executa o atalho
4. A Accessibility API do macOS injeta o evento no app em foco

---

## 📁 Estrutura

```
mactouchbar-studio/
│
├── mac-app-beta/               # 🍎 App macOS
│   ├── main.m                  # Entry point: NSWindow + WKWebView + JS Bridge
│   ├── index.html              # UI completa (HTML/CSS/JS)
│   ├── Info.plist              # Bundle metadata
│   ├── build_beta.sh           # Build + install automático em /Applications
│   ├── Views/                  # SwiftUI (referência)
│   └── Models/                 # SystemMonitor, AppProfile
│
├── TouchbarHackintosh.apk      # 📱 App Android (cliente Touch Bar)
│
└── docs/
    └── screenshots/            # 📸 Capturas de tela
```

---

## 🛠 Tech Stack

| Camada | Tecnologia |
|---|---|
| **Mac — Shell nativo** | Objective-C · Cocoa · AppKit · Carbon |
| **Mac — UI Engine** | HTML5 · CSS3 · JS · WebKit |
| **Mac — Bridge** | `WKScriptMessageHandler` (JS ↔ ObjC) |
| **Android Client** | APK instalável (sideload) |
| **Transporte** | USB `~1.2ms` · Wi-Fi WebSocket |
| **Appearance** | Apple HIG · `NSAppearance` · `color-scheme` |

---

## 🚀 Instalação

### Mac App

**Pré-requisito:** Xcode Command Line Tools  
```bash
xcode-select --install
```

```bash
# Clonar o repositório
git clone git@github.com:luxfajah/mactouchbar-studio.git
cd mactouchbar-studio

# Compilar e instalar em /Applications automaticamente
bash mac-app-beta/build_beta.sh
```

### Android APK

1. Transfira `TouchbarHackintosh.apk` para o Android
2. Habilite **"Instalar apps desconhecidos"** nas configurações
3. Abra o APK e instale
4. Conecte via USB ou Wi-Fi ao Mac App

---

## 📄 Licença

MIT © 2026 [luxfajah](https://github.com/luxfajah)

---

<div align="center">
  <sub>Feito com ❤️ para criadores que vivem no Mac.</sub>
</div>
