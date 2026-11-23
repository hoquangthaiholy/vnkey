# VNKey

Bộ gõ tiếng Việt cho macOS (kiểu OpenKey): app thanh menu chặn phím toàn hệ thống bằng CGEventTap,
đưa qua engine, rồi phát lại "xoá lùi + văn bản". Ưu tiên: gõ xen kẽ Việt/Anh/teen, khôi phục từ
gõ sai dựa trên thứ tự phím, và trải nghiệm gõ.

Giao tiếp với người dùng, chú thích trong mã, chuỗi giao diện và commit message đều bằng tiếng Việt.

## Lệnh

| Việc | Lệnh |
|---|---|
| Test engine | `./Scripts/test.sh` (tự thử lại khi plugin macro lỗi) |
| Build + mở lại app | `./Scripts/run.sh` (thêm `--settings` để mở cửa sổ Cài đặt) |
| Chỉ đóng gói | `./Scripts/build-app.sh` → `build/VNKey.app` |
| Gõ lại một chuỗi phím | `swift run vnkey-tool type --trace "tooi ddang"` (`<` = Backspace, `~` = đổi từ) |
| Đo hiệu năng engine | `swift run -c release vnkey-tool bench` |
| Xem nhật ký | `tail -50 ~/Library/Logs/VNKey.log` |

## Kiến trúc

- `Sources/VNEngine/` — engine thuần Swift, không đụng tới hệ thống.
  - `Syllable.swift`: luật âm tiết (âm đầu, vần, âm cuối, thanh); `isValid` và `isValidPrefix`.
  - `Composer.swift`: trạng thái của MỘT từ. Giữ chuỗi phím gốc `raw` và `owner` (phím nào tạo chữ nào).
  - `Engine.swift`: ranh giới từ, lịch sử, quyết định khôi phục, học từ, ngữ cảnh. Trả về `Output`.
  - `Predictor.swift`, `CommonWords.swift`, `UsageModel.swift`: đoán từ gõ thiếu dấu (ứng viên, danh sách từ
    thông dụng, bảng đếm thói quen gõ của người dùng).
  - `SystemLexicon.swift`: từ điển `en`/`vi` của macOS qua NSSpellChecker (tệp duy nhất dùng AppKit).
- `Sources/VNKey/` — app: `KeyTap` (event tap, gửi phím), `main` (AppDelegate, menu), `Settings`
  (cửa sổ cài đặt), `Onboarding` (hướng dẫn cấp quyền Trợ năng), `HUD` (nhãn VN/EN), `Shared` (khoá
  UserDefaults).
- `Sources/VNKeyCore/` — logic thuần của app, test được: `SendPlanner` (kế hoạch gửi phím theo ứng dụng,
  xử lý phím xoá lùi của người dùng), `classifyKey`, `Hotkey`, `ModifierTracker`, `AppMode`, `ListFormat`.
  `KeyTap` chỉ còn việc đọc sự kiện, hỏi Accessibility và phát phím theo kế hoạch.
- `Sources/VNTool/` — `vnkey-tool`: tái hiện lỗi và đo hiệu năng không cần giao diện.
- `Tests/VNEngineTests/` — test engine bằng swift-testing; `run()` giả lập màn hình.
- `Tests/VNKeyCoreTests/` — test logic app, kèm `Field`: mô hình ô nhập (thường, Spotlight, trình duyệt)
  để chạy cả đường đi engine → kế hoạch gửi → màn hình.

Hợp đồng giữa engine và app là `Output { backspaces, text, passKey }`. Engine không biết gì về
ứng dụng đích; mọi mẹo theo từng ứng dụng nằm trong `SendPlanner` (VNKeyCore), `KeyTap.send` chỉ thi hành.

## Quy tắc bắt buộc

1. **Lỗi gõ nào cũng phải có test trước khi sửa.** Tái hiện bằng `vnkey-tool type --trace`, thêm ca
   vào `EngineTests.swift`, thấy nó đỏ, rồi mới sửa. Lỗi phía app (gửi phím) không test tự động
   được thì ghi rõ là chưa kiểm chứng.
