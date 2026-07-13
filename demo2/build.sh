#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="Demo2.app"
APPBIN="$APP/Contents/MacOS"
TOOLCHAIN="/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
SDK="/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

echo "==> 编译菜单栏 app — Demo2..."
"$TOOLCHAIN/swiftc" -sdk "$SDK" -O -target arm64-apple-macosx27.0 \
    -module-cache-path /tmp/swift-modcache-beta -num-threads 4 \
    Sources/Data/FanTypes.swift \
    Sources/Data/HelperBridge.swift \
    Sources/Data/SystemInfo.swift \
    Sources/Views/Cards.swift \
    Sources/App/AppController.swift \
    Sources/main.swift \
    -o Demo2

echo "==> 组装 $APP ..."
rm -rf "$APP"
mkdir -p "$APPBIN"
mkdir -p "$APP/Contents/Resources"
cp Demo2 "$APPBIN/Demo2"
cp ../AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Demo2</string>
  <key>CFBundleDisplayName</key><string>Demo2</string>
  <key>CFBundleIdentifier</key><string>local.demo2.glass</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>Demo2</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleSignature</key><string>????</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> 代码签名..."
codesign --force --deep --sign - "$APP"

echo ""
echo "==> 编译完成: $(pwd)/$APP"
echo ""
echo "==> 启动 $APP ..."
pkill -x Demo2 2>/dev/null || true
sleep 0.5
open "$(pwd)/$APP"
