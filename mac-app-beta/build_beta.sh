#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/MacTouchBarBeta.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INSTALL_DIR="/Applications/MacTouchBarBeta.app"

echo "╔══════════════════════════════════════════════╗"
echo "║   MacTouchBar Studio Beta — Build & Install  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 1. Preparar estrutura do bundle ──────────────────
echo "📁 Preparando bundle..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp -f "$DIR/Info.plist"   "$CONTENTS_DIR/Info.plist"
cp -f "$DIR/index.html"   "$RESOURCES_DIR/index.html"

if [ -f "$ROOT_DIR/mac-app/AppIcon.icns" ]; then
    cp -f "$ROOT_DIR/mac-app/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

[ -d "$ROOT_DIR/icons" ]          && cp -rf "$ROOT_DIR/icons"          "$RESOURCES_DIR/icons"
[ -d "$ROOT_DIR/fonts" ]          && cp -rf "$ROOT_DIR/fonts"          "$RESOURCES_DIR/fonts"
[ -f "$ROOT_DIR/wallpaper.jpg" ]  && cp -f  "$ROOT_DIR/wallpaper.jpg"  "$RESOURCES_DIR/wallpaper.jpg"
[ -d "$ROOT_DIR/ipados-preview" ] && cp -rf "$ROOT_DIR/ipados-preview" "$RESOURCES_DIR/ipados-preview"

# ── 2. Compilar binário nativo ────────────────────────
echo "🔨 Compilando com clang (Cocoa + WebKit + Carbon)..."
clang -fobjc-arc -O2 \
    -framework Cocoa \
    -framework WebKit \
    -framework Carbon \
    -framework UniformTypeIdentifiers \
    "$DIR/main.m" \
    -o "$MACOS_DIR/MacTouchBarBeta"

# ── 3. Assinar bundle ────────────────────────────────
echo "🔏 Assinando bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "✅ Build concluído: $APP_BUNDLE"

# ── 4. Instalar em /Applications (automático) ────────
echo ""
echo "📦 Instalando em /Applications..."
rm -rf "$INSTALL_DIR"
cp -Rf "$APP_BUNDLE" "$INSTALL_DIR"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  ✅ MacTouchBarBeta.app instalado com sucesso ║"
echo "║     /Applications/MacTouchBarBeta.app        ║"
echo "╚══════════════════════════════════════════════╝"

