# Nhật ký thay đổi (CHANGELOG)

## [1.0.1] - 2026-06-29
### Thêm mới
- Thêm tính năng nhận diện ngữ cảnh thông minh (Perceptron model) để tự động ưu tiên thứ tự xử lý ngôn ngữ dựa trên ứng dụng đang hoạt động và cấu trúc từ.
- Bổ sung xử lý thông báo khi hệ thống khởi động lại từ chế độ ngủ (system wake notification).

### Cải tiến & Sửa lỗi
- Cải thiện logic kiểm tra từ điển tiếng Anh và tối ưu hóa việc khôi phục phím.
- Đồng bộ hóa biểu tượng khay hệ thống (tray icon) chính xác hơn.
- Bỏ qua kiểm tra chính tả tiếng Việt đối với các từ khóa viết hoa hoàn toàn (ALL_CAPS) trong chế độ lập trình.
- Khắc phục lỗi trích xuất phím thứ hai từ dữ liệu gõ thô (`_rawTyping`).
- Tinh chỉnh giao diện: Loại bỏ cơ chế tự học sửa dấu (Exclusion list) để tối ưu hiệu năng và đơn giản hóa cài đặt, sắp xếp lại phần cấu hình nhận diện ngữ cảnh thông minh.

## [1.0.0] - 2026-06-26
### Thêm mới
- Phát hành phiên bản đầu tiên của ứng dụng VNKey đa nền tảng (macOS, Windows, Linux) sử dụng Tauri 2, Svelte 5 và Rust.
- Tích hợp engine gõ tiếng Việt C++ gọn nhẹ, hỗ trợ Telex và VNI.
- Hỗ trợ các bảng mã phổ biến: Unicode dựng sẵn, Unicode tổ hợp, VNI Windows, TCVN3 (ABC)...
- Tính năng gõ tắt (Macro) không giới hạn ký tự.
- Trình quản lý Clipboard (Bảng ghi nhớ) thông minh hỗ trợ lưu lịch sử sao chép văn bản và hình ảnh.
- Công cụ chuyển mã văn bản qua lại giữa các bảng mã.
- Tự động hóa: Nhớ bảng mã theo ứng dụng, chuyển chế độ gõ thông minh theo tiêu điểm cửa sổ.
- Sửa lỗi gạch chân khó chịu trên macOS bằng kỹ thuật Backspace.