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
    <key>NSHumanReadableCopyright</key><string>RME Router（个人工作室工具）</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1 || true
echo "已生成 $app（$config，版本 $version，构建 $build）"

if (( install )); then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/RME Router.app"
  cp -R "$app" "$HOME/Applications/RME Router.app"
  echo "已安装到 ~/Applications/RME Router.app"
fi
