#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="FanControl.app"
APPBIN="$APP/Contents/MacOS"
TOOLCHAIN="/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
SDK="/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

echo "==> 编译 SMC helper (C)..."
"$TOOLCHAIN/clang" -isysroot "$SDK" -O2 -framework IOKit -framework CoreFoundation smc.c fanhelper.c -o fanhelper

echo "==> 编译菜单栏 app (Swift) — macOS 27 Liquid Glass..."
"$TOOLCHAIN/swiftc" -sdk "$SDK" -O -target arm64-apple-macosx27.0 -module-cache-path /tmp/swift-modcache-beta -num-threads 4 \
    DataSources.swift \
    TransparentPanel.swift RoundedPanelView.swift HeaderView.swift \
    SystemBarView.swift NetBarView.swift MetricBarView.swift \
    TempBarView.swift ChargeChartView.swift EfficiencyView.swift \
    BatteryBarView.swift FanSliderView.swift \
    main.swift \
    -o FanControl

echo "==> 组装 $APP ..."
rm -rf "$APP"
mkdir -p "$APPBIN"
mkdir -p "$APP/Contents/Resources"
cp FanControl "$APPBIN/FanControl"
cp -r fan_frames "$APP/Contents/Resources/fan_frames"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FanControl</string>
  <key>CFBundleDisplayName</key><string>风扇控制</string>
  <key>CFBundleIdentifier</key><string>local.fancontrol.glass</string>
  <key>CFBundleVersion</key><string>3.0</string>
  <key>CFBundleShortVersionString</key><string>3.0</string>
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

echo "==> 对 bundle 做 adhoc 代码签名..."
codesign --force --deep --sign - "$APP"

echo "==> 重新注册到 LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

echo ""
echo "==> 编译完成: $(pwd)/$APP"
echo ""

echo "==> 重启 $APP ..."
pkill -x FanControl 2>/dev/null || true
sleep 0.5
open "$(pwd)/$APP"
