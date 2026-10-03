#!/usr/bin/env bash
# Assembles Agentville.app from the SwiftPM release products (docs/architecture/installation.md):
#   Contents/MacOS/Agentville            the menu bar app
#   Contents/Helpers/agentville-hook     the hook helper Claude Code runs (through the link, ADR 0007)
#   Contents/Info.plist                  LSUIElement (no Dock icon), minimum macOS 14 (ADR 0003)
# Hardened runtime, not sandboxed, no entitlements. Signed ad hoc until signing is decided (open
# question 3, M8). The version is the plugin's, so app and plugin always match.
#
# Usage: scripts/bundle-app.sh [--out dist]      → dist/Agentville.app
set -euo pipefail
cd "$(dirname "$0")/.."

out=dist
[[ "${1:-}" == "--out" ]] && out="$2"

version=$(plutil -extract version raw -o - Plugin/agentville/.claude-plugin/plugin.json)
bundle_id=io.github.dimural.agentville # open question 16
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)

scripts/swift.sh build -c release >/dev/null
bin=$(scripts/swift.sh build -c release --show-bin-path)

app="$out/Agentville.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$bin/Agentville" "$app/Contents/MacOS/Agentville"
cp "$bin/agentville-hook" "$app/Contents/Helpers/agentville-hook"
cp LICENSE "$app/Contents/Resources/LICENSE" 2>/dev/null || true

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>Agentville</string>
  <key>CFBundleDisplayName</key><string>Agentville</string>
  <key>CFBundleExecutable</key><string>Agentville</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© Dimural Murat. MIT licence.</string>
</dict>
</plist>
PLIST
plutil -lint "$app/Contents/Info.plist" >/dev/null

# Inside out: the helper first, then the app. Hardened runtime, no entitlements.
codesign --force --options runtime --timestamp=none --sign - "$app/Contents/Helpers/agentville-hook" 2>&1 | grep -v "replacing existing signature" || true
codesign --force --options runtime --timestamp=none --sign - "$app" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --strict "$app"

echo "bundle-app: $app ($version, build $build, $(du -sk "$app" | cut -f1) KB)"
