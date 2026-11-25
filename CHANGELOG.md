# Nhật ký thay đổi (CHANGELOG)

## [Chưa phát hành]
### Thêm mới
- **Bảng tạm (lịch sử clipboard)**: nhấn `⌃⌥V` để mở bảng ngay cạnh chỗ đang gõ; gõ để tìm (không cần dấu), `↩` để dán, `⌘1`…`⌘9` dán nhanh, `⌘P` ghim, `⌘⌫` xoá. Lưu 200 mục gần nhất gồm văn bản, đường dẫn, ảnh và tệp, chỉ trên máy. Văn bản chép từ Word, Pages, trình duyệt, Google Docs… giữ nguyên định dạng (RTF, RTFD, HTML) khi dán lại; `⇧↩` dán chữ trơn. Mỗi mục có thẻ nhỏ cho biết định dạng đang lưu (RTF, HTML…), và `⇥` › Markdown dịch định dạng đó thành cú pháp Markdown (`**đậm**`, liên kết, danh sách, bảng, khối mã). Mặc định tắt; bật ở Cài đặt › Bảng tạm. Nội dung mà trình quản lý mật khẩu đánh dấu riêng tư không được lưu.
- **Chuyển bảng mã ngay khi dán**: văn bản TCVN3 (ABC), VNI Windows hay VIQR được nhận ra và dán thành Unicode; `⌥↩` dán nguyên gốc. Phím `⇥` mở "Dán dạng": Unicode dựng sẵn, Unicode tổ hợp, TCVN3, VNI Windows, VIQR, hoặc không dấu.
- **Đồng bộ bảng tạm qua iCloud Drive** (tuỳ chọn, mặc định tắt): văn bản và đường dẫn đã sao chép hiện trên các máy Mac khác của bạn. Ảnh và tệp không đồng bộ. Nội dung nằm ở dạng đọc được trong thư mục VNKey của iCloud Drive.
- `vnkey-tool convert`: chuyển bảng mã từ dòng lệnh.
- **Soát lỗi thay cho tự sửa**: VNKey không còn tự thay chữ bạn gõ (chỉ còn tự trả lại từ tiếng Anh khi gõ xen kẽ). Từ nghi gõ sai được gạch chân đỏ ngay trong ô đang nhập, kể cả chữ dán vào: thiếu dấu (`viêt`, `đươc`), trật phím dấu sang phím bên (`veeg`), gõ đảo phím (`tieegns`), lỗi gõ bạn đã tự sửa hai lần (`goc`), cụm không dấu bạn hay gõ có dấu. Rê chuột lên chữ bị gạch, hoặc dùng `←` `→` đưa con trỏ vào từ đó, để mở bảng đề nghị; chọn bằng chuột hoặc `↑` `↓` `↩`; "Thêm vào từ điển" để từ đó không bị gạch nữa. Đề nghị xếp theo từ đứng cạnh (`tiếng viêt` → `việt`, `bài viêt` → `viết`) nhờ bảng khoảng 106.000 cặp âm tiết đếm trên phụ đề OpenSubtitles. Hiện chạy trong ứng dụng macOS chuẩn (TextEdit, Ghi chú, Mail); chưa chạy trên trang web và ứng dụng Electron.
- **Phân biệt gõ nhầm và sai chính tả**: gõ nhầm (thiếu dấu, trật phím) gạch đỏ; sai chính tả gạch cam, đề nghị theo các lỗi thường gặp: d/gi/r/v, s/x, ch/tr, l/n, n/ng, t/c, hỏi/ngã, iêu/ươu… (`dới` → `với`, `xắp` → `sắp`, `chời` → `trời`, `muổi` → `muỗi`).
- **Từ điển từ ghép** (khoảng 48.000 từ hai âm tiết, từ danh sách Viet74K của Hồ Ngọc Đức): từ hiếm nhưng có thật không còn bị gạch nhầm (`bánh chưng`), và bắt được lỗi chính tả trùng một âm tiết có thật (`bánh trưng` → `chưng`, `dữ gìn` → `giữ`).
- **Chuyển động**: nét gạch chân trượt ra lần lượt; bảng đề nghị và bảng tạm hiện ra mềm hơn và nhanh hơn; chữ vừa được thay (Đổi từ vừa gõ, chọn đề nghị, gõ tắt) có một dải sáng lướt qua; nét gạch ẩn khi cửa sổ đang được dời. Tôn trọng "Giảm chuyển động" của macOS.
- **Trợ lý cho câu và đoạn văn (✦)**: để chuột dừng trên một câu rồi đưa vào nút ✦ để mở bảng riêng: sửa chính tả, cải tiến, viết lại, làm ngắn gọn, mở rộng, dịch Việt ↔ Anh, viết thành câu từ vài ý; chọn phạm vi một câu hay cả đoạn; nút ↻ để thử bản khác. Dùng mô hình ngôn ngữ chạy trên máy của macOS 26 (cần Apple Intelligence), không có gì rời khỏi máy, và chỉ thay khi bạn chọn. Máy không có mô hình vẫn có việc thêm dấu và sửa chính tả cả câu, làm bằng dữ liệu của VNKey.
- **Soát cả tiếng Anh** (tuỳ chọn, mặc định tắt) bằng từ điển của macOS.
- **Gõ tắt thông minh**: gõ `\tên` rồi dấu cách để bung (`\homnay` ra ngày hôm nay, `\hoten` ra họ tên); bảng tên và nội dung sửa được, tự thêm mục của bạn. Nội dung của mọi gõ tắt dùng được biến `[ngay]`, `[gio]`, `[thu]`, `[thang]`, `[nam]`, `[ngaydai]`, `[homqua]`, `[ngaymai]`, `[ngay+7]`, `[tuan]`, `[amlich]`, `[hoten]`, `[clipboard]`.
- Gõ thừa một phím làm từ bị trả về phím gốc (`ddaayy`), xoá phím thừa đi rồi nhấn dấu cách thì từ được hiểu lại (`đây`).
- `vnkey-tool check`: soát lỗi một đoạn văn bản từ dòng lệnh.

