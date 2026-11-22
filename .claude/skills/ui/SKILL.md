---
name: ui
description: Sửa và cải thiện giao diện của VNKey — menu thanh trạng thái, cửa sổ Cài đặt, nhãn VN/EN cạnh con trỏ, biểu tượng, chuỗi hiển thị. Dùng khi người dùng muốn đổi bố cục, thêm tuỳ chọn, làm giao diện đẹp hơn hoặc báo giao diện bị lệch.
---

# Giao diện VNKey

## Ràng buộc

- **AppKit thuần, không SwiftUI.** Thiếu plugin `SwiftUIMacros` trong Command Line Tools nên
  `@State`, `@AppStorage` không biên dịch được. Đừng thử lại trừ khi người dùng đã cài Xcode.
- **Xem giao diện bằng chế độ chụp của app**, không phải `screencapture` (bị từ chối vì thiếu quyền
  Screen Recording). Xem mục "Xem thử". Giới hạn: chỉ đáng tin ở chế độ sáng, không chụp được menu thanh
  trạng thái lẫn nhãn HUD, và không thấy được hành vi (bấm, kéo, ghi phím tắt). Những thứ đó vẫn phải
  nhờ người dùng xem; nói rõ phần nào đã tự xem, phần nào chưa.
- Chuỗi hiển thị bằng tiếng Việt, ngắn, nói điều người dùng nhận được chứ không nói cơ chế.

## Bản đồ

| Thành phần | Tệp | Ghi chú |
|---|---|---|
| Biểu tượng thanh menu | `Sources/VNKey/StatusIcon.swift` | Ô bo góc tô đặc ở CẢ HAI chế độ, chữ V/E khoét rỗng, canh giữa theo khung bao của nét chữ |
| Menu thanh trạng thái | `Sources/VNKey/main.swift` (`menuNeedsUpdate`) | Chỉ có: cảnh báo (nếu có), Gõ tiếng Việt, Bảng gõ, Cài đặt…, Thoát |
| Cửa sổ Cài đặt | `Sources/VNKey/Settings.swift` | Thanh thẻ kiểu macOS (`NSTabViewController`, `.toolbar`), cửa sổ tự cao theo từng thẻ |
| Nhãn cạnh con trỏ | `Sources/VNKey/HUD.swift` | `NSPanel` không kích hoạt, vị trí lấy qua AX |
| Biểu tượng app | `Scripts/make-icon.swift` → `Resources/AppIcon.icns` | |
| Khoá cài đặt | `Sources/VNKey/Shared.swift` (`Key`) | Mặc định trong `Key.registered` |

## Cách sắp xếp chức năng

Mỗi thẻ trả lời một câu hỏi của người dùng; thêm tuỳ chọn mới thì đặt theo câu hỏi đó, đừng tạo thẻ mới
cho một hai mục.

| Thẻ | Câu hỏi | Nội dung |
|---|---|---|
| Chung | App chạy thế nào? | Phím tắt, nhãn VN/EN, mở cùng lúc đăng nhập, nhật ký, phiên bản |
| Gõ | Tôi gõ kiểu gì? | Bảng gõ, vị trí dấu thanh, phím w, viết hoa đầu câu, dọn khoảng trắng |
| Việt & Anh | Khi nào thì KHÔNG bỏ dấu? | Tự trả lại từ, đoán ngữ cảnh, sửa đảo phím, ngữ cảnh code, chữ teen, từ đã nhớ |
| Gõ tắt | Gõ ít ra nhiều | Gõ tắt của người dùng, bung viết tắt teen |
| Ứng dụng | Khác nhau theo ứng dụng | Nhớ chế độ theo app, sửa lặp chữ ở ô gợi ý, danh sách bắt đầu ở chế độ Anh |

Menu thanh trạng thái chỉ giữ thứ dùng hằng ngày. Đừng đưa tuỳ chọn bật/tắt vào menu.

## Thêm một tuỳ chọn bật/tắt

1. Thêm khoá vào `Key` và giá trị mặc định vào `Key.registered`.
2. Thêm `toggle("Tên", "Mô tả ngắn", key: Key.tên)` vào một `Card` của đúng thẻ. Tuỳ chọn phụ thuộc
   tuỳ chọn khác: thêm `dependsOn: Key.cha` để nó mờ đi khi cha tắt.
3. Đọc nó trong `AppDelegate.applySettings` (vào `Config` nếu là hành vi engine).
4. Nếu là hành vi engine: thêm trường vào `Config`, thêm test.

Công tắc gắn thẳng vào UserDefaults bằng Cocoa Bindings, không cần viết action.

## Thành phần dựng sẵn trong `Settings.swift`

- `page([...])`: một thẻ; lề 20pt, cao vừa nội dung. `Card`, `NSScrollView` và view có
  `identifier == SettingsController.wide` tự giãn hết chiều ngang.
- `title`, `note`: tiêu đề nhóm và chú thích nhỏ.
- `Card(rows:)`: khung bo góc, tự kẻ đường mảnh giữa các dòng.
- `row(tên, mô tả, điều khiển…)`: tên bên trái, điều khiển bên phải. `toggle(...)` là `row` với `NSSwitch`.
- `ListEditor` (ô văn bản mỗi dòng một mục), `AppList` (bảng ứng dụng), `HotkeyButton`.

Quy ước chữ: tên dòng nói điều người dùng nhận được; mô tả một câu, có ví dụ cụ thể (`user, string…`).

## Xem thử

Tự xem bố cục (không cần người dùng, không đụng tới bản đang chạy):

```bash
swift build -c release --product VNKey && .build/release/VNKey --snapshot <thư mục tạm>
```

Sinh `settings-1.png` … `settings-6.png` (từng thẻ Cài đặt) và `status-vn.png`, `status-en.png` (biểu
tượng thanh menu phóng to; thêm `--dark` để xem trên nền tối). Mở ảnh bằng Read để nhìn. Chế độ này
KHÔNG khởi động event tap, nên chạy song song với bản người dùng đang dùng được. Luôn chạy và xem lại
sau mỗi thay đổi bố cục, trước khi nhờ người dùng.

Cho người dùng xem trên màn hình thật:

```bash
./Scripts/run.sh --settings
```

Biểu tượng app: sửa `Scripts/make-icon.swift`, chạy `swift Scripts/make-icon.swift`, xem
`build/AppIcon.iconset/icon_512x512.png`, rồi commit `Resources/AppIcon.icns`.

## Hướng cải thiện đã biết

- "Gõ tắt" và "Từ đã nhớ" vẫn là ô văn bản; có thể nâng lên bảng như `AppList` (giữ định dạng lưu).
- Nhãn HUD rơi về vị trí chuột ở các app không báo vị trí con trỏ (nhiều app Electron).
- Chế độ tối, cỡ chữ lớn và VoiceOver của cửa sổ Cài đặt chưa được ai xem.
- Ảnh chụp không thấy thanh thẻ (nằm trên thanh công cụ của cửa sổ) lẫn menu thanh trạng thái.
