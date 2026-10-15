#!/usr/bin/env bash
# Generates VoiceType.app's AppIcon iconset from a source SVG (or PNG).
#
# Usage:
#   macos/scripts/make-icons.sh                      # uses ../../voicetype-logo.svg
#   macos/scripts/make-icons.sh path/to/icon.svg
#   macos/scripts/make-icons.sh path/to/icon.png
#
# SVG is rasterized to 1024×1024 via qlmanage (built-in). PNG is taken as-is
# and resized with sips. All 10 macOS app-icon slots are written to
# macos/VoiceType/Resources/Assets.xcassets/AppIcon.appiconset/ plus a
# Contents.json that points at the new filenames.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ICONSET_DIR="${REPO_ROOT}/macos/VoiceType/Resources/Assets.xcassets/AppIcon.appiconset"

SOURCE="${1:-${REPO_ROOT}/voicetype-logo.svg}"
if [[ ! -f "${SOURCE}" ]]; then
    echo "make-icons.sh: source file not found: ${SOURCE}" >&2
    exit 1
fi

EXT="${SOURCE##*.}"
EXT_LOWER="$(echo "${EXT}" | tr '[:upper:]' '[:lower:]')"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

if [[ "${EXT_LOWER}" == "svg" ]]; then
    echo "Rasterizing SVG via qlmanage…"
    qlmanage -t -s 1024 -o "${TMP_DIR}" "${SOURCE}" >/dev/null 2>&1
    BASE="$(basename "${SOURCE}")"
    MASTER="${TMP_DIR}/${BASE}.png"
else
    echo "Using PNG source directly…"
    MASTER="${TMP_DIR}/master.png"
    sips -z 1024 1024 "${SOURCE}" --out "${MASTER}" >/dev/null
fi

if [[ ! -f "${MASTER}" ]]; then
    echo "make-icons.sh: rasterization failed (no master PNG at ${MASTER})" >&2
    exit 1
fi

# (basename-without-ext, pixel-size)
SLOTS=(
    "icon_16x16:16"
    "icon_16x16@2x:32"
    "icon_32x32:32"
    "icon_32x32@2x:64"
    "icon_128x128:128"
    "icon_128x128@2x:256"
    "icon_256x256:256"
    "icon_256x256@2x:512"
    "icon_512x512:512"
    "icon_512x512@2x:1024"
)

mkdir -p "${ICONSET_DIR}"
# Drop any stale PNGs first so a leftover file from an older run can't shadow
# the new set.
find "${ICONSET_DIR}" -maxdepth 1 -name "*.png" -delete

for slot in "${SLOTS[@]}"; do
    name="${slot%%:*}"
    size="${slot##*:}"
    sips -z "${size}" "${size}" "${MASTER}" --out "${ICONSET_DIR}/${name}.png" >/dev/null
done

cat > "${ICONSET_DIR}/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "make-icons.sh: wrote ${#SLOTS[@]} PNGs to ${ICONSET_DIR}"
