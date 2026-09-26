#!/bin/bash
# بناء تطبيق «الماسح» من المصدر
# يتطلب: macOS 14+، أدوات Xcode، Rust (https://rustup.rs)
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/.build"
APP="$HOME/Applications/الماسح.app"
PIXMA_REPO="https://github.com/pdrgds/pixma-rs.git"
PIXMA_REF="b9be726b002a0c1720c9928f3012b505bdb5ad1c"   # إصدار مثبّت من pixma-rs

command -v swiftc >/dev/null || { echo "✗ أدوات Xcode غير مثبتة: xcode-select --install"; exit 1; }
command -v cargo  >/dev/null || { echo "✗ Rust غير مثبت: https://rustup.rs"; exit 1; }

mkdir -p "$BUILD"

# ── 1. محرك المسح (pixma-rs) ──
if [ ! -d "$BUILD/pixma-rs" ]; then
  echo "▸ جلب محرك المسح pixma-rs…"
  git clone "$PIXMA_REPO" "$BUILD/pixma-rs"
fi
( cd "$BUILD/pixma-rs" && git fetch -q origin && git checkout -q "$PIXMA_REF" )
echo "▸ بناء محرك المسح…"
( cd "$BUILD/pixma-rs" && cargo build --release -p pixma-cli )

# ── 2. الأيقونة ──
echo "▸ بناء الأيقونة…"
swiftc -O "$HERE/src/makeicon.swift" -o "$BUILD/makeicon"
rm -rf "$BUILD/Icon.iconset" && mkdir -p "$BUILD/Icon.iconset"
"$BUILD/makeicon" "$BUILD/Icon.iconset"
iconutil -c icns "$BUILD/Icon.iconset" -o "$BUILD/AppIcon.icns"

# ── 3. التطبيق ──
echo "▸ بناء التطبيق…"
ARCH="$(uname -m)"
swiftc -O -parse-as-library -target "${ARCH}-apple-macos14.0" \
  "$HERE/src/ScannerApp.swift" \
  "$HERE/src/Theme.swift" \
  "$HERE/src/YahyaSignature.swift" \
  "$HERE/src/PhotosPicker.swift" \
  "$HERE/src/Queue.swift" \
  "$HERE/src/Options.swift" \
  -o "$BUILD/Scanner" \
  -framework SwiftUI -framework AppKit -framework Vision \
  -framework Photos -framework Network

# ── 4. تجميع الحزمة ──
echo "▸ تجميع الحزمة…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/Scanner" "$APP/Contents/MacOS/Scanner"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$BUILD/pixma-rs/target/release/pixma" "$APP/Contents/Resources/pixma"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

codesign --force --deep -s - "$APP"

echo ""
echo "✓ تم البناء: $APP"
echo "  شغّله بـ: open \"$APP\""
echo "  واسمح بإذن «الشبكة المحلية» عند طلبه."
