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
  Ngoại lệ: phím dấu thanh lặp khi trước đó đã có một phím dấu thanh KHÁC bị đè ("userr", "asrr") không phải huỷ dấu:
  từ thành nguyên văn với ĐỦ các phím đã gõ, không `cancelled` (huỷ dấu ở đây từng nuốt mất phím đầu: "userr" ra "uer";
  bộ test `RepeatedToneKeyAfterAnotherTone`).
- Thêm vần mới vào `Syl.nuclei` thì kiểm tra cả dạng không dấu có va chạm với vần khác không
  (`unmarkedNuclei` gộp chúng lại).
- Quyết định khôi phục nằm ở `Engine.decide()` theo thứ tự: từ đã học → chế độ nguyên văn →
  sai cấu trúc → danh sách tiếng Anh dựng sẵn → từ điển → ngữ cảnh. Thêm luật mới thì đặt đúng tầng.
- Giữa một mạch tiếng Anh (`englishStreak` ≥ 2, `Config.contextAware`) từ hợp lệ ở cả hai ngôn ngữ coi là tiếng Anh,
  TRỪ KHI chữ tiếng Việt rất thông dụng (`CommonWords.count` ≥ `veryCommon` = 5000: "cos" luôn là "có", còn "this" vẫn là "this" vì "thí" không đủ thông dụng). Người dùng chốt
  2026-11-25: ở chế độ tiếng Việt thì ưu tiên tiếng Việt; thiếu ngoại lệ này "cos" bị trả lại rồi tự nối dài mạch
  tiếng Anh (bộ test `VietnameseWinsInVietnameseMode`).
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
  ngữ cảnh code thì không hiểu lại. Từ nguyên văn mà phần còn lại là CHỮ đã có dấu ("Đ" sau "Ddj" rồi xoá: phím dấu gõ
  lúc chưa có nguyên âm) thì dịch chữ ngược về phím (`Engine.keys(for:)`) rồi gõ lại, chỉ nhận khi ra đúng chữ đang
  hiện (bộ test `RetryAfterAStrayToneKey`; lỗi gặp thật: "Đạt" ra "Đajt").
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
- **Engine KHÔNG tự sửa chữ** (người dùng chốt 2026-11-25, sau lỗi "việc dới" bị đổi thành "đới"). Ở `breakWord`
  chỉ còn: `decide()` (trả lại từ tiếng Anh, gõ xen kẽ), gõ tắt, viết hoa, dọn dấu câu. Đừng thêm lại phép đoán nào
  vào `breakWord`: đoán dấu (`predict`), gõ đảo phím (`transpositionFix`), trật phím dấu (`neighborFix`), lỗi gõ đã
  học (`typoFix`), cụm hai từ (`phraseFix`), `Config.predict` / `fixTransposition` / `fixTypos` / `fixNeighborKeys`,
  `Engine.fixedWord` đều đã gỡ. Phím "Đổi từ vừa gõ" chỉ còn hai dạng: phím gốc ↔ tiếng Việt. Gõ dấu tự do
  ("vieejt", "dduwojwc") là việc của `Composer`, không phải tự sửa, vẫn chạy.
