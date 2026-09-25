#!/usr/bin/env bash
# Build a universal macOS app + DMG into dist/
# Optional signing + notarization when MAC_SIGN_IDENTITY is set.
# See CODE_SIGNING.md for env vars and Apple Developer setup.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP='dist/macos/TrueSync Connector.app'
ENTITLEMENTS='macos/TrueSync.entitlements'
DMG='dist/TrueSync-Connector-Mac.dmg'
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -parse-as-library \
    -target "$arch-apple-macos13.0" \
    -import-objc-header macos/Bridge.h \
    -framework SwiftUI -framework AppKit -framework PDFKit -framework Security \
    -lcups macos/TrueSync.swift \
    -o "dist/TrueSync-$arch"
done
lipo -create dist/TrueSync-arm64 dist/TrueSync-x86_64 -output "$APP/Contents/MacOS/TrueSyncConnector"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TrueSyncConnector</string>
<key>CFBundleIdentifier</key><string>app.truesync.connector</string>
<key>CFBundleName</key><string>TrueSync Connector</string>
<key>CFBundleDisplayName</key><string>TrueSync Connector</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.2</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>CFBundleIconFile</key><string>TrueSync.icns</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 SandHut and Nandakishore Gowda G</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
ICON_SRC=assets/icon.png
if [[ ! -f "$ICON_SRC" ]]; then
  echo "Missing $ICON_SRC" >&2
  exit 1
fi
sips -z 128 128 "$ICON_SRC" --out dist/mac-icon.png >/dev/null
python3 - <<'PY'
import struct
from pathlib import Path
png = Path('dist/mac-icon.png').read_bytes()
chunk = b'ic07' + struct.pack('>I', len(png) + 8) + png
Path('dist/macos/TrueSync Connector.app/Contents/Resources/TrueSync.icns').write_bytes(
    b'icns' + struct.pack('>I', len(chunk) + 8) + chunk
)
PY

sign_app() {
  local identity="$1"
  echo "Signing with identity: $identity (hardened runtime)"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$identity" \
    "$APP"
  codesign --verify --verbose=2 "$APP"
}

notarize_and_staple() {
  local submit_args=()
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "Notarizing with keychain profile: $NOTARY_PROFILE"
    submit_args=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "Notarizing with Apple ID credentials (prefer NOTARY_PROFILE for CI/local reuse)"
    submit_args=(
      --apple-id "$APPLE_ID"
      --team-id "$APPLE_TEAM_ID"
      --password "$APPLE_APP_SPECIFIC_PASSWORD"
    )
  else
    echo "WARNING: App is Developer ID–signed but notarization credentials are missing." >&2
    echo "  Set NOTARY_PROFILE (preferred) or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD." >&2
    echo "  Without notarization, Gatekeeper will still block first open on other Macs." >&2
    return 0
  fi
  xcrun notarytool submit "$DMG" "${submit_args[@]}" --wait
  xcrun stapler staple "$APP"
  xcrun stapler staple "$DMG"
  echo "Notarized and stapled: $APP and $DMG"
}

if [[ -n "${MAC_SIGN_IDENTITY:-}" ]]; then
  if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "Missing entitlements file: $ENTITLEMENTS" >&2
    exit 1
  fi
  sign_app "$MAC_SIGN_IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "WARNING: Ad-hoc codesign only (MAC_SIGN_IDENTITY unset)." >&2
  echo "  Gatekeeper will treat this as an unidentified developer." >&2
  echo "  Set MAC_SIGN_IDENTITY to a Developer ID Application identity, then notarize." >&2
  echo "  See CODE_SIGNING.md — Apple Developer Program (~\$99/year) is required." >&2
fi

cp macos/README.md "dist/macos/READ-ME.md"
ln -sfn /Applications dist/macos/Applications
trap 'rm -f dist/macos/Applications' EXIT
hdiutil create -volname 'TrueSync Connector' -srcfolder dist/macos -ov -format UDZO "$DMG"

if [[ -n "${MAC_SIGN_IDENTITY:-}" ]]; then
  # Re-sign the DMG payload is already signed; notarize the disk image.
  notarize_and_staple
fi

echo "Built $DMG"
