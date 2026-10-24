#!/bin/zsh
# 把 RMERouterApp 打包成 RMERouter.app（放在 .build/ 下，不进版本库）。
# 用法：scripts/make-app.sh [debug|release]，然后 open .build/RMERouter.app
set -euo pipefail
cd "$(dirname "$0")/.."
config="${1:-debug}"
swift build -c "$config" --product RMERouterApp
bin="$(swift build -c "$config" --show-bin-path)/RMERouterApp"
app=".build/RMERouter.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/RMERouter"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.rme.router</string>
    <key>CFBundleName</key><string>RME Router</string>
    <key>CFBundleDisplayName</key><string>RME Router</string>
    <key>CFBundleExecutable</key><string>RMERouter</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1 || true
echo "已生成 $app"
