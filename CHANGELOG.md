# Nhật ký thay đổi (CHANGELOG)

## [1.1.0] - 2026-07-08
### Thêm mới
- **Thư mục dữ liệu ứng dụng mới**: Chuẩn hóa dữ liệu cục bộ về `~/Library/Application Support/VNKey` trên macOS và dùng cơ sở dữ liệu `data.db`.
- **Migration dữ liệu tự động**: Tự chuyển dữ liệu từ thư mục cũ `~/Library/Application Support/com.hoquangthaiholy.vnkey`, bao gồm cơ sở dữ liệu, thiết lập, cấu hình theo ứng dụng, clipboard và ảnh clipboard.
- **Từ điển ưu tiên**: Thay thế các mục từ điển cũ bằng một danh sách ưu tiên thống nhất, dùng chung cho từ tiếng Anh, từ lập trình và các từ dễ bị gõ nhầm dấu.

### Cải tiến & Sửa lỗi
- **Sửa đặt dấu hiện đại/cũ**: Tùy chọn gõ dấu kiểu mới nay áp dụng đúng quy ước kiểu cũ `xóa/hòa/khỏe` và kiểu mới `xoá/hoà/khoẻ`.
- **Cải thiện gõ nhanh**: Sửa các tùy chọn gõ nhanh phụ âm đầu, phụ âm cuối và gõ phụ âm bằng phím đúp.
- **Cải thiện khôi phục từ**: Tăng độ ổn định khi khôi phục từ tiếng Anh, từ lập trình, đường dẫn, tên file và các từ có phím dấu lặp.
- **Sửa lỗi gõ đúp dấu bị lặp ký tự**: Khắc phục lỗi hủy dấu Telex/VNI gửi trùng phím dấu thứ hai, ví dụ `taxx` nay cho đúng `tax` thay vì `taxx` hoặc làm lệch trạng thái khôi phục từ.
- **Ổn định trạng thái raw-key khi hủy dấu**: Giữ đúng lịch sử phím gốc sau khi gõ đúp dấu để các từ như `password`, `coffee`, `issue`, `tesst` tiếp tục được khôi phục thông minh ở cuối từ.
- **Sửa vòng lặp focus/top-app trên macOS**: VNKey không còn tự áp cấu hình theo ứng dụng khi chính VNKey là frontmost app, tránh tình trạng bảng điều khiển giành focus khỏi vùng nhập liệu của ứng dụng khác.
- **Giảm đứng UI khi mở bảng điều khiển**: Bỏ reload settings nặng mỗi lần cửa sổ chính nhận focus và không cưỡng ép focus panel trong luồng cấp lại Accessibility, giúp giảm hiện tượng bảng điều khiển đứng hình ngắn lúc khởi động/lấy lại quyền.
- **Tối ưu độ mượt khi gõ**: Giảm nhánh xử lý thừa trong engine và bổ sung kiểm thử hồi quy cho các ca Telex/VNI quan trọng.
- **Dọn giao diện bảng điều khiển**: Làm gọn bố cục, đổi tên các mục cài đặt theo cơ chế mới và loại bỏ các chức năng/copy không còn dùng.
- **Loại bỏ donation**: Xóa phần ủng hộ khỏi README, website và tài nguyên liên quan.

## [1.0.2] - 2026-07-05
### Thêm mới
- **Cơ chế hủy dấu Telex/VNI thông minh**: Cho phép gõ đúp phím dấu để hủy dấu tiếng Việt và giữ lại ký tự gốc (ví dụ: gõ `as` + `s` -> `ass`, `oo` -> `oo` thay vì `ô`...). Giúp cải thiện trải nghiệm gõ các từ tiếng Anh chứa ký tự lặp hoặc chữ có chứa phím trùng dấu (như `password`, `coffee`, `issue`).

### Cải tiến & Sửa lỗi
- **Tối ưu hóa độ trễ phản hồi phím**: Giảm đáng kể độ trễ gõ phím trên macOS bằng cách chỉ áp dụng độ trễ điều phối (3ms) trên các ứng dụng thực sự cần thiết (các trình duyệt Chromium, ứng dụng gốc của Apple...), tăng tốc độ phản hồi phím cho phần lớn các ứng dụng khác.
- **Khắc phục lỗi ký tự rác (stale character)**: Sửa lỗi hiển thị thừa ký tự khi khôi phục các từ tiếng Anh chứa ký tự dấu lặp lại không liền kề kết hợp với ký tự biến âm (ví dụ: gõ `forward`, `toward`, `award` bị lỗi hiển thị thừa chữ).
- **Cải thiện quản lý tiến trình (Single Instance) trên macOS**: Sử dụng kỹ thuật khóa tệp tin khuyên nghị (advisory file lock) để ngăn chặn chạy song song nhiều tiến trình ứng dụng (khi chạy từ terminal, `tauri dev` hoặc file chạy trực tiếp), tránh xung đột bộ bắt sự kiện phím (CGEventTap) và nhân đôi biểu tượng thanh trạng thái.
- **Tối ưu hóa khởi động cùng hệ thống**: Đăng ký dịch vụ khởi động cùng hệ thống trên macOS thông qua lệnh `launchctl bootstrap` ngay sau khi tạo tệp cấu hình `.plist`.
- **Cải tiến giao diện người dùng (UI)**: Cập nhật các biến màu sắc, tinh chỉnh thiết kế cửa sổ và tích hợp trình quản lý tab cùng bộ phân tích cú pháp nhật ký thay đổi (Release Notes) hiển thị trực tiếp trong ứng dụng.
- **Dọn dẹp tài nguyên**: Loại bỏ các biểu tượng cũ và tối ưu hóa tài nguyên hình ảnh dự án bằng cách chuyển đổi sang định dạng đóng gói `.icns` tiêu chuẩn.

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