2. **Không tuyên bố "đã sửa" với lỗi trong ứng dụng thật khi chưa có người dùng xác nhận.** Claude
   không gõ được vào ứng dụng khác và không chụp được màn hình trên máy này (bố cục cửa sổ Cài đặt thì
   tự xem được bằng `VNKey --snapshot`, xem skill `ui`). Nói rõ phần nào đã
   test, phần nào mới chỉ biên dịch.
3. **Chẩn đoán bằng nhật ký, không đoán.** Lỗi Spotlight "toôi" tốn bốn vòng đoán; một dòng log đã
   chỉ ra nguyên nhân. Thiếu thông tin thì thêm dòng log rồi nhờ người dùng thử lại.
4. **Nhật ký chứa nguyên văn nội dung gõ.** Chỉ đọc đoạn cần thiết quanh thời điểm lỗi, không dán
   nội dung người dùng gõ vào câu trả lời, commit hay dịch vụ bên ngoài.
5. **Không dùng SwiftUI.** Máy chỉ có Command Line Tools, thiếu plugin `SwiftUIMacros`, nên
   `@State`/`@AppStorage` không biên dịch được. Giao diện viết bằng AppKit.
6. **Callback của event tap phải nhanh.** Không I/O đồng bộ nặng, không gọi AX cho mỗi phím. macOS
   tắt tap khi callback chậm.
7. **Luôn ký bằng chứng chỉ "VNKey Dev"** (script đã lo). Ký ad-hoc làm mất quyền Trợ năng sau
   mỗi lần build. Không đụng tới cài đặt tin cậy của keychain.
8. **Engine không được phụ thuộc vào app.** Không import AppKit trong VNEngine ngoài `SystemLexicon.swift`.

## Điều đã biết về môi trường

- Xcode không được cài; chỉ có Command Line Tools. Không có `xcodebuild`, không có XCTest UI.
- Build test thỉnh thoảng báo `plugin for module 'TestingMacros' not found`; chạy lại là qua.
- Spotlight trên macOS này là tiến trình `com.apple.campo`. Gợi ý của nó không nằm trong nội dung ô
  nhập, và phím xoá lùi đầu tiên chỉ gạt gợi ý. Cách đang dùng: gửi ← rồi → trước khi xoá.
- Spotlight và các bảng nổi nhận phím mà không thành "ứng dụng ở trước": dùng `KeyTap.focus()`.
- Bản sửa cho thanh địa chỉ trình duyệt (chèn U+202F) chưa được kiểm chứng trên ứng dụng thật; nó chỉ
  còn chạy khi không hỏi được vùng bôi chọn.
- Văn bản được phát bằng sự kiện phím kèm chuỗi Unicode. Mã phím của sự kiện đó KHÔNG được trùng phím
  người dùng đang giữ: Safari coi nó là phím lặp và bỏ đoạn chữ (gõ "ddia" rồi "j" khi chưa nhả "a" làm
  mất "ịa"). `HeldKeys.carrier` chọn mã phím an toàn.
- Khi bật nhật ký, sau mỗi lần sửa chữ VNKey đọc lại ô nhập và ghi `VERIFY khớp` / `VERIFY LỆCH`. Tìm
  `VERIFY LỆCH` trước tiên khi người dùng báo chữ ra sai: nó chỉ đúng phím gây lệch.

- Thói quen gõ (bảng đếm từ và cặp từ, không có câu) lưu ở `~/Library/Application Support/VNKey/usage.json`.
  Coi nó riêng tư như nhật ký: không đọc ra, không dán vào câu trả lời.

## Commit

Tiêu đề tiếng Việt, ngắn, nói thay đổi gì. Chỉ commit khi người dùng yêu cầu. Chạy `./Scripts/test.sh`
trước khi commit thay đổi trong `Sources/VNEngine/`.
