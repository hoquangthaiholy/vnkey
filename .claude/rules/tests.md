---
paths:
  - "Tests/**"
---

# Quy tắc cho test

- Dùng swift-testing (`@Suite`, `@Test(arguments:)`, `#expect`). Không có XCTest trên máy này.
- Mỗi ca là cặp `(chuỗi phím, kết quả trên màn hình)` chạy qua `run()`. `<` = Backspace, `~` = đổi từ.
  Kết thúc bằng dấu cách khi muốn kiểm tra quyết định ở ranh giới từ.
- Ca cần từ điển dùng `FakeLexicon.shared`; thêm từ vào đó thay vì gọi NSSpellChecker thật trong test.
- Trước khi ghi kỳ vọng, tự gõ thử chuỗi phím trong đầu theo Telex. Vài ca đã từng sai do kỳ vọng
  viết nhầm chứ không phải engine sai ("tiegns" không thể ra "tiếng" vì chỉ có một chữ e).
- Sửa lỗi thì thêm ca vào đúng nhóm sẵn có; chỉ tạo `@Suite` mới cho một tính năng mới.
- Không xoá hay nới lỏng ca đang có để test qua. Nếu hành vi cố ý thay đổi, nói rõ với người dùng.
