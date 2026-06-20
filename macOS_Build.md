# Build VNKey Tauri trên macOS

VNKey hiện dùng Tauri cho toàn bộ bảng điều khiển. Xcode project cũ trong
`Sources/VNKey/macOS` đã được loại bỏ để dọn dẹp mã nguồn.

## Yêu cầu

- Xcode Command Line Tools;
- Node.js và npm;
- Rust stable và Cargo.

## Build

Từ thư mục gốc:

```bash
./scripts/build_macos.sh [action]
```

Các tham số (actions) hỗ trợ:

- **`build`** (hoặc không truyền tham số): Chỉ build ra bundle `.app` tại:
  ```text
  Sources/src-tauri/target/release/bundle/macos/VNKey.app
  ```
- **`clean`**: Dọn dẹp toàn bộ các thư mục build tạm thời của cargo và frontend (`node_modules`, `.svelte-kit`, `build`).
- **`dmg`**: Build bundle `.app` và đóng gói thành tệp `.dmg` tại:
  ```text
  Sources/src-tauri/target/release/bundle/dmg/VNKey_1.0.0_aarch64.dmg
  ```
- **`install`**: Build bundle `.app`, đóng ứng dụng VNKey đang chạy (nếu có), thay thế ứng dụng cũ trong thư mục `/Applications/`, và mở ứng dụng mới.

## Chạy thử

```bash
open -g Sources/src-tauri/target/release/bundle/macos/VNKey.app
```

VNKey cần quyền Accessibility để event tap trên macOS bắt và gửi phím. Bundle
identifier được giữ là `com.theodore.vnkey` để tương thích với cấu hình quyền
của ứng dụng cũ.

DMG phát hành nên được tạo trong pipeline có Developer ID, hardened runtime và
notarization. Bundle local từ script sử dụng chữ ký ad-hoc dành cho phát triển.
