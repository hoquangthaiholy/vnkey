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
- Từ thành nguyên văn vì một phím gõ nhầm ("thii", "vieejk") rồi bị xoá lùi thì đặt `Composer.retry`; phím
  chữ kế tiếp gõ lại phần còn lại từ đầu (`Engine.recomposed`) và thoát nguyên văn nếu hợp lệ. Việc này chỉ
  làm khi có phím mới, không làm trong `backspace()`. Từ đã gõ lặp để huỷ dấu (`noRecompose`) và từ trong
  ngữ cảnh code thì không hiểu lại.
- Gõ tự do là yêu cầu: phím dấu (thanh, mũ/móc, chữ d thứ hai) được đến ở bất kỳ lúc nào sau chữ nó bổ
  nghĩa ("dduwowcj", "duojwcd", "duodwcj" đều là "được"). Bộ `FreeOrder` trong `FreeOrderTests.swift` sinh
  mọi thứ tự hợp lý cho một danh sách từ; đổi luật phím thì chạy nó, thêm vần lạ thì thêm từ vào đó.
- Chữ d gõ muộn thành đ đặt cờ `Composer.lateBar`; `decide()` trả lại phím gốc nếu chuỗi phím là từ tiếng
  Anh ("did", "dad", "deed"). Muốn "đi", "đa" thì gõ "ddi", "dda".
- Từ chỉ sai ở chỗ thiếu dấu thanh trước âm cuối c/ch/p/t ("đươc") không bị trả về phím gốc nếu rõ là
  tiếng Việt (không phải từ tiếng Anh; khi không có từ điển thì cần từ hai dấu mũ/móc/đ trở lên).
- Telex có hai tuỳ chọn trong `Config`: `standaloneW` (w đứng riêng thành ư, mặc định bật) và `bracketKeys`
  (phím [ ] { } thành ơ ư Ơ Ư, mặc định tắt). Phím ngoặc chỉ là phím chữ khi từ chưa nguyên văn và không ở ngữ
  cảnh code; không ghép được vào âm tiết thì nó ngắt từ như dấu câu thường. Bộ `TelexOptions` giữ các luật này.
  Người dùng đã từ chối thêm kiểu gõ "Telex đơn giản 1/2" của OpenKey (2026-11-23): hai công tắc là đủ.
- Đoán từ gõ thiếu dấu (`Engine.predict`, `Predictor`, `Config.predict` / `predictUnmarked`): chạy trong
  `breakWord` sau `transpositionFix`. Nguyên tắc không được phá:
  - chỉ THÊM dấu (đ, mũ/móc, thanh), không đổi chữ cái, không bỏ dấu đã gõ;
  - KHÔNG BAO GIỜ thay một chữ mà từ điển coi là từ tiếng Việt đúng ("dược", "ngươi", "ban"), dù có từ thông
    dụng hơn. Từ điển macOS khá dễ dãi ("tiêng" được coi là đúng) nên có từ sẽ không được đoán: chấp nhận;
  - không đoán từ tiếng Anh, từ đã nhớ, ngữ cảnh code, từ đã gõ lặp huỷ dấu;
  - từ chưa có dấu nào chỉ đoán khi một trong ba từ vừa gõ có dấu và `englishStreak == 0`, và chỉ bằng tầng 1–2;
  - chọn theo tầng: cặp (từ trước → từ) người dùng đã gõ (`ContextModel`) → `Lexicon.rank` (gợi ý theo câu của
    macOS, ~8 ms, có bộ đệm; đo ngày 2026-11-23 đúng 11/11 với chữ chưa thành từ: "tiếng viet" → việt, "bài viet"
    → viết) → độ thông dụng (`CommonWords` + số lần người dùng gõ) → chỉ một ứng viên. Tầng đếm đòi hạng nhất ≥ 2
    lần hạng nhì; không quyết được thì giữ nguyên.
  - Chữ không dấu mà từ điển coi là từ đúng ("loi" trong "lầm loi") CHỈ được sửa bằng thói quen của người dùng:
    họ đã gõ cặp (từ trước → ứng viên) ít nhất 3 lần và nhiều hơn số lần gõ cặp ấy ở dạng không dấu (đòi "chưa
    từng" thì vài lần người dùng gõ thử đã chặn việc học mãi mãi — lỗi đã gặp thật). Quay lại sửa một từ thì lần
    ghi nhận của từ đó được rút lại (`ContextModel.unrecord`). Gợi ý của macOS
    không dùng được ở đây (nó đổi "hôm nay" thành "hôm này"). Vì vậy engine cũng ghi nhận từ không dấu khi đang ở
    ngữ cảnh tiếng Việt. Người dùng đã chọn cách học này thay cho từ điển từ ghép (2026-11-23).
  - Cả cụm hai từ không dấu ("lam loi" → "lầm lỗi") sửa bằng `Engine.phraseFix` + `ContextModel.phrase`: cụm có
    dấu đã được gõ ≥ 3 lần, ≥ 2 lần cụm có dấu khác cùng khớp, và nhiều hơn chính cụm không dấu đó. Không cần
    quanh đó có từ có dấu, nhưng không làm giữa một mạch tiếng Anh. Lần sửa này xoá và gõ lại cả từ đứng trước.
    Vì vậy mọi từ không dấu mà từ điển coi là tiếng Việt đều được ghi nhận (kể cả "to do" trong câu tiếng Anh):
    đó là thứ ngăn việc sửa nhầm.
  - `Engine.fixedWord` báo từ vừa được tự sửa (đoán dấu, sửa đảo phím) để app nháy nhẹ lên nó (`HUD.flash`).
  Từ đã đoán lưu với `resumable = false`; phím "Đổi từ vừa gõ" trả lại phím gốc và nhớ vào `preferRaw`.
  `UsageModel` (VNEngine, thuần Foundation) là bảng đếm có giới hạn; app lưu nó qua `UsageStore`.
- Tự học khi gõ lại (`Config.learnFromRetype`): chỉ khi người dùng xoá ĐÚNG từ vừa gõ gần nhất (chưa gõ chữ nào
  khác sau nó, `freshBreak`), xoá HẾT từ đó mà không xoá lan sang chữ đứng trước, rồi gõ lại đúng chuỗi phím
  (phân biệt hoa/thường). Điều kiện lỏng hơn sẽ học nhầm khi người dùng chỉ giữ phím xoá rồi gõ lại. Việc nhớ
  diễn ra TRƯỚC `transpositionFix`/`decide()` trong `breakWord`, nên chính lần gõ lại đã ra dạng mới.
- Sau khi sửa: `./Scripts/test.sh` và `swift run -c release vnkey-tool bench`.