### Sửa lỗi
- Gõ `Dd`, lỡ gõ một phím dấu (`j`) rồi xoá đi, gõ tiếp `ajt` ra "Đajt" thay vì "Đạt".
- Sau hai từ tiếng Anh liên tiếp, `cos` bị giữ nguyên thay vì ra "có" (và gõ lại vẫn sai). Từ tiếng Việt rất thông dụng nay luôn được ưu tiên.

### Thay đổi
- Bỏ các công tắc tự sửa (gõ đảo phím, từ thiếu dấu, phím dấu gõ trượt, nháy từ vừa sửa). Thẻ "Tự sửa" trong Cài đặt thành thẻ "Chính tả".
- Thẻ "Việt & Anh" thành thẻ "Ngôn ngữ" với hai nhóm có công tắc chính: Tiếng Anh (gõ xen kẽ, ngữ cảnh, code, chính tả tiếng Anh) và Ngôn ngữ GenZ (chữ teen, bung viết tắt). Tắt công tắc chính thì các tuỳ chọn trong nhóm mất tác dụng.
- Một công tắc "Ghi lại thói quen gõ" cho mọi việc học, và một bảng duy nhất cho mọi thứ VNKey đã nhớ (từ điển của bạn, từ giữ một dạng, lỗi gõ, cặp từ); chỉ xem và xoá.
- Phím Đổi từ vừa gõ chỉ còn đổi giữa phím gốc và tiếng Việt.
- **Cài đặt gọn hơn**: thẻ Đã nhớ nhập vào thẻ Chính tả.

