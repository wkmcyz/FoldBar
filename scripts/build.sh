#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/FoldBar.app"
swift build --package-path "$ROOT" --configuration release
BIN_DIR="$(swift build --package-path "$ROOT" --configuration release --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/AppIcon.iconset"
cp "$BIN_DIR/FoldBar" "$APP/Contents/MacOS/FoldBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/.build/AppIcon-1024.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/.build/AppIcon-1024.png" --out "$ROOT/.build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$ROOT/.build/AppIcon-1024.png" --out "$ROOT/.build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ROOT/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
# A stable development identity preserves TCC identity across rebuilds; ad-hoc signing pins each binary's hash.
# Only auto-select an unambiguous Apple Development identity. An explicit override can select another identity or '-'.
SIGNING_IDENTITY="${FOLDBAR_SIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | python3 -c 'import re,sys; ids=re.findall(r"\b([0-9A-F]{40})\s+\"Apple Development:", sys.stdin.read()); print(ids[0] if len(ids)==1 else "-")')"
fi
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
