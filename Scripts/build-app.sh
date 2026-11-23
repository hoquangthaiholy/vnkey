#!/bin/bash
# Đóng gói VNKey.app từ Swift Package (không cần Xcode, chỉ cần Command Line Tools).
#
# Tuỳ chọn qua biến môi trường (để trống = bản phát triển trên máy):
#   VNKEY_VERSION        số phiên bản ghi vào app (mặc định bên dưới)
#   VNKEY_BUILD          số build (mặc định 1)
#   VNKEY_BUNDLE_ID      mã định danh (mặc định local.vnkey; bản phát hành dùng com.hoquangthaiholy.vnkey)
#   VNKEY_SIGN_IDENTITY  chứng chỉ ký (mặc định "VNKey Dev"; bản phát hành dùng "Developer ID Application: …")
#   VNKEY_UNIVERSAL=1    dựng cho cả Apple silicon lẫn Intel
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VNKEY_VERSION:-2.0.0}"
BUILD="${VNKEY_BUILD:-1}"
BUNDLE_ID="${VNKEY_BUNDLE_ID:-local.vnkey}"
IDENTITY="${VNKEY_SIGN_IDENTITY:-VNKey Dev}"

if [ "${VNKEY_UNIVERSAL:-}" = "1" ]; then
    swift build -c release --product VNKey --arch arm64 --arch x86_64
    BINARY=.build/apple/Products/Release/VNKey
else
    swift build -c release --product VNKey
    BINARY=.build/release/VNKey
fi

APP=build/VNKey.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Biểu tượng app: thay Resources/AppIcon.svg rồi chạy `swift Scripts/make-icon.swift`.
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BINARY" "$APP/Contents/MacOS/VNKey"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>VNKey</string>
    <key>CFBundleExecutable</key><string>VNKey</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Hồ Quang Thái</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# Ký. Trên máy phát triển dùng chứng chỉ tự ký "VNKey Dev": macOS nhận diện app theo người ký nên quyền Trợ
# năng được giữ qua các lần build. Không có chứng chỉ thì ký ad-hoc (mỗi lần build phải cấp lại quyền).
# Chứng chỉ "Developer ID" (bản phát hành) cần hardened runtime và dấu thời gian để công chứng được.
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    case "$IDENTITY" in
        "Developer ID"*) codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP" ;;
        *) codesign --force --sign "$IDENTITY" "$APP" ;;
    esac
else
    echo "Không thấy chứng chỉ \"$IDENTITY\": ký ad-hoc."
    codesign --force --sign - "$APP"
fi
echo "Đã tạo $APP (bản $VERSION)"
