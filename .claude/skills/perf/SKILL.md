---
name: perf
description: Đo và cải thiện hiệu năng của VNKey — độ trễ mỗi phím, thời gian trong callback của event tap, chi phí gọi Accessibility, từ điển và ghi log. Dùng khi người dùng thấy gõ bị trễ, tap bị macOS tắt, hoặc muốn tối ưu.
---

# Hiệu năng VNKey

Nguyên tắc: **đo trước, sửa sau**. Engine đã rất nhanh; đừng tối ưu nó khi chưa có số liệu chỉ ra.

## Ngân sách

Mỗi phím đi qua callback của event tap trên main thread. Người gõ nhanh tạo khoảng 10–15 phím/giây,
nên vài trăm µs mỗi phím là không cảm nhận được. Nguy hiểm thật sự là các lần **đứng hình** hàng
chục ms trở lên: macOS sẽ tắt tap (`TAP … timeout` trong log) và người dùng thấy mất phím.

## Số đo nền (22/11/2026, Apple silicon, bản release)

```bash
swift run -c release vnkey-tool bench
swift run -c release vnkey-tool bench --no-lexicon
```

- Có từ điển: ~2,9 µs/phím trung bình, chậm nhất ~73 µs.
- Không từ điển: ~2,2 µs/phím, chậm nhất ~25 µs.

`bench` thoát với mã lỗi nếu trung bình vượt 50 µs/phím. Chạy lại sau mọi thay đổi trong
`Sources/VNEngine/` và ghi số mới vào đây nếu nó đổi đáng kể.

## Chỗ thực sự tốn thời gian (theo thứ tự nghi ngờ)

1. **Gọi Accessibility trong `KeyTap.focus()`**: IPC đồng bộ sang ứng dụng khác, có thể mất tới thời
   gian timeout (0,1 giây) nếu ứng dụng đó đang treo. Hiện chỉ gọi khi sắp gửi phím xoá. Hướng cải
   thiện: nhớ kết quả theo lần đổi ứng dụng/đổi ô, chỉ hỏi lại khi cần `sel`.
2. **NSSpellChecker lần đầu cho một từ** (`SystemLexicon`): có cache, nhưng lần gọi đầu tiên sau khi
   khởi động phải nạp từ điển. Hướng: làm nóng lúc khởi động trên hàng đợi nền.
3. **Ghi log** (`Log.write`): một lần `write` đồng bộ mỗi phím khi bật. Hướng: gom vào bộ đệm và ghi
   trên hàng đợi nền; nhớ xả khi thoát.
4. **`Composer.attempt`** sao chép cả struct cho mỗi phím biến đổi, và `Letter.glyph` chuẩn hoá NFC
   mỗi lần hiển thị. Nhỏ; chỉ đụng tới nếu `bench` chỉ ra.
5. **HUD**: gọi AX để lấy vị trí con trỏ; đã chạy ngoài callback của tap.

## Đo phía app

`bench` chỉ đo engine. Để đo cả đường đi trong app, thêm tạm phép đo quanh `KeyTap.keyDown`
(`DispatchTime.now().uptimeNanoseconds` trước/sau) và ghi vào dòng `KEY` dạng `dt=…µs`, rồi:

```bash
grep -o "dt=[0-9]*" ~/Library/Logs/VNKey.log | sort -t= -k2 -n | tail
grep "TAP" ~/Library/Logs/VNKey.log
```

Nhìn phân vị cao và giá trị lớn nhất chứ không phải trung bình. Tách riêng thời gian của `focus()`.

## Quy trình

1. Đo, ghi số trước.
2. Đổi **một** thứ.
3. Đo lại, `./Scripts/test.sh` phải qua.
4. Báo số trước/sau; nếu không cải thiện đo được thì hoàn tác.
