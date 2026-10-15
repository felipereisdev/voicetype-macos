#!/usr/bin/env bash
#
# release.sh — build a Release VoiceType.app and pack it into a DMG.
#
# This script ships the AD-HOC path only (no Apple Developer Program
# enrollment required). Output is suitable for hand-distributing to a small
# number of beta testers; each tester needs to clear quarantine and grant
# TCC permissions manually — instructions are printed at the end.
#
# A signed + notarized path (Developer ID + xcrun notarytool) is documented
# in docs/follow-ups.md as FU-N2 and will be added the day there's an
# active Apple Developer Program enrollment.
#
# Usage:
#   ./macos/scripts/release.sh
#
# Pré-requisitos:
#   - Xcode 15.4+ instalado em /Applications/Xcode.app.
#   - create-dmg via Homebrew: brew install create-dmg
#
# Output:
#   dist/VoiceType-<version>-arm64.dmg

set -euo pipefail

# Always operate from repo root, regardless of invocation cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT"

PROJECT="macos/VoiceType.xcodeproj"
SCHEME="VoiceType"
CONFIGURATION="Release"
BUILD_DIR="macos/build/release"
ARCHIVE_PATH="$BUILD_DIR/VoiceType.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/VoiceType.app"
DIST_DIR="dist"
BUNDLE_ID="com.macsilva.VoiceType"

# --- Pre-flight ----------------------------------------------------------

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "ERROR: create-dmg not installed." >&2
  echo "       Install it with: brew install create-dmg" >&2
  exit 1
fi

if [[ ! -d /Applications/Xcode.app ]]; then
  echo "ERROR: /Applications/Xcode.app not found." >&2
  exit 1
fi

# Force the full Xcode toolchain (CommandLineTools lacks swift-testing,
# XCTest, and the archive action). See docs/gotchas.md G-003.
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

# --- Clean previous output ----------------------------------------------

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# --- 1. Archive Release build (ad-hoc signed) ---------------------------

echo "==> xcodebuild archive (this takes ~1-2 min)"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  -quiet

# --- 2. Pull the .app out of the archive --------------------------------

echo "==> extracting .app from archive"
mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/VoiceType.app" "$EXPORT_DIR/"

# --- 3. Re-sign ad-hoc with the bundle identifier ----------------------
#
# Without this, the binary signature ends up as `Identifier=VoiceType`
# (the executable name) instead of the bundle id. UNUserNotificationCenter
# rejects requestAuthorization when identifier != bundle id. See
# docs/gotchas.md G-002.

echo "==> ad-hoc re-sign with --identifier $BUNDLE_ID"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_PATH"

# --- 4. Read version ----------------------------------------------------

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0.0")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1")"

DMG_PATH="$DIST_DIR/VoiceType-${VERSION}-arm64.dmg"

# --- 5. DMG -------------------------------------------------------------

echo "==> create-dmg → $DMG_PATH"
rm -f "$DMG_PATH"
create-dmg \
  --volname "VoiceType" \
  --window-pos 200 120 \
  --window-size 540 380 \
  --icon-size 100 \
  --icon "VoiceType.app" 130 220 \
  --hide-extension "VoiceType.app" \
  --app-drop-link 410 220 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH" \
  >/dev/null

# --- Done ---------------------------------------------------------------

echo ""
echo "==================================================================="
echo "  DONE"
echo "  App:     $APP_PATH"
echo "  DMG:     $DMG_PATH"
echo "  Version: $VERSION (build $BUILD_NUMBER)"
echo "==================================================================="
echo ""
echo "Para os testers:"
echo ""
echo "  1) Baixar o DMG. Duplo-clique pra montar."
echo "  2) Arrastar VoiceType.app pra /Applications."
echo "  3) No terminal:"
echo ""
echo "       xattr -d com.apple.quarantine -r /Applications/VoiceType.app"
echo "       codesign --force --deep --sign - \\"
echo "         --identifier $BUNDLE_ID \\"
echo "         /Applications/VoiceType.app"
echo ""
echo "  4) Abrir VoiceType (Spotlight ou Finder). Permitir microfone quando perguntar."
echo "  5) System Settings → Privacy & Security → Accessibility → + →"
echo "     escolher /Applications/VoiceType.app → toggle ON."
echo "  6) pkill -f VoiceType && open /Applications/VoiceType.app  (re-poll TCC)"
echo "  7) Menu bar → Configurações → Geral → colar Groq API key (gsk_...)."
echo ""
echo "Pronto. Segurar Cmd+Shift+Space pra gravar."
