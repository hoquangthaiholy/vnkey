#!/bin/bash
# Đóng gói VNKey.app từ Swift Package (không cần Xcode, chỉ cần Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product VNKey
APP=build/VNKey.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Biểu tượng app: tạo lại bằng `swift Scripts/make-icon.swift` khi muốn đổi thiết kế.
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/VNKey "$APP/Contents/MacOS/VNKey"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.vnkey</string>
    <key>CFBundleName</key><string>VNKey</string>
    <key>CFBundleExecutable</key><string>VNKey</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
# Ký bằng chứng chỉ tự ký "VNKey Dev" nếu có: macOS nhận diện app theo người ký nên quyền Trợ năng
# được giữ qua các lần build. Không có thì ký ad-hoc (mỗi lần build phải cấp lại quyền).
IDENTITY="VNKey Dev"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "Không thấy chứng chỉ \"$IDENTITY\": ký ad-hoc."
    codesign --force --sign - "$APP"
fi
echo "Đã tạo $APP"
