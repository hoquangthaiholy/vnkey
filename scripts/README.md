# VNKey build scripts

Các script trong thư mục này build cùng một ứng dụng Tauri trên macOS,
Windows và Linux. Giao diện Svelte, backend Rust và engine C++ được đóng gói
chung; chỉ adapter bắt sự kiện bàn phím thay đổi theo hệ điều hành.

## Yêu cầu chung

- Node.js và npm;
- Rust stable và Cargo;
- toolchain native của hệ điều hành.

Từ thư mục gốc, chạy script tự nhận diện hệ điều hành:

```bash
./scripts/build_all.sh
```

Hoặc gọi trực tiếp:

```bash
./scripts/build_macos.sh
./scripts/build_linux.sh
```

Trên Windows:

```bat
scripts\build_windows.bat
```

Mỗi script thực hiện `npm ci`, kiểm tra Svelte/TypeScript, sau đó chạy
`tauri build`. Artifact được tạo trong:

```text
Sources/src-tauri/target/release/bundle/
```

## Phụ thuộc nền tảng

- macOS: Xcode Command Line Tools. VNKey cần quyền Accessibility để adapter
  event tap có thể bắt và gửi phím.
- Windows: Microsoft C++ Build Tools và WebView2.
- Linux: `build-essential` cùng các development package mà Tauri 2 yêu cầu
  cho WebKitGTK và system tray.

Hiện adapter nhập liệu hoàn chỉnh nằm ở
`Sources/src-tauri/src/tauri_event_tap.mm` cho macOS. Windows và Linux dùng
cùng control panel/engine API nhưng vẫn cần adapter hook bàn phím riêng để bộ
gõ hoạt động toàn hệ thống.
