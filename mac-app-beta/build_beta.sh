#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/MacTouchBarBeta.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
INSTALL_DIR="/Applications/MacTouchBarBeta.app"

echo "╔══════════════════════════════════════════════╗"
echo "║   MacTouchBar Studio Beta — Build & Install  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 1. Preparar estrutura do bundle ──────────────────
echo "📁 Preparando bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

cp -f "$DIR/Info.plist"   "$CONTENTS_DIR/Info.plist"
cp -f "$ROOT_DIR/index.html"      "$RESOURCES_DIR/index.html"
cp -f "$ROOT_DIR/app.js"          "$RESOURCES_DIR/app.js"
cp -f "$ROOT_DIR/style.css"        "$RESOURCES_DIR/style.css"
cp -f "$ROOT_DIR/tailwind.cdn.js" "$RESOURCES_DIR/tailwind.cdn.js"
[ -f "$ROOT_DIR/mac-companion-studio.html" ] && cp -f "$ROOT_DIR/mac-companion-studio.html" "$RESOURCES_DIR/mac-companion-studio.html"

if [ -f "$ROOT_DIR/mac-app/AppIcon.icns" ]; then
    cp -f "$ROOT_DIR/mac-app/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

[ -d "$ROOT_DIR/icons" ]          && cp -rf "$ROOT_DIR/icons"          "$RESOURCES_DIR/icons"
[ -d "$ROOT_DIR/fonts" ]          && cp -rf "$ROOT_DIR/fonts"          "$RESOURCES_DIR/fonts"
[ -f "$ROOT_DIR/wallpaper.jpg" ]  && cp -f  "$ROOT_DIR/wallpaper.jpg"  "$RESOURCES_DIR/wallpaper.jpg"
[ -d "$ROOT_DIR/ipados-preview" ] && cp -rf "$ROOT_DIR/ipados-preview" "$RESOURCES_DIR/ipados-preview"

# Copiar Sparkle.framework se existir
if [ -d "$DIR/Frameworks/Sparkle.framework" ]; then
    echo "✨ Copiando Sparkle.framework..."
    cp -Rf "$DIR/Frameworks/Sparkle.framework" "$FRAMEWORKS_DIR/"
fi

# ── 2. Compilar binário nativo ────────────────────────
export MACOSX_DEPLOYMENT_TARGET=13.0
echo "🔨 Compilando com clang Universal Binary (arm64 + x86_64, macOS 13.0+)..."
clang -fobjc-arc -O2 \
    -arch arm64 \
    -arch x86_64 \
    -mmacosx-version-min=13.0 \
    -F "$DIR/Frameworks" \
    -framework Cocoa \
    -framework WebKit \
    -framework Carbon \
    -framework UniformTypeIdentifiers \
    -framework Sparkle \
    -rpath @executable_path/../Frameworks \
    "$DIR/main.m" \
    -o "$MACOS_DIR/MacTouchBarBeta"

# ── 3. Assinar bundle e frameworks ───────────────────
echo "🔏 Assinando bundle..."
if [ -d "$FRAMEWORKS_DIR/Sparkle.framework" ]; then
    codesign --force --deep --sign - "$FRAMEWORKS_DIR/Sparkle.framework"
fi
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

