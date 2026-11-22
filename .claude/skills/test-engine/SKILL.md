---
name: test-engine
description: Viết và chạy kiểm thử cho VNKey — thêm ca test cho engine gõ, mở rộng độ phủ (Telex, VNI, xen kẽ Anh/teen, xoá lùi, khôi phục), và kiểm tra thủ công phần app. Dùng khi người dùng muốn thêm test, kiểm tra hồi quy, hoặc trước khi commit thay đổi engine.
---

# Kiểm thử VNKey

## Chạy

```bash
./Scripts/test.sh
```

Script tự thử lại khi gặp lỗi `plugin for module 'TestingMacros' not found` (lỗi nạp plugin của
Command Line Tools, không phải lỗi mã). Lọc một nhóm: `./Scripts/test.sh --filter MixedLanguage`.

## Thêm ca cho engine

Tệp `Tests/VNEngineTests/EngineTests.swift`. Mỗi ca là `(chuỗi phím, màn hình mong đợi)`:

```swift
@Test(arguments: [
    ("tieengs vieetj", "tiếng việt"),
    ("vieetj <s", "viết"),      // "<" = Backspace
    ("this ~", "this "),        // "~" = phím đổi từ vừa gõ
])
func compose(keys: String, want: String) { #expect(run(keys) == want) }
```

Trước khi ghi kỳ vọng, xem engine thật sự làm gì:

```bash
swift run vnkey-tool type --trace "<chuỗi phím>"
```

Nếu kết quả khác kỳ vọng, tự hỏi kỳ vọng hay engine sai trước khi sửa bên nào.

Nhóm hiện có: `Telex` (soạn, huỷ dấu, xoá lùi), `MixedLanguage` (tiếng Anh, teen, macro, từ điển,
học từ), `VNI`, `Experience` (ngữ cảnh, code, đảo phím, viết hoa, dấu câu).

## Test logic app (`Tests/VNKeyCoreTests/CoreTests.swift`)

Phần quyết định của app nằm trong `Sources/VNKeyCore/` và test được: phím tắt, theo dõi phím bổ trợ,
phân loại phím, kế hoạch gửi phím, chế độ theo ứng dụng, định dạng danh sách cài đặt.

Nhóm `EndToEnd` chạy cả đường đi engine → `SendPlanner` → màn hình trên `Field`, một mô hình ô nhập:

- `.plain`: ô thường.
- `.spotlight(leftAbsorbed:)`: gợi ý nằm ngoài nội dung, phím xoá đầu tiên chỉ gạt gợi ý.
- `.browser`: gợi ý được chèn sau con trỏ và bôi chọn.

Các mô hình này là **giả thuyết** dựng từ nhật ký và quan sát của người dùng. Chúng bắt lỗi hồi quy và
đã tìm ra lỗi lệch trạng thái khi người dùng tự xoá lùi, nhưng không thay được việc gõ thử thật. Khi
một ứng dụng thật cư xử khác mô hình, sửa mô hình trước rồi mới sửa `SendPlanner`.

Hàm `typeInto` trong tệp test phải đi đúng các nhánh như `KeyTap.keyDown`; đổi bên này thì đổi bên kia.

## Chỗ còn mỏng, nên bổ sung khi có dịp

- Caps Lock, từ viết hoa toàn bộ bị trả lại.
- Tổ hợp nhiều tuỳ chọn hơn (viết hoa đầu câu + ngữ cảnh code, macro + teen).
- Mô hình ô nhập cho terminal và app Electron.
- Phần còn lại của `Sources/VNKey/` (event tap, phát sự kiện, cửa sổ Cài đặt, HUD, UserDefaults) vẫn
  chưa có test tự động.

## Kiểm tra phần app

Không tự động được: cần quyền Trợ năng và ứng dụng thật, và Claude không gõ hay chụp màn hình được
trên máy này. Cách làm:

1. `./Scripts/run.sh`, xác nhận dòng khởi động trong log có `AX trusted=true`.
2. Đưa người dùng danh sách ngắn chuỗi phím + kết quả mong đợi + ứng dụng cần thử.
3. Sau khi họ thử, đọc `~/Library/Logs/VNKey.log` để đối chiếu `shown=` với điều mong đợi.

Bộ ứng dụng nên thử khi đổi cách gửi phím: TextEdit, Spotlight, thanh địa chỉ Chrome và Safari,
một app Electron (VS Code hoặc Slack), Terminal, Notes.