- **Soát lỗi (`Proofreader.swift`, bộ test `Proofreading`, `TypedTextIsFlaggedNotChanged`, `MissingMarkSuggestions`,
  `LearnedTypos`)** thay cho tự sửa: `check(text, caret:)` nhận một đoạn VĂN BẢN (không phải chuỗi phím) và trả về
  các `ProofIssue` (vị trí UTF-16, loại, tối đa 3 đề nghị). App gạch chân và người dùng chọn. Vì không tự thay nên
  không cần ngưỡng "thắng rõ ràng"; thứ phải giữ là KHÔNG gạch từ đúng:
  - Từ CÓ DẤU: không gạch nếu có trong bảng tần suất `CommonWords` (≥ `tableFloor` = 100) hoặc người dùng đã gõ nó
    ≥ 2 lần. Từ điển macOS không được hỏi (nó nhận gần như mọi âm tiết đúng cấu trúc: "tiêng", "dúng", "ròi"). Còn
    lại: đề nghị các cách THÊM dấu (`Predictor.candidates`, không đổi chữ cái) ra từ trong bảng, xếp theo cặp từ của
    người dùng → `CommonPairs` với từ TRƯỚC và từ SAU → tần suất chia 10 cho mỗi phím thiếu nhiều hơn ứng viên gần
    nhất ("dúng": đúng trước đứng). Loại `.missingMark` (GÕ NHẦM, app tô đỏ).
  - SAI CHÍNH TẢ (`.spelling`, app tô cam; người dùng yêu cầu 2026-11-25): chữ có dấu, là âm tiết đúng cấu tạo, không
    có trong bảng, và đổi MỘT chỗ theo bảng lỗi thường gặp thì ra từ trong bảng (`Proofreader.mixups`): âm đầu
    (d/gi/r/v, s/x, ch/tr, l/n, c/k, g/gh, ng/ngh, d/nh, h/qu, qu/v), vần (i/y, i/iê, u/uô, ư/ươ, iu/iêu/ưu/ươu,
    ui/uôi/uy, ai/ay/ây, ao/au/âu, ă/â, o/ô, ô/ơ…), âm cuối (n/ng/nh, t/c/ch), thanh (hỏi/ngã, ngã/nặng). Ứng viên
    lẫn âm xếp CHUNG với ứng viên thêm dấu (cặp của người dùng → `CommonPairs` → tần suất); ứng viên đứng đầu thuộc
    loại nào thì chỗ đó mang loại ấy: "việc dới" → với (sai chính tả), "nhiệt dới" → đới (gõ thiếu). Chữ không phải
    âm tiết đúng cấu tạo ("viêt", "đươc", "duojc") luôn là gõ nhầm. Chữ sai chính tả mà trùng một âm tiết có thật
    ("hưu" cho "hươu", "trưng" cho "chưng", "dữ" cho "giữ") KHÔNG bắt được: giới hạn của việc soát theo âm tiết.
    SAI DẤU THANH (`.wrongTone`, gõ nhầm, tô đỏ): cùng điều kiện, thử mọi thanh khác (`otherTones`; "đi vễ nhà" → về,
    "đị" → đi), điểm tần suất chia 10 vì ít chắc hơn; xếp chung với hai loại trên.
    Thêm nhóm lỗi mới thì thêm ca vào `commonMisspellings`. Lối ra cho từ bị gạch nhầm là "Thêm vào từ điển".
  - Từ KHÔNG DẤU là âm tiết đúng cấu tạo ("goc", "nhat", "toi") không bao giờ bị gạch riêng lẻ: người ta vẫn viết
    không dấu, và "goc" có thể là "góc". Từ tiếng Anh (`isEnglish`, `builtinEnglish`) cũng không. Ngoại lệ: chữ không
    dấu kết thúc bằng c/ch/p/t ("viet", "duoc") không phải âm tiết đúng (thanh sắc/nặng là bắt buộc), nên khi đứng
    cạnh một từ CÓ dấu thì bị gạch và được đề nghị thêm dấu ("Tiếng viet" → việt). Không có từ có dấu bên cạnh thì thôi.
  - Chữ không ra từ nào: coi là chuỗi phím, gõ lại qua `Composer.replay` rồi thử gõ đảo phím (`swapped`), trật phím
    dấu CUỐI sang phím kề (`slipped`; `telexSlips` / `vniSlips`, không có "k", nguyên âm, m, n vì chữ teen "bik",
    "hok"; phải có từ bên cạnh ủng hộ ≥ `CommonPairs.floor`), rồi chữ có dấu mà chuỗi phím đó gõ ra ("duojc",
    "tieesng"). Không có đề nghị thì không gạch. VNI: chữ số sau chữ cái thuộc về từ ("tie61gn").
  - LẶP / ĐẢO CHỮ CÁI (`letterSlip`, bộ test `repeatedAndSwappedLetters`; 2026-11-26): chữ không phải âm tiết, không có
    trong bảng, mà bỏ một chữ cái lặp (`.doubledKey`: "mộtt", "đãã", "xemm") hoặc đổi chỗ hai chữ cái liền nhau
    (`.swappedKeys`: "khôgn", "lcú") thì ra từ trong bảng. Làm trên CHỮ đang hiện (khác `swapped`, làm trên chuỗi phím).
    Ứng viên không dấu phải ≥ `plainSlipFloor` = 1000. Với từ không dấu, loại lặp đi TRƯỚC việc thêm dấu ("muaa" là
    "mua", không phải "mâu").
  - TÊN RIÊNG (bộ test `properNamesAreLeftAlone`): từ viết hoa đứng giữa câu, hoặc viết hoa và đứng trước một từ viết
    hoa, không nhận đề nghị loại lẫn âm / đổi thanh ("Huế" không phải "Huệ", "Nguyễn Du", "Sông Hương"). Thiếu dấu,
    lặp, đảo chữ vẫn gạch ("Viêt Nam"). `wrongCompound` bỏ qua từ ≥ `tooCommonToDoubt` (= `veryCommon` 5000): "bánh
    khác" không phải "bánh khách". Đổi lại, lỗi trùng từ có thật bắt được ít hơn (49,8% xuống 45,9% trên `Eval/`).
    Tên viết hoa là âm tiết đúng cấu tạo cũng không nhận đề nghị THÊM DẤU ("anh Diên" không phải "Điên"); họ và địa
    danh thường gặp nằm trong `Proofreader.nameSyllables` (bảng tần suất từ phụ đề thiếu "nguyễn", "huế"…), bộ test
    `namesInRealText`. Đo gạch nhầm trên văn bản thật: `vnkey-tool check-eval --set Eval/vtb.tsv`.
    Còn gạch nhầm: "mài sắt" → sắc, "tậu được" → tạo, "gỏi cuốn" → gọi, "đàn vịt" → việt, "còn đọng" → động.
  - Lỗi gõ đã học đi trước mọi luật trên, kể cả với từ thật ("muôn" → "muốn"): bảng lưu chuỗi phím nên mỗi lần
    soát dựng lại bảng "chữ đang hiện → phím đúng" (`learned`). Số lần để nguyên (`keepTypo`) chặn gạch nhầm.
  - Cụm: cặp không dấu người dùng hay gõ có dấu (`ContextModel.phrase`: ≥ 3 lần, ≥ 2 lần cụm khác, nhiều hơn dạng
    không dấu) thành một `ProofIssue` `.phrase`; hai từ liền nhau cùng bị gạch cũng gộp lại, đề nghị xếp theo cặp.
  - Tiếng Anh (`checkEnglish`): chỉ khi từ điển có đề nghị (`Lexicon.englishGuesses`), từ viết thường, ≥ 3 chữ,
    không cạnh từ tiếng Việt có dấu.
  - Bỏ qua: từ đang gõ dở (chứa hoặc sát con trỏ), ngữ cảnh code / địa chỉ, từ viết hoa toàn bộ, từ trong `skip`
    (từ người dùng bỏ qua, `preferRaw`, `preferVN`).
  - Từ điển từ ghép (`Compounds`, 47.891 từ hai âm tiết + 2.874 từ đơn hiếm; người dùng chọn giữ CẢ bảng cặp, 2026-11-25):
    (1) chữ ngoài bảng tần suất mà tạo thành từ ghép với từ bên cạnh ("bánh chưng") thì không gạch; (2) từ đơn hiếm có
    thật ("quẫy", "tậu", "cốm") chỉ bị gạch khi đề nghị đứng đầu là loại THÊM DẤU và gặp ≥ `rareWordFloor` = 1000 lần
    ("rưng" → rừng, "dúng" → đúng, "ròi" → rồi), hoặc hay đi với từ bên cạnh (cặp ≥ `CommonPairs.floor`, từ ghép, cặp
    của người dùng). Người dùng chọn 2026-11-25 sau khi đo 2.894 từ hiếm bằng `vnkey-tool rare-words`: ngưỡng 1000
    cho mọi loại gạch 1.200 từ thật (lẫn âm, đổi thanh chỉ là phỏng đoán với từ có thật), chỉ loại thêm dấu thì 165;
    (3) ứng viên tạo thành từ ghép với từ bên cạnh được cộng `compoundBonus` vào điểm ngữ liệu; (4) `wrongCompound`: âm
    tiết CÓ trong bảng nhưng đứng sai chỗ ("bánh trưng" → chưng, "dữ gìn" → giữ) bị gạch khi cặp đang viết không phải
    từ ghép, KHÔNG HỀ có trong `CommonPairs`, người dùng chưa từng gõ, và đổi một âm hay lẫn thì ra từ ghép. Lỗi mà kho
    phụ đề cũng mắc nhiều ("sữa chữa", "chia sẽ" có trong bảng cặp) vì thế chưa bắt được. Không đụng i / y.
  - `Proofreader` không an toàn giữa các luồng (dùng chung `Lexicon`, `ContextModel` với `Engine`): gọi ở luồng chính.
  - Tái hiện lỗi soát: `swift run vnkey-tool check [--english] "<văn bản>"`.
