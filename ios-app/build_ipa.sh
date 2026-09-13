#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="MacTouchBarStudio"
IPA_NAME="MacTouchBarStudio.ipa"

echo "==> Preparando build do pacote iOS/iPadOS ($APP_NAME)..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Payload/$APP_NAME.app"

# Copia recursos e Info.plist
cp "$SCRIPT_DIR/Info.plist" "$BUILD_DIR/Payload/$APP_NAME.app/Info.plist"
mkdir -p "$BUILD_DIR/Payload/$APP_NAME.app/WebResources"
cp -R "$SCRIPT_DIR/WebResources/"* "$BUILD_DIR/Payload/$APP_NAME.app/WebResources/"
cp "$ROOT_DIR/app_icon.png" "$BUILD_DIR/Payload/$APP_NAME.app/AppIcon60x60@2x.png" 2>/dev/null || true

# Cria executável placeholder / launcher WebKit
cat << 'EOF' > "$BUILD_DIR/Payload/$APP_NAME.app/$APP_NAME"
#!/bin/sh
exec open "WebResources/index.html"
EOF
chmod +x "$BUILD_DIR/Payload/$APP_NAME.app/$APP_NAME"

# Empacota em .ipa (ZIP padrão iOS)
echo "==> Gerando $IPA_NAME..."
cd "$BUILD_DIR"
zip -qr "$ROOT_DIR/$IPA_NAME" Payload

echo "==> Pacote $IPA_NAME gerado com sucesso em: $ROOT_DIR/$IPA_NAME"
echo "==> Você pode instalar via AltStore, SideStore, TrollStore ou Sideloadly!"
