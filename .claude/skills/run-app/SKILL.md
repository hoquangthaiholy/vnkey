---
name: run-app
description: Build, ký, chạy lại VNKey và kiểm tra nó đang hoạt động (quyền Trợ năng, event tap, nhật ký). Dùng khi người dùng bảo mở/chạy lại/khởi động lại ứng dụng, hoặc sau khi sửa mã trong Sources/VNKey.
---

# Chạy VNKey

```bash
./Scripts/run.sh            # build, thoát bản cũ, mở bản mới
./Scripts/run.sh --settings # kèm cửa sổ Cài đặt
```

Chỉ mở lại bản đã build (không build): `pkill -f "VNKey.app/Contents/MacOS/VNKey"; open build/VNKey.app`

## Kiểm tra sau khi mở

```bash
grep "====" ~/Library/Logs/VNKey.log | tail -1
```

- `AX trusted=true`: bộ gõ hoạt động.
- `AX trusted=false`: thanh menu hiện `VN ⚠︎`. Người dùng phải bật VNKey trong System Settings →
  Privacy & Security → Accessibility. Claude không tự làm được việc này.

## Chữ ký và quyền

`build-app.sh` ký bằng chứng chỉ tự ký "VNKey Dev" trong keychain đăng nhập. Nhờ vậy macOS nhận
diện app theo người ký + bundle ID `local.vnkey`, và quyền Trợ năng được giữ qua các lần build.

Nếu script in "ký ad-hoc" thì chứng chỉ đã mất: mỗi lần build người dùng sẽ phải xoá và thêm lại
quyền. Báo cho họ và hỏi trước khi tạo lại chứng chỉ (đó là thay đổi trong keychain của họ). Khi
tạo, dùng `/usr/bin/openssl` (LibreSSL); OpenSSL của Homebrew tạo tệp .p12 mà `security import`
không đọc được.

## Trạng thái trên thanh menu

`VN` / `EN` là chế độ hiện tại; `⚠︎` là chưa có quyền; `🔒` là một ứng dụng đang bật ô nhập bảo mật
nên bộ gõ không nhận được phím.

## Lưu ý

- Chạy hai bộ gõ cùng lúc (VNKey + OpenKey/Unikey/bộ gõ Telex của macOS) sẽ xử lý chồng lên nhau.
- Terminal và vài ứng dụng trong danh sách "bắt đầu ở chế độ Anh" tự chuyển sang `EN` khi được chọn.
