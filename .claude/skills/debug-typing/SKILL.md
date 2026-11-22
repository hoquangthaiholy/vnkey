---
name: debug-typing
description: Tìm và sửa lỗi gõ của VNKey từ báo cáo của người dùng (ra sai chữ, lặp chữ, mất dấu, từ bị trả lại sai, không gõ được trong một ứng dụng). Dùng khi người dùng nói "xem log", dán kết quả gõ sai, hoặc báo một ứng dụng gõ không đúng.
---

# Gỡ lỗi gõ

Mục tiêu: xác định lỗi nằm ở **engine** (quyết định sai) hay ở **app** (quyết định đúng nhưng ứng
dụng đích nhận sai), rồi sửa đúng chỗ. Không đoán khi log có thể trả lời.

## 1. Đọc nhật ký

```bash
tail -80 ~/Library/Logs/VNKey.log
```

Nhật ký chứa nguyên văn nội dung gõ: chỉ lấy đoạn quanh thời điểm lỗi, không dán lại nội dung gõ
của người dùng ngoài phần cần để giải thích lỗi.

Mỗi phím là một dòng `KEY`, theo sau là `SEND` nếu có sửa chữ:

```
KEY code=31 ch="o" mods= app=… | raw="toi" shown="toi" hist=0 -> bs=2 text="ôi" passKey=false | raw="toio" shown="tôi" hist=0
  SEND mode=nudge xoá=2 focus=com.apple.campo role=AXTextField sel=0 valueLen=3
```

Các dòng khác: `RESET <lý do>`, `APP`, `MODE`, `HOTKEY`, `TAP`, `SECURE INPUT`, `CONFIG`.

Nếu log trống: kiểm tra `AX trusted=` ở dòng khởi động, mục "Ghi nhật ký gỡ lỗi" trong menu, và
`SECURE INPUT`.

Tìm chỗ màn hình lệch với engine trước tiên:

```bash
grep -n "VERIFY LỆCH" ~/Library/Logs/VNKey.log | tail
```

Dòng `VERIFY LỆCH … engine="…" màn hình=…"…"` nằm ngay sau phím gây lỗi. Xem khoảng cách thời gian với
phím trước đó: hai phím cách nhau vài mili giây (gõ lăn tay) là dấu hiệu sự kiện bị ứng dụng bỏ hoặc
đảo thứ tự. Phép đối chiếu bị bỏ qua nếu người dùng gõ tiếp trong 0,12 giây, và không chạy ở ứng dụng
không cho đọc nội dung ô nhập.

## 2. Phân loại

- `shown="…"` sau phím **khác** với điều người dùng mong muốn → lỗi **engine**. Sang bước 3.
- `shown` đúng nhưng màn hình sai → lỗi **app**. Sang bước 4.
- Có `RESET` ngay trước chỗ sai → engine bị xoá trạng thái giữa từ; xem lý do reset có hợp lý không.
- Không có dòng `KEY` cho phím đó → tap không nhận được (secure input, tap bị tắt, chế độ EN).

## 3. Lỗi engine

1. Ghép các `ch="…"` thành chuỗi phím và tái hiện:
   ```bash
   swift run vnkey-tool type --trace "<chuỗi phím>"
   ```
   Mặc định dùng từ điển thật của macOS; thêm `--no-lexicon` để xem hành vi thuần cấu trúc.
2. Thêm ca vào `Tests/VNEngineTests/EngineTests.swift`, chạy `./Scripts/test.sh`, xác nhận nó đỏ.
3. Sửa trong `Sources/VNEngine/` (đọc `.claude/rules/engine.md`), chạy lại test.

## 4. Lỗi app

Engine đúng, nên vấn đề là cách ứng dụng đích xử lý chuỗi "xoá lùi + văn bản".

1. Nhìn `SEND`: `focus=` là tiến trình thật sự nhận phím (có thể khác `app=`), `mode=` là mẹo đã dùng.
2. So số ký tự thừa/thiếu trên màn hình với `xoá=`. Thiếu đúng một lần xoá thường là gợi ý tự điền
   nuốt phím xoá đầu tiên (đã gặp ở Spotlight).
3. Nếu thiếu dữ kiện, thêm thuộc tính cần xem vào `KeyTap.focus()` và dòng `SEND`, build lại, nhờ
   người dùng thử một lần rồi đọc log. Mỗi vòng nhờ người dùng thử là tốn công của họ: gom mọi thứ
   cần biết vào một lần.
4. Các mẹo đang có trong `KeyTap.send`: `selection` (thêm một phím xoá khi có vùng chọn), `nudge`
   (← → rồi xoá), `emptyChar` (chèn U+202F rồi xoá). Thêm bundle ID vào đúng tập, hoặc thêm chế độ mới.

## 5. Kết thúc

```bash
./Scripts/run.sh
```

Báo rõ: nguyên nhân, đã sửa gì, phần nào có test, phần nào cần người dùng gõ thử lại. Lỗi phía app
chỉ được coi là xong khi người dùng xác nhận.
