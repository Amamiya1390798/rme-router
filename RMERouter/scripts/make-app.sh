#!/bin/zsh
# 把 RMERouterApp 打包成 RMERouter.app（放在 .build/ 下，不进版本库）。
# 用法：scripts/make-app.sh [debug|release] [--install]
#   release   用优化构建（日常使用）
#   --install 复制到 ~/Applications（只影响你自己的“应用程序”文件夹，可直接从启动台打开）
# 之后：open .build/RMERouter.app
set -euo pipefail
cd "$(dirname "$0")/.."
config="debug"; install=0
for arg in "$@"; do
  case "$arg" in
    debug|release) config="$arg" ;;
    --install) install=1 ;;
    *) echo "未知参数：$arg"; exit 2 ;;
  esac
done
version="$(cat VERSION 2>/dev/null || echo 0.0.0)"
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

swift build -c "$config" --product RMERouterApp
bin="$(swift build -c "$config" --show-bin-path)/RMERouterApp"
app=".build/RMERouter.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/RMERouter"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# 设备页的面板图（RME 官方产品图，第 6.4 节）
[[ -d Resources/Panels ]] && cp -R Resources/Panels "$app/Contents/Resources/Panels"
# 二次元模式素材（CC BY-NC-SA 4.0：署名、非商用、相同方式共享，见 NOTICE.txt）
[[ -d Resources/Anime ]] && cp -R Resources/Anime "$app/Contents/Resources/Anime"
# 二次元模式 · Claude 看板娘（形象由 amamiya 提供）
[[ -d Resources/AnimeClaude ]] && cp -R Resources/AnimeClaude "$app/Contents/Resources/AnimeClaude"
# 光标角标：DeepSeek 鲸鱼尾巴（官方 MIT；社区版版权不明，个人自用，见 sources.json）
[[ -d Resources/Cursor ]] && cp -R Resources/Cursor "$app/Contents/Resources/Cursor"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.rme.router</string>
    <key>CFBundleName</key><string>RME Router</string>
    <key>CFBundleDisplayName</key><string>RME Router</string>
    <key>CFBundleExecutable</key><string>RMERouter</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$build</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>读取并控制同一网络或 USB 网络上的 RME 12Mic（HTTP 接口），以及本机的 TotalMix FX（OSC）。</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 amamiya (cly20041110@gmail.com). 二次元模式美术 CC BY-NC-SA 4.0（上善、ZipZipPipe、Small-tailqwq）</string>
</dict>
</plist>
PLIST
# 签名：默认临时签名（本机用）；发给别人时设 SIGN_ID 为钥匙串里的证书名，例如
#   SIGN_ID="Apple Development: …" scripts/make-app.sh release
if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --deep --options runtime --sign "$SIGN_ID" "$app"
  codesign --verify --strict "$app" && echo "已签名：$SIGN_ID"
else
  codesign --force --sign - "$app" >/dev/null 2>&1 || true
fi
echo "已生成 $app（$config，版本 $version，构建 $build）"

if (( install )); then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/RME Router.app"
  cp -R "$app" "$HOME/Applications/RME Router.app"
  echo "已安装到 ~/Applications/RME Router.app"
fi
