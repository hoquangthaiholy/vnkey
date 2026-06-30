# Bảng điều khiển VNKey (Control Panel)

Bảng điều khiển VNKey được phát triển bằng Tauri 2, Svelte 5, TypeScript, Rust và engine gõ tiếng Việt C++ dùng chung.

Phần giao diện Webview đảm nhận toàn bộ các màn hình cấu hình dành cho người dùng:
- Lựa chọn kiểu gõ và các quy tắc chính tả tiếng Việt;
- Quản lý từ viết tắt (macro);
- Công cụ chuyển mã văn bản / trang mã;
- Cấu hình tương thích cho từng ứng dụng;
- Quản lý trạng thái menu hệ thống (tray icon).

Việc bắt và xử lý sự kiện bàn phím cho từng nền tảng cụ thể được thực hiện qua các adapter native riêng. Trên macOS sử dụng `tauri_event_tap.mm`; Windows và Linux sử dụng các cơ chế hook tương ứng.

Chức năng **Smart Switch** (Theo dõi ứng dụng đang chạy để tự động áp dụng cấu hình/bảng mã tương ứng) được hỗ trợ đầy đủ trên cả ba nền tảng thông qua các module Backend viết bằng Rust:
- **macOS:** Sử dụng Workspace APIs thông qua Objective-C++ bridge (`macos_apps.mm`).
- **Windows:** Sử dụng Windows SDK APIs (`win_apps.rs` qua `EnumWindows` và trích xuất icon từ tệp `.exe`).
- **Linux:** Sử dụng `xprop` cho môi trường X11 và quét `/proc` cho môi trường Wayland (`linux_apps.rs`), tự động ánh xạ biểu tượng từ thư mục icon hệ thống.

---

## Hướng dẫn dành cho Nhà phát triển (Developer Guide)

### 1. Yêu cầu môi trường
Trước khi build ứng dụng, máy tính của bạn cần cài đặt:
* **Node.js** (Phiên bản 18 trở lên) và **npm**.
* **Rust stable** và công cụ quản lý package **Cargo**.
* **macOS:** Xcode Command Line Tools (`xcode-select --install`).
* **Windows:** Microsoft C++ Build Tools và WebView2 Runtime.
* **Linux:** Các thư viện phát triển của WebKitGTK và System Tray (theo hướng dẫn cài đặt của Tauri 2).

### 2. Chạy ứng dụng trong môi trường Development (Chế độ Dev)
Để chạy thử ứng dụng và debug giao diện theo thời gian thực:
1. Đảm bảo bạn đang ở trong thư mục `Sources`:
   ```bash
   cd Sources
   ```
2. Cài đặt các package phụ thuộc:
   ```bash
   npm install
   ```
3. Kiểm tra mã nguồn (tùy chọn):
   ```bash
   npm run check
   ```
4. Khởi chạy dự án ở chế độ phát triển:
   ```bash
   npm run tauri dev
   ```

### 3. Build ứng dụng phát hành (Release Build)
Bạn có thể chạy trực tiếp lệnh build của tauri trong thư mục `Sources`:
```bash
npm run tauri build
```

Hoặc sử dụng các script tiện ích ở thư mục `scripts/` (chạy từ thư mục gốc của dự án) để tự động hóa quá trình đóng gói và cài đặt:

* **Tự động nhận diện hệ điều hành và build:**
  ```bash
  ./scripts/build_all.sh
  ```

* **Build riêng cho macOS:**
  ```bash
  ./scripts/build_macos.sh [action]
  ```
  Các tham số `[action]` hỗ trợ:
  * `build` (mặc định): Build ra file bundle ứng dụng `VNKey.app` tại `Sources/src-tauri/target/release/bundle/macos/`.
  * `build-installer` (hoặc `dmg`): Đóng gói ứng dụng thành file `.dmg`.
  * `install`: Build ứng dụng, ghi đè ứng dụng cũ trong `/Applications` và chạy bản mới nhất ngay lập tức.
  * `clean`: Xóa các thư mục build tạm thời để giải phóng dung lượng.
  * `uninstall`: Gỡ cài đặt VNKey khỏi hệ thống.

* **Build riêng cho Windows (gọi từ Command Prompt / PowerShell):**
  ```cmd
  scripts\build_windows.bat
  ```

* **Build riêng cho Linux:**
  ```bash
  ./scripts/build_linux.sh
  ```
