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
- Việc nặng trong callback của tap (AX, cửa sổ, HUD) phải đẩy sang `DispatchQueue.main.async`.
- Cài đặt lưu trong UserDefaults với khoá trong `Key`; thêm khoá mới thì thêm cả vào `Key.registered`
  và `AppDelegate.applySettings`. Chỉ gán `engine.config` khi nó thật sự đổi (gán là xoá trạng thái gõ).
- Giao diện AppKit thuần. Ô đánh dấu gắn UserDefaults qua Cocoa Bindings (`SettingsController.check`).
- Mọi nhánh mới trong xử lý phím phải có dòng `Log.write`. Dùng `Log.show` cho chuỗi có ký tự điều khiển.
