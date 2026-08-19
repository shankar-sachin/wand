#!/bin/bash
# Installs the app icon from the master artwork in assets/.
#
# iOS rejects or blackens icons that carry an alpha channel, so transparency is flattened
# here rather than left to chance.
#
#   ./scripts/install_icon.sh [path-to-artwork]     (defaults to assets/logo.png)
set -euo pipefail

SRC="${1:-assets/logo.png}"
DEST="Wand/Resources/Assets.xcassets/AppIcon.appiconset/wand.png"

if [ ! -f "$SRC" ]; then
  echo "No artwork at $SRC — drop a square PNG (1024x1024 or larger) there first." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sips -z 1024 1024 "$SRC" --out "$TMP/sized.png" >/dev/null
# Round-tripping through JPEG is the reliable way to drop an alpha channel with sips.
sips -s format jpeg "$TMP/sized.png" --out "$TMP/flat.jpg" >/dev/null
sips -s format png "$TMP/flat.jpg" --out "$DEST" >/dev/null

# Point the icon set at the installed file (it ships empty so a fresh clone builds clean).
cat > "$(dirname "$DEST")/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "wand.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "Installed icon:"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$DEST" | tail -3
echo "-> $DEST"
echo
echo "Rebuild with: xcodegen generate && xcodebuild -project Wand.xcodeproj -scheme Wand -sdk iphonesimulator build"
