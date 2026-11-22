---
name: ui
description: Sửa và cải thiện giao diện của VNKey — menu thanh trạng thái, cửa sổ Cài đặt, nhãn VN/EN cạnh con trỏ, biểu tượng, chuỗi hiển thị. Dùng khi người dùng muốn đổi bố cục, thêm tuỳ chọn, làm giao diện đẹp hơn hoặc báo giao diện bị lệch.
---

# Giao diện VNKey

## Ràng buộc

- **AppKit thuần, không SwiftUI.** Thiếu plugin `SwiftUIMacros` trong Command Line Tools nên
  `@State`, `@AppStorage` không biên dịch được. Đừng thử lại trừ khi người dùng đã cài Xcode.
- **Claude không nhìn được giao diện.** `screencapture` bị từ chối (không có quyền Screen Recording).
  Mọi thay đổi bố cục cần người dùng xem và, nếu lệch, gửi ảnh chụp màn hình. Nói rõ điều đó thay vì
  bảo "trông ổn".
- Chuỗi hiển thị bằng tiếng Việt, ngắn, nói điều người dùng nhận được chứ không nói cơ chế.

## Bản đồ

| Thành phần | Tệp | Ghi chú |
|---|---|---|
| Menu thanh trạng thái | `Sources/VNKey/main.swift` (`menuNeedsUpdate`) | Dựng lại mỗi lần mở; tiêu đề `VN`/`EN` + `⚠︎`/`🔒` |
| Cửa sổ Cài đặt | `Sources/VNKey/Settings.swift` | `NSTabView` 6 thẻ, mỗi thẻ là một `NSStackView` dọc |
| Nhãn cạnh con trỏ | `Sources/VNKey/HUD.swift` | `NSPanel` không kích hoạt, vị trí lấy qua AX |
| Khoá cài đặt | `Sources/VNKey/Shared.swift` (`Key`) | Mặc định trong `Key.registered` |

## Thêm một tuỳ chọn bật/tắt

1. Thêm khoá vào `Key` và giá trị mặc định vào `Key.registered`.
2. Thêm `check("Nhãn…", Key.tên)` vào đúng thẻ trong `Settings.swift`; kèm `hint(…)` nếu cần giải thích.
3. Đọc nó trong `AppDelegate.applySettings` (vào `Config` nếu là hành vi engine).
4. Nếu là hành vi engine: thêm trường vào `Config`, thêm test.

`check` gắn thẳng vào UserDefaults bằng Cocoa Bindings, không cần viết action.

## Các thành phần dựng sẵn trong `SettingsController`

`page(_:stretch:)`, `check`, `hint`, `heading`, `separator`, `row`, `listEditor(key, lowercase:)`,
`HotkeyButton`. Danh sách (gõ tắt, từ đã nhớ, ứng dụng) hiện là ô văn bản mỗi dòng một mục; nếu
nâng lên `NSTableView` thì giữ nguyên định dạng lưu trong UserDefaults.

## Xem thử

```bash
./Scripts/run.sh --settings
```

Mở app kèm cửa sổ Cài đặt. Mở lại VNKey khi nó đang chạy cũng mở cửa sổ này.

## Hướng cải thiện đã biết

- Thanh trạng thái đang dùng chữ `VN`/`EN`; có thể đổi sang biểu tượng SF Symbols hoặc ảnh template.
- App chưa có biểu tượng (`.icns`) và chưa có mục "Giới thiệu".
- Cửa sổ Cài đặt chưa có trạng thái vô hiệu hoá cho các mục phụ thuộc "Tự trả lại từ…".
- Danh sách ứng dụng hiện bundle ID thô, chưa hiện tên và biểu tượng ứng dụng.
- Nhãn HUD rơi về vị trí chuột ở các app không báo vị trí con trỏ (nhiều app Electron).
- Chưa kiểm tra chế độ tối, cỡ chữ lớn, và VoiceOver cho cửa sổ Cài đặt.
