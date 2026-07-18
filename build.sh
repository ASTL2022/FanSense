#!/bin/bash
set -e
cd "$(dirname "$0")"

VERSION="1.2.0"
APP="FanSense.app"
APPBIN="$APP/Contents/MacOS"
XCODE_DIR=$(xcode-select -p)
if [ -d "$XCODE_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
    TOOLCHAIN="$XCODE_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
    SDK="$XCODE_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
else
    TOOLCHAIN="$XCODE_DIR/usr/bin"
    SDK="$XCODE_DIR/SDKs/MacOSX.sdk"
fi
[ -d "$TOOLCHAIN" ] || { echo "Xcode tools not found. Install Xcode or Command Line Tools."; exit 1; }

echo "==> 编译 SMC helper (C)..."
"$TOOLCHAIN/clang" -isysroot "$SDK" -O2 -framework IOKit -framework CoreFoundation smc.c nvme_smart.c fanhelper.c -o fanhelper

ARCH=$(uname -m)
echo "==> 编译 FanSense (Swift, $ARCH) ..."
"$TOOLCHAIN/swiftc" -sdk "$SDK" -O -target "$ARCH-apple-macosx15.0" -module-cache-path /tmp/swift-modcache-v2 \
    DataSources.swift \
    TransparentPanel.swift RoundedPanelView.swift HeaderView.swift \
    SystemBarView.swift NetBarView.swift MetricBarView.swift \
    TempBarView.swift ChargeChartView.swift EfficiencyView.swift \
    BatteryBarView.swift FanView.swift \
    main.swift \
    -o FanSense

echo "==> 组装 $APP ..."
rm -rf "$APP"
mkdir -p "$APPBIN" "$APP/Contents/Resources"
cp FanSense "$APPBIN/FanSense"
cp fanhelper "$APP/Contents/Resources/fanhelper"
cp -r fan_frames "$APP/Contents/Resources/fan_frames"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FanSense</string>
  <key>CFBundleDisplayName</key><string>FanSense</string>
  <key>CFBundleIdentifier</key><string>local.fansense</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>FanSense</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleSignature</key><string>????</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> 代码签名..."
codesign --force --deep --sign - "$APP"

echo "==> 打包 DMG (FanSense-${VERSION}.dmg) ..."
for v in /Volumes/FanSense*; do hdiutil detach "$v" 2>/dev/null || true; done
sleep 1
DMG_TMP="/tmp/fansense-build"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$APP" "$DMG_TMP/"
osascript -e "tell application \"Finder\" to make new alias file at (POSIX file \"$DMG_TMP\") to folder \"Applications\" of startup disk with properties {name:\"Applications\"}" > /dev/null 2>&1

DMG_NAME="FanSense-${VERSION}.dmg"
rm -f "$DMG_NAME" /tmp/fansense-rw.dmg
hdiutil create -size 8m -layout NONE -fs "Case-sensitive APFS" -volname FanSense -attach /tmp/fansense-rw.dmg > /dev/null 2>&1
sleep 1
ditto "$DMG_TMP/$APP"           "/Volumes/FanSense/$APP"
ditto "$DMG_TMP/Applications"    "/Volumes/FanSense/Applications"
osascript -e '
tell application "Finder"
    open disk "FanSense"
    delay 0.5
    set theWindow to container window of disk "FanSense"
    set bounds of theWindow to {200, 200, 660, 400}
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set current view of theWindow to icon view
    delay 0.3
    set position of item "FanSense.app" of theWindow to {110, 100}
    set position of item "Applications" of theWindow to {340, 100}
    delay 0.3
    close theWindow
    update disk "FanSense"
end tell
' 2>/dev/null
hdiutil detach /Volumes/FanSense > /dev/null 2>&1
sleep 1
hdiutil convert /tmp/fansense-rw.dmg -format UDZO -o "$DMG_NAME" > /dev/null 2>&1
rm -f /tmp/fansense-rw.dmg
rm -rf "$DMG_TMP"

echo "==> 编译完成: $(pwd)/$APP"
echo ""
echo "==> 重启 $APP ..."
pkill -x FanSense 2>/dev/null || true
sleep 0.5
open "$(pwd)/$APP"