## [2.0.0] - 2026-11-24
Bản viết lại hoàn toàn, **chỉ dành cho macOS** (12 trở lên), bằng Swift thuần. Bản 1.x đa nền tảng (Tauri, Rust,
Svelte) không còn được phát triển; mã nguồn và các bản phát hành cũ vẫn nằm trong lịch sử của kho.

### Thêm mới
- **Engine mới theo dõi thứ tự phím**: giữ nguyên chuỗi phím gốc của từng từ, nên luôn trả lại được đúng những gì đã gõ; phím dấu gõ lúc nào cũng được sau chữ nó bổ nghĩa (`dduwowcj`, `duojwcd` → `được`).
- **Gõ xen kẽ Việt – Anh**: tự trả lại từ không phải tiếng Việt (`user`, `string`, `data`), có tham khảo từ điển Việt/Anh của macOS và ngữ cảnh câu; giữ nguyên trong ngữ cảnh code (sau `@ # / . _`, chữ số).
- **Đoán từ gõ thiếu dấu**: `duojc`, `đươc` → `được`; chọn theo từ đứng trước (`tiếng viet` → `việt`, `bài viet` → `viết`). Chỉ thêm dấu, không thay từ đã đúng; nháy nhẹ từ vừa được sửa.
- **Học từ cách bạn gõ**: nhớ từ muốn giữ nguyên (phím Đổi từ vừa gõ `⌃⌥Z`, hoặc xoá rồi gõ lại), và đếm cặp từ hay gõ để sửa cả từ không dấu (`lầm loi` → `lầm lỗi`). Dữ liệu chỉ nằm trên máy, xem và xoá được trong Cài đặt.
- **Sửa gõ đảo hai phím liền nhau** (`tieegns` → `tiếng`).
- **Gõ tắt** dạng bảng có tìm kiếm; bộ viết tắt teen có sẵn (bật tuỳ ý).
- **Nhớ chế độ Việt/Anh theo ứng dụng**; danh sách ứng dụng bắt đầu ở chế độ Anh (mặc định là các terminal).
- **Tạm ngưng khi dùng bộ gõ khác của macOS** hoặc bàn phím không phải chữ Latin; biểu tượng mờ đi.
- **Nhãn chế độ cạnh con trỏ soạn thảo** (`VN - Telex`, `VN - VNI`, `EN`) khi đổi chế độ.
- Tuỳ chọn Telex: phím `w` đứng riêng thành `ư`, phím `[ ]` thành `ơ ư`; viết hoa đầu câu; xoá khoảng trắng thừa trước dấu câu.
- **Đoán cả cụm không dấu**: sau khi bạn gõ `lầm lỗi` vài lần, gõ `lam loi` cũng ra `lầm lỗi` (sửa luôn từ đứng trước).
- **Giao diện tiếng Việt và tiếng Anh**: chọn Theo hệ thống / Tiếng Việt / English ở Cài đặt › Chung.
- **Tự cập nhật**: VNKey kiểm tra bản mới trên GitHub Releases mỗi ngày; bấm "Cập nhật ngay" để nó tải, kiểm tra chữ ký (cùng nhà phát triển, do Apple cấp chứng chỉ), tự thay rồi mở lại.
- **Cửa sổ "Có gì mới"**: xem nhật ký thay đổi ngay trong app.
- Cửa sổ hướng dẫn cấp quyền Trợ năng; thẻ Giới thiệu có liên kết tới trang web và mã nguồn.
- Nhật ký gỡ lỗi mặc định tắt.
- Bản phát hành có hai gói: `universal` (Apple silicon và Intel) và `arm64` (chỉ Apple silicon, nhẹ hơn).

### Thay đổi so với 1.x
- Không còn bản Windows và Linux.
- Không còn Bảng ghi nhớ (clipboard), đồng bộ đám mây, công cụ chuyển mã và các bảng mã cũ (VNI Windows, TCVN3); chỉ xuất Unicode dựng sẵn.
- Xử lý riêng cho thanh địa chỉ trình duyệt và Spotlight để gợi ý tự điền không làm lặp chữ.

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