# MacTouchBar Studio

Transforme seu dispositivo Android, iPhone ou iPad em uma Touch Bar tátil e painel de atalhos contextuais para macOS.

![MacTouchBar Studio Preview](docs/screenshots/home.png)

MacTouchBar Studio é uma aplicação para macOS que permite utilizar smartphones e tablets (Android, iPhone e iPad) como uma superfície física de atalhos, automações e controles criativos. O app detecta automaticamente o programa em foco no Mac e adapta as ferramentas exibidas na tela do dispositivo em tempo real.

---

## Funcionalidades

- **Perfis contextuais automáticos**: Alterna os controles na tela conforme o app aberto no macOS (Adobe Illustrator, Photoshop, Figma, VS Code, Finder, etc.).
- **Conexão USB de baixa latência (~1.2ms)**: Comunicação direta via cabo USB para resposta instantânea ao toque, além de conexão sem fio via Wi-Fi local.
- **Suporte Multiplataforma**: Compatível com dispositivos Android (smartphones, tablets e Samsung DeX), iPhone e iPad.
- **Dock de atalhos customizável**: Permite criar e reorganizar grades de botões, disparadores de apps, scripts de sistema e macros.
- **Módulos para criativos (Add-ons)**:
  - **Illustrator**: Seletores de cor HSL/RGB, alinhamento magnético, ferramentas de vetor e ajustes tipográficos.
  - **Photoshop**: Retoque rápido, separação de frequência, opacidade, modos de mesclagem e máscaras.
  - **Figma & Edição**: Atalhos rápidos de componentes, frames e corte de timeline.
- **Controle por voz local**: Mapeamento de comandos falados para ações do macOS com processamento on-device via Apple Neural Engine.
- **Monitor de sistema**: Leitura em tempo real do uso de CPU, RAM, GPU e status de conexão.

---

## Screenshots

### Conexão e Pareamento (USB / Wi-Fi)
Configuração via cabo USB com baixa latência ou pareamento sem fio por QR Code para Android, iPhone e iPad.

![Conexão USB e Wi-Fi](docs/screenshots/connection.png)

### Editor de Dock
Personalização de atalhos, grade de 1 ou 2 linhas e organização de ícones.

![Editor de Dock](docs/screenshots/dock.png)

### Gerenciamento de Telas
Definição da ordem do carrossel e comportamento da alternância automática por aplicativo.

![Gerenciador de Telas](docs/screenshots/displays.png)

### Extensões (Add-ons)
Módulos instaláveis para suítes de criação e automação de fluxo de trabalho.

![Extensões](docs/screenshots/addons.png)

### Comandos de Voz
Painel de automação por voz com processamento acústico local e baixa sobrecarga.

![Comandos de Voz](docs/screenshots/voice.png)

---

## Instalação e Uso

### 1. macOS (Servidor / Host)

**Requisitos**: macOS 13 (Ventura) ou superior e Xcode Command Line Tools.

```bash
# Clone o repositório
git clone https://github.com/luxfajah/mactouchbar-studio.git
cd mactouchbar-studio

# Compile e instale em /Applications
chmod +x mac-app-beta/build_beta.sh
./mac-app-beta/build_beta.sh
```

> **Permissões necessárias**:  
> No primeiro uso, acesse **Ajustes do Sistema > Privacidade e Segurança > Acessibilidade** e ative o **MacTouchBar Studio** para permitir o envio de eventos de teclado e atalhos aos aplicativos.

---

### 2. Dispositivos Clientes

#### Android
1. Transfira o arquivo `TouchbarHackintosh.apk` (disponível na raiz do repositório) para o dispositivo.
2. Habilite a instalação de fontes desconhecidas caso solicitado.
3. Instale o APK e conecte via cabo USB ou Wi-Fi.

#### iPhone e iPad
1. Com o MacTouchBar Studio aberto no Mac, acesse a aba **Conexão**.
2. Aponte a câmera do iPhone ou iPad para o **QR Code** exibido na tela ou acesse o endereço IP local no Safari.
3. Toque em **Compartilhar > Adicionar à Tela de Início** para usar o aplicativo em tela cheia sem barras de navegação.

---

## Estrutura do Projeto

```
mactouchbar-studio/
├── mac-app-beta/            # Aplicação nativa macOS (Objective-C + WebKit)
│   ├── main.m               # Janela nativa, WKWebView e bridge JS/ObjC
│   ├── index.html           # Interface do usuário, dock e simulador
│   ├── Info.plist           # Configuração do bundle
│   └── build_beta.sh        # Script de compilação
├── TouchbarHackintosh.apk   # Cliente nativo Android
├── DeXPlay-AirPlay.apk      # Módulo complementar de receptor de tela
└── docs/screenshots/       # Imagens de demonstração
```

---

## Licença

Este projeto está sob a licença [MIT](LICENSE).
