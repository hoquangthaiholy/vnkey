# [VNKey](https://hoquangthaiholy.github.io/vnkey/)
### [Download bản mới nhất](https://github.com/hoquangthaiholy/vnkey/releases)
[![GitHub release](https://img.shields.io/github/v/release/hoquangthaiholy/vnkey.svg)](https://github.com/hoquangthaiholy/vnkey/releases/latest)

### Bộ gõ tiếng Việt nguồn mở, gọn nhẹ và đa nền tảng (macOS, Windows, Linux)
VNKey là ứng dụng gõ tiếng Việt hiện đại được phát triển trên nền tảng **Tauri 2**, **Rust** và **Svelte 5**. Trên macOS, VNKey sử dụng kỹ thuật gửi phím `Backspace` thông minh giúp loại bỏ hoàn toàn lỗi gạch chân khó chịu của bộ gõ mặc định, mang lại trải nghiệm gõ mượt mà và an toàn tuyệt đối.

---

## Tính năng nổi bật:
* **Hỗ trợ kiểu gõ phổ biến:** Hỗ trợ kiểu gõ Telex và VNI.
* **Bảng mã phong phú:** Unicode dựng sẵn, Unicode tổ hợp, TCVN3 (ABC), VNI Windows, Vietnamese Locale CP 1258...
* **Kiểm tra chính tả tiếng Việt:** Phát hiện lỗi gõ sai quy tắc âm tiết để tự khôi phục phím hoặc dừng gõ dấu sai.
* **Từ điển ưu tiên:** Nhận diện từ tiếng Anh, từ lập trình và các từ dễ bị gõ nhầm dấu để giữ nguyên hoặc khôi phục thông minh.
* **Tối ưu hóa lập trình:** Tự bảo vệ từ khóa cú pháp, tên file, đường dẫn và các cấu trúc biến (`camelCase`, `snake_case`, `ALL_CAPS`).
* **Gõ tắt thông minh (Macro):** Quản lý từ viết tắt dễ dàng, không giới hạn độ dài ký tự thay thế, hỗ trợ tự động viết hoa (Auto Caps) và gõ tắt trong chế độ tiếng Anh.
* **Quản lý khay nhớ tạm (Clipboard Manager):** Lưu lịch sử sao chép (văn bản, hình ảnh, liên kết) và tìm kiếm/truy xuất nhanh bằng phím tắt, bảo mật an toàn cục bộ.
* **Công cụ chuyển mã:** Chuyển đổi nhanh qua lại giữa các bảng mã cũ sang Unicode, loại bỏ dấu tiếng Việt hoặc đổi chữ hoa/thường trực tiếp qua Clipboard.
* **Chuyển chế độ thông minh (Smart Switch):** Tự động ghi nhớ và chuyển đổi chế độ gõ Anh/Việt tương ứng khi thay đổi tiêu điểm cửa sổ ứng dụng.
* **Nhớ bảng mã theo ứng dụng:** Tự động chuyển đổi bảng mã phù hợp cho từng phần mềm (như tự chuyển sang VNI/TCVN3 khi vào Photoshop, AutoCAD).
* **Đồng bộ dữ liệu đám mây (Cloud Sync):** Đồng bộ cấu hình cài đặt, từ điển cá nhân, thư viện macro và clipboard giữa các thiết bị.
* **Tích hợp hệ thống:** Chạy cùng hệ điều hành (Autostart), hiển thị trạng thái gõ trên Tray Icon (hỗ trợ Gray icon cho Dark mode).
* **Khắc phục lỗi macOS:** Sử dụng kỹ thuật Backspace thông minh loại bỏ hoàn toàn lỗi gạch chân khó chịu trên macOS.

---

## Cài đặt

### Cài đặt thủ công
Tải bản VNKey mới nhất từ [GitHub Releases](https://github.com/hoquangthaiholy/vnkey/releases/latest), mở file `.dmg` (trên macOS) hoặc file cài đặt phù hợp với hệ điều hành của bạn, tiến hành kéo thả/cài đặt vào hệ thống.

<!--
### Cài đặt qua Homebrew (dành cho macOS)
Nếu bạn sử dụng Homebrew, có thể cài đặt nhanh bằng lệnh:
```bash
brew install --cask vnkey
```
Để cập nhật VNKey lên bản mới nhất:
```bash
brew upgrade --cask vnkey
```
-->

### Lưu ý cấp quyền Accessibility (macOS)
Để VNKey có thể bắt và gửi phím chính xác trên hệ thống macOS, bạn cần cấp quyền Accessibility (Trợ năng):
1. Vào *System Settings (Cài đặt hệ thống) -> Privacy & Security (Quyền riêng tư & Bảo mật) -> Accessibility (Trợ năng)*.
2. Bật kích hoạt cho `VNKey.app`.

---

## Hướng dẫn Chi tiết các Chức năng

### 1. Kiểm tra chính tả & Quy tắc ngôn ngữ

* **Kiểm tra chính tả tiếng Việt**: 
  * *Chi tiết:* Bộ lọc kiểm tra xem từ đang gõ có tuân thủ đúng quy tắc ngữ âm tiếng Việt hay không. Nếu phát hiện từ sai (ví dụ ghép âm sai quy tắc), bộ gõ sẽ tự động dừng xử lý dấu hoặc khôi phục phím gốc để từ không bị biến dạng.
  * *Sử dụng:* Luôn bật để duy trì tốc độ và độ chính xác khi gõ văn bản tiếng Việt.
* **Từ điển ưu tiên**:
  * *Chi tiết:* Bỏ qua hoặc khôi phục thông minh các từ tiếng Anh, từ lập trình, tên file và đường dẫn dễ bị chuyển nhầm sang tiếng Việt. Bạn có thể thêm các từ riêng vào danh sách ưu tiên trong bảng điều khiển.
* **Tự khôi phục khi sai chính tả**:
  * *Chi tiết:* Khi từ sau khi bỏ dấu không hợp lệ theo quy tắc tiếng Việt nhưng khớp với từ ưu tiên hoặc ngữ cảnh lập trình, VNKey tự trả về phím gốc để không làm biến dạng nội dung đang gõ.

### 2. Gõ tắt (Macro)

* **Cơ chế hoạt động**: Cho phép định nghĩa từ viết tắt để tự động thay thế bằng cụm từ hoặc đoạn văn bản dài nhanh chóng. VNKey hỗ trợ nhập đoạn văn bản thay thế dài nhiều dòng và không giới hạn số lượng ký tự.
* **Gõ tắt trong chế độ tiếng Anh**: Hỗ trợ bật/tắt khả năng sử dụng các từ viết tắt ngay cả khi bạn đang gõ ở chế độ tiếng Anh.
* **Tự động viết hoa (Auto Caps Macro)**: Tự động phân tích kiểu viết chữ hoa/thường của phím gõ tắt để chuyển đổi kết quả đầu ra tương ứng (ví dụ: gõ `vk` -> `vnkey`, gõ `Vk` -> `Vnkey`, gõ `VK` -> `VNKEY`).

### 3. Công cụ chuyển mã (Convert Tool)

* **Chi tiết**: Chuyển đổi định dạng bảng mã của một đoạn văn bản (như chuyển từ các bảng mã cũ VNI-Windows, TCVN3 sang Unicode hiện đại), loại bỏ dấu tiếng Việt hoặc đổi kiểu viết hoa/thường.
* **Sử dụng**: Sao chép văn bản cần xử lý -> sử dụng phím tắt chuyển mã nhanh (cấu hình trong cài đặt) -> Nhấn Dán (Paste) để hiển thị nội dung mới đã chuyển đổi từ bộ nhớ tạm.

### 4. Bảng ghi nhớ (Clipboard Manager)

* **Lịch sử sao chép**: Tự động lưu lịch sử các nội dung đã sao chép (bao gồm văn bản, hình ảnh và liên kết) giúp bạn dễ dàng tìm kiếm và tái sử dụng lại các thông tin cũ. Dữ liệu được mã hóa và lưu trữ cục bộ hoàn toàn trên máy của bạn để đảm bảo an toàn bảo mật tuyệt đối.
* **Sử dụng**: Bật tính năng trong cài đặt và cấu hình phím tắt mở nhanh (ví dụ: `Option + V` hoặc `Cmd + Shift + V`). Cửa sổ Clipboard sẽ hiển thị ngay bên cạnh con trỏ chuột để bạn tìm kiếm và chọn nhanh dòng nội dung cần dán.

### 5. Thiết lập theo từng ứng dụng (Application Settings)

* **Chuyển chế độ thông minh (Smart Switch)**: VNKey tự động ghi nhớ chế độ gõ (Anh hoặc Việt) trên từng cửa sổ ứng dụng đang chạy. Khi bạn chuyển đổi tiêu điểm làm việc (ví dụ từ trình soạn thảo mã nguồn sang cửa sổ chat), VNKey tự động thiết lập đúng chế độ gõ đã dùng trước đó cho ứng dụng đó.
* **Tự ghi nhớ bảng mã theo ứng dụng**: Ghi nhớ bảng mã tương ứng cho từng phần mềm. Rất thích hợp cho những ai thiết kế đồ họa (Photoshop) hay vẽ kỹ thuật (AutoCAD) cần làm việc với các font chữ thuộc bảng mã cũ (VNI, TCVN3). Khi bạn mở các phần mềm này, VNKey tự chuyển sang bảng mã cũ và tự động chuyển về Unicode khi bạn quay lại các ứng dụng khác.

### 6. Đồng bộ dữ liệu (Cloud Sync)

* **Chi tiết**: Giúp người dùng đồng bộ hóa cấu hình cài đặt chung, từ điển tiếng Việt/Anh cá nhân, thư viện macro và bảng ghi nhớ Clipboard giữa các thiết bị khác nhau thông qua kết nối đám mây an toàn, giúp bạn duy trì trải nghiệm gõ phím đồng nhất.

### 7. Hệ thống & Tương thích

* **Chạy cùng hệ thống (Autostart)**: Tự động chạy ngầm VNKey ngay khi bạn khởi động hệ điều hành để sẵn sàng gõ tiếng Việt mà không cần mở thủ công.
* **Hiển thị trên thanh menu hệ thống (Tray Icon)**: Giúp theo dõi nhanh chế độ gõ (V/E). Hỗ trợ tùy chọn biểu tượng màu xám (Gray icon) hài hòa với giao diện sáng/tối của hệ điều hành.
* **Tương thích quyền Trợ năng (Accessibility)**: Để có thể lắng nghe và xử lý phím hệ thống thông qua Event Tap, VNKey bắt buộc cần quyền Trợ năng trên macOS. Ứng dụng cam kết hoàn toàn chạy cục bộ và không thu thập bất kỳ dữ liệu cá nhân hay ký tự gõ phím nào của người dùng.

---

## Hướng dẫn dành cho Nhà phát triển (Developer Guide)

Hướng dẫn chuẩn bị môi trường lập trình, chạy ứng dụng ở chế độ phát triển (Development) và các lệnh đóng gói/build chi tiết cho macOS, Windows, Linux đã được chuyển sang tài liệu riêng. 

👉 Xem chi tiết tại: **[Hướng dẫn dành cho Nhà phát triển (Sources/README.md)](Sources/README.md)**.

## Tác giả & Đóng góp

* **Tác giả:** **Hồ Quang Thái** cùng sự đóng góp của cộng đồng mã nguồn mở.
* **Liên hệ & Hỗ trợ:** Mọi phản hồi, góp ý hoặc báo lỗi vui lòng tạo Issue trên GitHub hoặc gửi về email: [vnkey.dev@gmail.com](mailto:vnkey.dev@gmail.com).