- Engine vẫn GHI thói quen gõ để bộ soát lỗi dùng: từ và cặp từ tiếng Việt người dùng tự gõ, kể cả không dấu
  (`ContextModel.record`; quay lại sửa thì `unrecord`), và lỗi gõ quen tay: `Engine.abandoned` chụp chuỗi phím của
  từ ngay trước lần xoá lùi đầu tiên; ở `breakWord`, nếu từ gõ xong chỉ khác nó đúng một phím (`oneKeyApart`) thì
  `recordTypo(sai, fixed: đúng)`. Đủ điều kiện khi đã sửa ≥ 2 lần, ≥ 2 lần cách sửa đứng nhì và nhiều hơn số lần gõ
  rồi để nguyên. Việc này KHÔNG đổi `backspace()`: nó vẫn luôn trả `.pass`. `UsageModel` (VNEngine, thuần
  Foundation) là bảng đếm có giới hạn; app lưu nó qua `UsageStore`.
- Tự học khi gõ lại (`Config.learnFromRetype`): chỉ khi người dùng xoá ĐÚNG từ vừa gõ gần nhất (chưa gõ chữ nào
  khác sau nó, `freshBreak`), xoá HẾT từ đó mà không xoá lan sang chữ đứng trước, rồi gõ lại đúng chuỗi phím
  (phân biệt hoa/thường). Điều kiện lỏng hơn sẽ học nhầm khi người dùng chỉ giữ phím xoá rồi gõ lại. Việc nhớ
  diễn ra TRƯỚC `decide()` trong `breakWord`, nên chính lần gõ lại đã ra dạng mới.
