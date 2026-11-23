---
paths:
  - "Sources/VNKey/**"
  - "Sources/VNKeyCore/**"
---

# Quy tắc cho app macOS

- Sự kiện do VNKey phát ra phải gắn `kMagic` vào `eventSourceUserData` và đi qua `post()`, nếu không
  tap sẽ xử lý lại chính phím của mình.
- Phát phím bằng `tapPostEvent(proxy)` để giữ đúng thứ tự trong luồng sự kiện. Khi cần phím gốc đi
  sau phần sửa, nuốt phím gốc rồi phát lại bản sao (xem `send`).
- Phím không làm đổi gì thì cho đi thẳng (`Output.isPass`), không nuốt rồi phát lại.
- Quyết định nào không cần chạm vào hệ thống thì đặt trong `Sources/VNKeyCore/` và có test. `KeyTap` chỉ
  đọc sự kiện, hỏi Accessibility, rồi thi hành `SendPlan`.
- Mẹo theo từng ứng dụng nằm trong `SendPlanner.plan`, chọn theo `focus().app` chứ không theo `frontApp`.
  Thêm mẹo mới: thêm chế độ vào `plan`, thêm loại ô vào `Field` trong `CoreTests.swift`, và viết ca
  `EndToEnd` cho nó. Tên chế độ tự hiện trong dòng log `SEND mode=…`.
- Phím xoá lùi của người dùng đi qua `SendPlanner.userBackspace`: nếu ứng dụng chỉ gạt gợi ý thì KHÔNG
  được gọi `engine.backspace()`, nếu không engine sẽ lệch với màn hình.
- Gọi AX chỉ khi sắp gửi phím xoá, luôn đặt `AXUIElementSetMessagingTimeout` (≤ 0,15 giây).
- Thông tin về ô đang nhận phím (`focusCache`) bỏ hay giữ là do `FocusPolicy` (VNKeyCore) quyết: chuột và
  phím mũi tên giữ bản cũ rồi làm mới ở luồng nền; phím tắt, Tab/Enter, đổi ứng dụng thì bỏ. Khi cache trống
  vẫn tra đồng bộ (đúng kiểu gửi quan trọng hơn vài chục ms; bỏ bước này thì lỗi "toôi" ở Spotlight quay lại).
- Phím xoá lùi đang lặp không hỏi lại vùng chọn. `perf.ax` chỉ đếm lần thật sự gọi sang ứng dụng khác.
- `Log.write` chỉ dựng chuỗi rồi xếp hàng; ghi đĩa ở luồng nền. Đọc lại tệp log trong test hay công cụ thì gọi
  `Log.flush()` trước. Đừng tính `engine.debugState` khi `Log.enabled` là false.
- App không hiện menu chính nhưng PHẢI có `NSApp.mainMenu` (`installMainMenu`): thiếu nó thì ⌘C/⌘V/⌘Z/⌘W
  không chạy trong cửa sổ Cài đặt.
- Phím tắt mới phải qua `Hotkey.problem(other:)` (không nhận ⇧ + phím, không trùng phím tắt kia).
- Việc nặng trong callback của tap (AX, cửa sổ, HUD) phải đẩy sang `DispatchQueue.main.async`.
- Cài đặt lưu trong UserDefaults với khoá trong `Key`; thêm khoá mới thì thêm cả vào `Key.registered`
  và `AppDelegate.applySettings`. Chỉ gán `engine.config` khi nó thật sự đổi (gán là xoá trạng thái gõ).
- Giao diện AppKit thuần. Ô đánh dấu gắn UserDefaults qua Cocoa Bindings (`SettingsController.check`).
- Mọi nhánh mới trong xử lý phím phải có dòng `Log.write`. Dùng `Log.show` cho chuỗi có ký tự điều khiển.
