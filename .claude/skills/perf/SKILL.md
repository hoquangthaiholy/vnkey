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

Các phần ngoài engine đo được không cần giao diện:

```bash
swift run -c release vnkey-tool bench-parts
```

- Từ điển: lần gọi đầu ~1 ms, từ chưa gặp ~0,13 ms, từ đã nhớ ~0,1 µs. Chỉ gọi ở ranh giới từ.
- Ghi log: ~3,8 µs/dòng, chậm nhất dưới 0,1 ms.

**Đã loại khỏi diện nghi ngờ** (đừng tối ưu khi chưa có số liệu mới): engine, ghi log đồng bộ, khởi động từ điển.

## Đo trong app thật

`KeyTap` đo thời gian từng phím trong callback và thời gian hỏi Accessibility (`PerfStats`):

```bash
grep -E "PERF|SLOW|TAP" ~/Library/Logs/VNKey.log | tail -40
```

- `PERF phím=… tb=…µs max=…ms ≥1ms=… ≥10ms=… | ax=… tb=…µs max=…ms`: tổng kết mỗi 200 phím hoặc 30 giây.
- `SLOW dt=…ms ax=…ms app=…`: từng phím mất từ 2 ms trở lên, kèm phần thời gian do Accessibility.
- `TAP … timeout`: macOS đã tắt tap vì callback quá chậm — đây là sự cố, không phải số liệu.

Nhìn `max` và số phím `≥10ms` chứ không phải trung bình. Claude không tự tạo phím được, nên số liệu
này chỉ có khi người dùng gõ; nhờ họ gõ vài phút ở nhiều loại ứng dụng rồi mới đọc.

### Số đo thật trước khi nhớ tiêu điểm (22/11/2026)

- Claude desktop: 55 phím, trung bình 1143 µs, chậm nhất 25,6 ms; 11 lần hỏi AX, trung bình 3,5 ms.
- Safari: 115 phím, trung bình 779 µs; 40 lần hỏi AX, trung bình 1,3 ms; có phím đơn lẻ 45 ms.
- Ở mọi dòng `SLOW`, phần `ax` chiếm gần hết `dt`: phím chậm = phím có hỏi Accessibility.

Sau đó `KeyTap` nhớ ô đang nhận phím (`FocusCache`) cho tới khi có chuột, phím tắt, Tab, Enter, đổi
ứng dụng hoặc quá 5 giây; bỏ truy vấn `AXValue`; thôi hỏi vùng chọn ở app đã trả lỗi và ở Spotlight.

### Số đo thật sau khi nhớ tiêu điểm (22/11/2026)

- Claude desktop: 295 phím, trung bình ~610 µs; 85 lần hỏi AX, trung bình ~310 µs (trước: 3,5 ms). Chỉ
  lần hỏi đầu tiên sau khi đổi tiêu điểm còn chậm (18,6 ms); 1 phím ≥10 ms trên 295 (trước: 2 trên 55).
- Safari: 322 phím, trung bình ~575 µs; 88 lần hỏi AX, trung bình ~0,9 ms (trước: 1,3–5,9 ms); chậm
  nhất 19,7 ms (trước: 45 ms); 3 phím ≥10 ms trên 322 (trước: 4 trên 161).

Kết luận: cải thiện rõ ở app không trả lời được câu hỏi vùng chọn (Electron); ở Safari chỉ cải thiện
vừa phải vì chính truy vấn vùng chọn còn lại vẫn có lúc mất 10–20 ms.

Bước tiếp theo đã làm: chỉ hỏi vùng chọn ở ô một dòng (`SendPlanner.shouldAskSelection`: vai trò
`AXTextField`, `AXComboBox`, `AXSearchField`), và trong trình duyệt chỉ chèn ký tự rỗng ở các ô đó. Gõ
trong nội dung trang web không còn hỏi AX mỗi lần sửa chữ. Số đo sau bước này (Safari, vùng `AXTextArea`): khi ô đã
được nhớ, 28 lần hỏi trung bình 0,2 ms, chậm nhất 2,5 ms. Nhưng lần TRA CỨU ô nhập (tìm phần tử đang
nhận phím + vai trò) vẫn chạy trong callback và mất 22 ms, có lần 85 ms.

Bước kế: tra cứu chạy ở luồng nền (`prefetchFocus`), kích hoạt bởi phím thường đầu tiên sau khi tiêu
điểm đổi hoặc khi thông tin cũ quá 5 giây; dòng log `FOCUS nền …ms`. Chỉ khi phím sửa chữ tới trước lúc
tra cứu xong mới phải tra đồng bộ (`SEND … lookup`). KHÔNG tra cứu ngay trên phím làm đổi tiêu điểm
(⌘Space, Tab, Enter): ô mới chưa nhận tiêu điểm, sẽ nhớ nhầm ô cũ và làm hỏng bản sửa Spotlight.
Số đo sau bước này: tra cứu nền chạy đúng (`FOCUS nền` tới 20 ms mà không chặn phím nào); phím chậm còn
lại là truy vấn vùng chọn ở ô một dòng của Safari, thỉnh thoảng 36–45 ms (khoảng một lần trên trăm
phím). Truy vấn này phải đồng bộ vì kết quả quyết định cách xoá; muốn bỏ nó phải tìm cách sửa chữ ở
thanh địa chỉ mà không cần biết có gợi ý hay không. Khi đọc log,
xem `role=` ở dòng `SEND` để biết người dùng gõ ở loại ô nào.

Điều mới lộ ra: có những phím mất 2–4 ms mà `ax=0.00ms`, và khoảng 10–15% số phím mất ≥1 ms dù không
hỏi AX. Chưa biết phần nào gây ra (phát sự kiện, sửa đảo phím ở ranh giới từ, dựng chuỗi log). Muốn
biết phải tách `dt` thành engine / gửi phím / log trước khi sửa gì.

## Chỗ còn nghi ngờ

1. **Gọi Accessibility trong `KeyTap.focus()`**: IPC đồng bộ sang ứng dụng khác, tối đa bằng timeout
   (0,1 giây) nếu ứng dụng đó treo. Sau khi nhớ tiêu điểm, mỗi lần gửi phím xoá còn tối đa MỘT truy vấn
   (vùng bôi chọn), và lần đầu sau khi tiêu điểm đổi thêm hai truy vấn. Nếu vẫn chậm: chỉ hỏi vùng chọn
   ở ô kiểu `AXTextField`/`AXComboBox`, nơi gợi ý tự điền thật sự xuất hiện.
2. **`Composer.attempt`** sao chép cả struct cho mỗi phím biến đổi, và `Letter.glyph` chuẩn hoá NFC
   mỗi lần hiển thị. Nhỏ; chỉ đụng tới nếu `bench` chỉ ra.
3. **HUD**: gọi AX để lấy vị trí con trỏ; đã chạy ngoài callback của tap.

## Quy trình

1. Đo, ghi số trước.
2. Đổi **một** thứ.
3. Đo lại, `./Scripts/test.sh` phải qua.
4. Báo số trước/sau; nếu không cải thiện đo được thì hoàn tác.
