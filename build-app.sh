#!/bin/zsh
# Compile OutilScan en mode release et l'emballe dans build/OutilScan.app.
# Usage : ./build-app.sh            → crée build/OutilScan.app
#         ./build-app.sh --install  → copie aussi l'app dans /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/OutilScan.app"
VERSION="1.0"

swift build -c release --product OutilScan
BIN="$(swift build -c release --product OutilScan --show-bin-path)/OutilScan"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OutilScan"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>OutilScan</string>
    <key>CFBundleDisplayName</key><string>OutilScan</string>
    <key>CFBundleIdentifier</key><string>be.adnmac.OutilScan</string>
    <key>CFBundleExecutable</key><string>OutilScan</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Signature ad hoc : suffisante pour un usage personnel sur ce Mac.
codesign --force --sign - "$APP"
echo "✔ Application créée : $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/OutilScan.app"
    cp -R "$APP" /Applications/
    echo "✔ Installée dans /Applications"
fi
