#!/bin/bash
# 编译 定时锁屏.app（Apple 芯片 + Intel 通用）并打包成 .pkg
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BUILD=build
APP="$BUILD/root/定时锁屏.app"
PKG="$BUILD/定时锁屏-$VERSION.pkg"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/scripts"

echo "▸ 编译"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" Sources/*.swift -o "$BUILD/LockTimer-$arch"
done
lipo -create "$BUILD"/LockTimer-arm64 "$BUILD"/LockTimer-x86_64 -output "$APP/Contents/MacOS/LockTimer"

echo "▸ 资源"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/ui "$APP/Contents/Resources/"

echo "▸ 图标"
swift scripts/make_icon.swift "$BUILD/icon_1024.png"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ 签名（ad-hoc）"
codesign --force --deep --sign - "$APP"

echo "▸ 打包"
# 安装前先退出正在运行的旧版本
cat > "$BUILD/scripts/preinstall" <<'EOF'
#!/bin/sh
/usr/bin/pkill -x LockTimer || true
exit 0
EOF
chmod +x "$BUILD/scripts/preinstall"
# 固定安装到 /Applications，不去“追踪”别处的同名副本
pkgbuild --analyze --root "$BUILD/root" "$BUILD/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$BUILD/component.plist"
pkgbuild --root "$BUILD/root" --component-plist "$BUILD/component.plist" \
  --identifier local.cat.LockTimer --version "$VERSION" \
  --install-location /Applications --scripts "$BUILD/scripts" \
  "$BUILD/LockTimer-component.pkg" >/dev/null
productbuild --synthesize --package "$BUILD/LockTimer-component.pkg" "$BUILD/distribution.xml" >/dev/null
sed -i '' 's#<installer-gui-script minSpecVersion="[0-9]*">#&\n    <title>定时锁屏</title>#' "$BUILD/distribution.xml"
productbuild --distribution "$BUILD/distribution.xml" --package-path "$BUILD" "$PKG" >/dev/null

echo "✓ $PKG"
