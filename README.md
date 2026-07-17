# VNKey - Bộ gõ tiếng Việt đa nền tảng siêu nhẹ & hiệu năng cao

VNKey là một bộ gõ tiếng Việt thế hệ mới dành cho macOS, Windows và Linux. Dự án được lấy cảm hứng từ OpenKey nhưng được viết lại hoàn toàn bằng **Rust** cho Engine xử lý và **Tauri v2 (Vue 3 + Tailwind CSS v4)** cho Bảng điều khiển (Control Panel), hướng tới hiệu năng tối đa, độ trễ tối thiểu và giao diện hiện đại.

---

## ✨ Tính năng nổi bật

- **Tốc độ xử lý siêu việt**: Engine Rust xử lý hơn **914,000 từ/giây** (độ trễ **< 1.1 microgiây** cho mỗi phím gõ), nhẹ hơn và nhanh hơn đáng kể so với C++.
- **Kiểm tra chính tả thông minh**: Tự động nhận diện cấu trúc âm tiết tiếng Việt và các cụm nguyên âm để tránh bỏ dấu sai trên các từ tiếng Anh hoặc tên riêng (ví dụ: gõ `vietjet`, `zalo` không bị lỗi dấu).
- **Hỗ trợ 2 kiểu bỏ dấu**: Bỏ dấu kiểu mới (Hiện đại - ví dụ: `hoà`) và kiểu cũ (Cổ điển - ví dụ: `hòa`).
- **Giao diện kính mờ (Glassmorphism)**: Bảng điều khiển được thiết kế sang trọng, hỗ trợ chế độ Dark Mode tự động theo hệ thống.
- **Tích hợp System Tray**: Điều khiển nhanh các chế độ gõ ngay từ thanh Menu bar (macOS) hoặc Taskbar (Windows).

---

## 🛠️ Cấu trúc thư mục dự án

```
vnkey/
├── Cargo.toml                  # Cấu hình Cargo Workspace
├── README.md                   # Tài liệu hướng dẫn này
├── vnkey-engine/               # Thư viện xử lý âm tiết tiếng Việt (Pure Rust)
│   ├── src/
│   └── tests/                  # Bộ kiểm thử hiệu năng & độ chính xác
├── vnkey-daemon/               # Service chạy ngầm bắt phím toàn cục (Standalone)
│   └── src/
└── vnkey-ui/                   # Ứng dụng Tauri Control Panel & System Tray
    ├── src/                    # Giao diện Vue 3 + Tailwind CSS v4
    └── src-tauri/              # Backend Rust tích hợp Keyboard Hook ngầm
```

---

## 📋 Yêu cầu phần mềm trước khi cài đặt

Để biên dịch và phát triển VNKey, máy tính của bạn cần cài đặt sẵn:

1. **Rust & Cargo**: Cài đặt thông qua [Rustup](https://rustup.rs/).
2. **Node.js & npm** (v18 trở lên): Dành cho việc chạy và đóng gói giao diện Tauri.
3. **Thư viện hệ thống theo từng OS**:
   - **macOS**: Cần cấp quyền **Accessibility (Trợ năng)** cho ứng dụng để nhận sự kiện bàn phím toàn cục (`CGEventTap`). 
     *Lưu ý khi chạy ở chế độ phát triển (`npm run tauri dev`), do ứng dụng chưa được ký (unsign) và chạy thông qua Terminal, bạn cần cấp quyền Trợ năng cho ứng dụng **Terminal (hoặc Visual Studio Code)** đang chạy lệnh để bộ gõ có thể hoạt động.*
   - **Windows**: Không cần thư viện phụ trợ.
   - **Linux**: Cần các thư viện phát triển X11 và GTK:
     ```bash
     sudo apt install libx11-dev libxtst-dev libayatana-appindicator3-dev webkit2gtk-4.1
     ```

---

## 🚀 Hướng dẫn phát triển và biên dịch

### 1. Kiểm tra & Chạy thử nghiệm Engine
Để chạy bộ test chính tả và đo hiệu năng xử lý từ:
```bash
# Chạy các test case kiểm tra lỗi
cargo test -p vnkey-engine

# Chạy kiểm thử tốc độ ở chế độ tối ưu (Release Mode)
cargo test -p vnkey-engine --release -- --nocapture
```

### 2. Phát triển Giao diện Bảng điều khiển (Tauri UI)
Di chuyển vào thư mục giao diện và cài đặt các gói NPM cần thiết:
```bash
cd vnkey-ui
npm install
```

Khởi chạy ứng dụng ở chế độ Phát triển (Development Mode):
```bash
npm run tauri dev
```
*Lệnh này sẽ tự động khởi động máy chủ Vite chứa giao diện và biên dịch ứng dụng Tauri chạy song song.*

### 3. Đóng gói ứng dụng (Production Build)
Để đóng gói thành tệp cài đặt chính thức cho hệ điều hành của bạn (`.app` / `.dmg` trên macOS, `.exe` / `.msi` trên Windows, `.deb` / `.appimage` trên Linux):
```bash
cd vnkey-ui
npm run tauri build
```

---

## 🤝 Bản quyền & Đóng góp
Dự án được phát triển dưới giấy phép MIT. Mọi đóng góp về thuật toán xử lý âm tiết và tối ưu hóa hệ thống bàn phím luôn được chào đón.
