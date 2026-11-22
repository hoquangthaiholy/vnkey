---
paths:
  - "Sources/VNEngine/**"
---

# Quy tắc cho engine

- Mọi phép biến đổi (mũ, móc, đ) đi qua `attempt`: chỉ nhận khi kết quả còn là tiền tố âm tiết hợp lệ,
  không thì coi phím là chữ thường. Đừng biến đổi vô điều kiện.
- Mỗi phím thô phải thêm đúng MỘT phần tử vào `owner`. `raw.count == owner.count` là bất biến;
  xoá lùi và khôi phục dựa vào nó.
- Phím lặp để huỷ dấu ("ass", "aaa", "ddd") trả về `.cancelled` và bỏ qua kiểm tra tiền tố.
- Thêm vần mới vào `Syl.nuclei` thì kiểm tra cả dạng không dấu có va chạm với vần khác không
  (`unmarkedNuclei` gộp chúng lại).
- Quyết định khôi phục nằm ở `Engine.decide()` theo thứ tự: từ đã học → chế độ nguyên văn →
  sai cấu trúc → danh sách tiếng Anh dựng sẵn → từ điển → ngữ cảnh. Thêm luật mới thì đặt đúng tầng.
- Từ hợp lệ ở cả hai ngôn ngữ (this/thí) mặc định giữ tiếng Việt. Đừng thêm ngoại lệ lẻ vào
  `builtinEnglish` cho từ mà nghĩa tiếng Việt cũng thông dụng.
- `Engine.type` chạy cho mỗi phím: không cấp phát thừa, không gọi từ điển giữa từ. Từ điển chỉ được
  hỏi ở ranh giới từ.
- `Engine.backspace()` LUÔN trả về `.pass`: màn hình mất đúng ký tự cuối, engine chỉ cập nhật cho khớp.
  Không bao giờ sửa chữ khác khi xoá lùi (phát phím trong lúc người dùng giữ phím xoá làm lệch màn hình).
  Chữ bị xoá mang dấu thanh thì dấu mất theo ("tiế" → "ti"); nếu cách hiển thị chuẩn khác màn hình
  ("hoà" so với "hòa") thì phím kế tiếp hoặc lúc kết thúc từ sẽ sửa. Test `BackspaceIsPlain` giữ điều này.
- Gõ tự do là yêu cầu: phím dấu (thanh, mũ/móc, chữ d thứ hai) được đến ở bất kỳ lúc nào sau chữ nó bổ
  nghĩa ("dduwowcj", "duojwcd", "duodwcj" đều là "được"). Bộ `FreeOrder` trong `FreeOrderTests.swift` sinh
  mọi thứ tự hợp lý cho một danh sách từ; đổi luật phím thì chạy nó, thêm vần lạ thì thêm từ vào đó.
- Chữ d gõ muộn thành đ đặt cờ `Composer.lateBar`; `decide()` trả lại phím gốc nếu chuỗi phím là từ tiếng
  Anh ("did", "dad", "deed"). Muốn "đi", "đa" thì gõ "ddi", "dda".
- Từ chỉ sai ở chỗ thiếu dấu thanh trước âm cuối c/ch/p/t ("đươc") không bị trả về phím gốc nếu rõ là
  tiếng Việt (không phải từ tiếng Anh; khi không có từ điển thì cần từ hai dấu mũ/móc/đ trở lên).
- Sau khi sửa: `./Scripts/test.sh` và `swift run -c release vnkey-tool bench`.
