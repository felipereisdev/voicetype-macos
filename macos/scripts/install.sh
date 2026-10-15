#!/usr/bin/env bash
#
# install.sh — build Release and install /Applications/VoiceType.app signed
# with a stable local identity, so TCC grants (Accessibility, Microphone)
# survive reinstalls. See docs/gotchas.md G-002 / G-033 and ADR-011.
#
# Ad-hoc signing (`--sign -`) yields a designated requirement of
# `cdhash H"..."`, which changes every build → TCC stops matching. A
# self-signed cert yields `identifier ... and certificate leaf = H"..."`,
# stable across builds.
#
# Usage: ./macos/scripts/install.sh
# Override identity: VOICETYPE_SIGN_IDENTITY="My Cert" ./macos/scripts/install.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IDENTITY="${VOICETYPE_SIGN_IDENTITY:-VoiceType Local}"
BUNDLE_ID="com.macsilva.VoiceType"
DEST="/Applications/VoiceType.app"
DERIVED="$REPO_ROOT/build/install-dd"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  cat >&2 <<EOF
ERROR: code-signing identity "$IDENTITY" not found in the keychain.

Create a self-signed one (once):
  Keychain Access → Certificate Assistant → Create a Certificate…
    Name: $IDENTITY · Identity Type: Self Signed Root · Certificate Type: Code Signing

or via OpenSSL 3 (brew install openssl@3; -legacy so 'security import' can read the .p12):
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$IDENTITY" \\
    -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature" \\
    -keyout key.pem -out cert.pem
  openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem -out id.p12 -passout pass:tmp
  security import id.p12 -k ~/Library/Keychains/login.keychain-db -P tmp -T /usr/bin/codesign
  rm key.pem cert.pem id.p12

The cert does not need to be trusted; codesign only needs the private key.
EOF
  exit 1
fi

echo "==> xcodebuild Release"
xcodebuild -project "$REPO_ROOT/macos/VoiceType.xcodeproj" -scheme VoiceType \
  -configuration Release -derivedDataPath "$DERIVED" -quiet build
BUILT="$DERIVED/Build/Products/Release/VoiceType.app"

echo "==> quitting running VoiceType"
osascript -e 'quit app id "'"$BUNDLE_ID"'"' 2>/dev/null || true
pkill -x VoiceType 2>/dev/null || true

echo "==> installing to $DEST"
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# No --options runtime: the self-signed cert has no Team ID, and the shipped
# binary has always run without hardened runtime (mic + CGEventTap work).
echo "==> signing with \"$IDENTITY\""
codesign --force --deep --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$DEST"

DR="$(codesign -d -r- "$DEST" 2>&1 | grep 'designated =>')"
echo "    $DR"
if [[ "$DR" == *cdhash* ]]; then
  echo "ERROR: designated requirement is cdhash-based; TCC grants will not survive the next install." >&2
  exit 1
fi

open "$DEST"
echo "==> done. First run with this identity: grant Accessibility/Microphone once more; later installs keep them."
