#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="FanControl.app"
APPBIN="$APP/Contents/MacOS"
TOOLCHAIN="/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
SDK="/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

echo "==> 编译 SMC helper (C)..."
"$TOOLCHAIN/clang" -isysroot "$SDK" -O2 -framework IOKit -framework CoreFoundation smc.c fanhelper.c -o fanhelper

echo "==> 编译 FanControl (Swift) ..."
"$TOOLCHAIN/swiftc" -sdk "$SDK" -O -target arm64-apple-macosx27.0 -module-cache-path /tmp/swift-modcache-v2 -num-threads 4 \
    DataSources.swift \
    TransparentPanel.swift RoundedPanelView.swift HeaderView.swift \
    SystemBarView.swift NetBarView.swift MetricBarView.swift \
    TempBarView.swift ChargeChartView.swift EfficiencyView.swift \
    BatteryBarView.swift FanSliderView.swift \
    main.swift \
    -o FanControl

echo "==> 组装 $APP ..."
rm -rf "$APP"
mkdir -p "$APPBIN" "$APP/Contents/Resources"
cp FanControl "$APPBIN/FanControl"
cp -r fan_frames "$APP/Contents/Resources/fan_frames"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FanControl</string>
  <key>CFBundleDisplayName</key><string>风扇控制</string>
  <key>CFBundleIdentifier</key><string>local.fancontrol.v2</string>
  <key>CFBundleVersion</key><string>4.0</string>
  <key>CFBundleShortVersionString</key><string>4.0</string>
  <key>CFBundleExecutable</key><string>FanControl</string>
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

echo "==> 编译完成: $(pwd)/$APP"
echo ""
echo "==> 重启 $APP ..."
pkill -x FanControl 2>/dev/null || true
sleep 0.5
open "$(pwd)/$APP"