- Lúc NGẮT TỪ, `breakWord` gọi `recomposed()` trước: từ thành nguyên văn vì một phím gõ thừa rồi bị xoá ("ddaayy" xoá
  một chữ) được hiểu lại ("đây"), như khi gõ tiếp một chữ. Vẫn KHÔNG làm gì lúc xoá lùi (bộ test `RetryAtWordBreak`).
- Gõ tắt thông minh (`SmartMacro.swift`, `Config.smartMacros: [tên: nội dung]`, bộ test `SmartMacros`; người dùng chốt
  2026-11-25): bung khi gõ `\tên` rồi ngắt từ, và CHỈ khi dấu `\` đứng ở đầu từ (trước nó là đầu dòng, khoảng trắng,
  dấu mở ngoặc / nháy; `C:\ten`, `a\b` là đường dẫn, không bung). `breakWord` đặt `prefixTyped`, từ kế tiếp
  (`afterPrefix`) luôn nguyên văn; tên có trong bảng thì xoá cả `\` lẫn tên rồi gõ nội dung. Tên chưa định nghĩa thì
  không đụng (`\alpha`, `\n`). Tiền tố `\` được chọn vì ít đụng ứng dụng khác nhất (`@` bật bảng nhắc tên, `/` là lệnh
  của Slack / Notion, `:` là emoji). Không còn gõ tắt đặt sẵn KHÔNG tiền tố (`hnay`…): `vn`, `tphcm` là dòng mẫu của
  bảng thường. Biến `[tên]` trong nội dung (cả hai bảng) thay bằng `SmartMacro.resolve` theo `Engine.now`: ngay, gio,
  thu, thang, nam, ngaydai, homqua, ngaymai, ngay±N, tuan, amlich (lịch Trung Quốc của macOS, có thể lệch lịch Việt Nam
  một ngày); tên engine không biết thì hỏi `Engine.variable` (app trả hoten, clipboard). Gõ tắt không bung trong ngữ
  cảnh code. `Engine.replaced` báo nội dung vừa bung để app quét dải sáng.
- THỬ NGHIỆM `Config.retryOnBackspace` (mặc định TẮT, app chưa bật; bộ test `RetryOnBackspace`): đổi chữ ngay khi xoá
  phím gõ thừa ("ddaayy" xoá một chữ → "đây"), trái với luật phím xoá ở trên. Bật cờ cho cả bộ test (2026-11-25) chỉ
  hỏng hai chỗ: test giữ luật cũ, và việc học khi gõ lại ("test" xoá dần thành "tes" rồi ra "té"). Chỗ thứ hai đã
  chặn bằng `Engine.reopened` (không áp dụng cho từ mở lại bằng phím xoá); phím xoá đang giữ (`held`) không bao giờ
  đổi chữ. CHƯA thử trên ứng dụng thật, nơi luật cũ sinh ra vì màn hình lệch khi phát phím lúc đang xoá.
- Thêm dấu cả câu bằng thuật toán (`Proofreader.restore`, Viterbi trên bảng tần suất / bảng cặp / từ ghép) ĐÃ GỠ
  2026-11-26: người dùng bỏ việc sửa cả câu ngoài Apple Intelligence. Bản cuối ở commit 40d7e2d; đừng thêm lại.
- Sau khi sửa: `./Scripts/test.sh` và `swift run -c release vnkey-tool bench`.
