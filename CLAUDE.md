# VNKey

Bộ gõ tiếng Việt cho macOS (kiểu OpenKey): app thanh menu chặn phím toàn hệ thống bằng CGEventTap,
đưa qua engine, rồi phát lại "xoá lùi + văn bản". Ưu tiên: gõ xen kẽ Việt/Anh/teen, khôi phục từ
gõ sai dựa trên thứ tự phím, và trải nghiệm gõ. VNKey KHÔNG tự sửa chữ (trừ trả lại từ tiếng Anh): từ nghi gõ sai
được gạch chân trong ô đang nhập, rê chuột lên (hoặc đưa con trỏ vào bằng ← →) thì có bảng đề nghị (kiểu Grammarly).

Giao tiếp với người dùng, chú thích trong mã và commit message bằng tiếng Việt. Chuỗi giao diện có HAI bản: viết
`L("tiếng Việt", "English")` ngay tại chỗ dùng (xem `Shared.swift`); thêm chuỗi mới thì phải có cả hai. Nhật ký
(`Log.write`) chỉ tiếng Việt.

## Lệnh

| Việc | Lệnh |
|---|---|
| Test engine | `./Scripts/test.sh` (tự thử lại khi plugin macro lỗi) |
| Build + mở lại app | `./Scripts/run.sh` (thêm `--settings` để mở cửa sổ Cài đặt) |
| Chỉ đóng gói | `./Scripts/build-app.sh` → `build/VNKey.app` |
| Gõ lại một chuỗi phím | `swift run vnkey-tool type --trace "tooi ddang"` (`<` = Backspace, `~` = đổi từ) |
| Chuyển bảng mã một đoạn văn bản | `swift run vnkey-tool convert --to vni "Tiếng Việt"` (thiếu `--from` thì tự đoán) |
| Soát lỗi một đoạn văn bản | `swift run vnkey-tool check "tôi veeg nhà"` (thêm `--english` để soát cả tiếng Anh) |
| Thử AI sửa cả câu (mô hình trên máy của macOS) | `swift run -c release vnkey-tool fix-sentence` (không có câu thì chạy 20 câu mẫu) |
| Đo hiệu năng engine | `swift run -c release vnkey-tool bench` |
| Xem nhật ký | `tail -50 ~/Library/Logs/VNKey.log` |

## Kiến trúc

- `Sources/VNEngine/` — engine thuần Swift, không đụng tới hệ thống.
  - `Syllable.swift`: luật âm tiết (âm đầu, vần, âm cuối, thanh); `isValid` và `isValidPrefix`.
  - `Composer.swift`: trạng thái của MỘT từ. Giữ chuỗi phím gốc `raw` và `owner` (phím nào tạo chữ nào).
  - `Engine.swift`: ranh giới từ, lịch sử, quyết định khôi phục, học từ, ngữ cảnh. Trả về `Output`. Không đoán,
    không tự sửa.
  - `Proofreader.swift`: soát một đoạn văn bản, trả về các chỗ nghi sai (`ProofIssue`: vị trí UTF-16, loại, đề
    nghị): thiếu dấu, trật phím dấu, gõ đảo phím, lỗi gõ đã học, cụm từ, tiếng Anh.
  - `Predictor.swift`, `CommonWords.swift`, `UsageModel.swift`: nguồn cho bộ soát lỗi (ứng viên thêm dấu, bảng tần
    suất âm tiết, bảng đếm thói quen gõ của người dùng). `CommonWordsData.swift` là tệp SINH TỰ ĐỘNG từ danh sách
    FrequencyWords (OpenSubtitles 2018, CC BY-SA 4.0): đừng sửa tay; cách sinh lại ghi ở đầu tệp
    (`vnkey-tool syllables`). Giữ dòng ghi nguồn ở đầu tệp và trong README.
  - `CommonPairs.swift`: số lần hai âm tiết đi liền nhau, để xếp đề nghị theo từ bên cạnh. `CommonPairsData.swift` cũng
    SINH TỰ ĐỘNG (kho phụ đề OpenSubtitles 2018 trên OPUS, `vnkey-tool pairs`) và đánh số âm tiết theo thứ tự của
    `CommonWordsData.swift`: sinh lại tệp kia thì phải sinh lại tệp này. Giữ dòng ghi nguồn ở đầu tệp và README.
  - `Compounds.swift`: từ điển từ ghép hai âm tiết và từ đơn hiếm (danh sách Viet74K của Hồ Ngọc Đức, GNU GPL).
    `CompoundsData.swift` SINH TỰ ĐỘNG (`vnkey-tool compounds`), đánh số âm tiết tiếp theo `CommonWordsData.swift`:
    sinh lại tệp kia thì phải sinh lại tệp này. Giữ dòng ghi nguồn ở đầu tệp và README.
  - `Charset.swift`: chuyển giữa Unicode dựng sẵn / tổ hợp, TCVN3, VNI Windows, VIQR; `detect` đoán bảng mã cũ
    bằng cách giải mã thử rồi kiểm âm tiết; `stripMarks` bỏ dấu. Bảng tra sinh từ `Letter.glyphs`.
  - `SystemLexicon.swift`: từ điển `en`/`vi` của macOS qua NSSpellChecker (tệp duy nhất dùng AppKit).
- `Sources/VNKey/` — app: `KeyTap` (event tap, gửi phím), `main` (AppDelegate, menu), `Settings`
  (cửa sổ cài đặt), `Onboarding` (hướng dẫn cấp quyền Trợ năng), `HUD` (nhãn VN/EN cạnh con trỏ),
  `Proofing` (đọc ô đang nhập qua Trợ năng, gạch chân chỗ nghi sai, bảng đề nghị, thay chữ),
  `Updater` (kiểm tra bản mới trên GitHub Releases), `Shared` (khoá UserDefaults).
  Clipboard: `ClipboardWatcher` (hỏi `changeCount` mỗi 0,5 giây), `ClipboardStore` (lưu lịch sử, ghi lên pasteboard
  để dán), `ClipboardPanel` (bảng nổi cạnh con trỏ + `ClipboardController` nối các phần), `ClipboardSync` (đọc/ghi
  thư mục iCloud Drive).
- `Sources/VNKeyCore/` — logic thuần của app, test được: `SendPlanner` (kế hoạch gửi phím theo ứng dụng,
  xử lý phím xoá lùi của người dùng), `classifyKey`, `Hotkey`, `ModifierTracker`, `AppMode`, `ListFormat`.
  `KeyTap` chỉ còn việc đọc sự kiện, hỏi Accessibility và phát phím theo kế hoạch.
  `Clipboard.swift`: `ClipItem` (id = mã băm nội dung), `ClipHistory`, `ClipPolicy` (bỏ qua nội dung riêng tư),
  `ClipSearch`, `ClipSync.reconcile` (luật hoà trộn khi đồng bộ). `Markdown.swift`: `HTMLMarkdown.convert` dịch HTML
  trên clipboard về Markdown (bộ đọc HTML tự viết, dễ dãi với HTML hỏng).
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
4. **Nhật ký chứa nguyên văn nội dung gõ và mặc định TẮT.** Cần log để chẩn đoán thì nhờ người dùng bật ở
   Cài đặt › Chung › "Ghi nhật ký gỡ lỗi" rồi thử lại. Chỉ đọc đoạn cần thiết quanh thời điểm lỗi, không dán
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

- Bảng clipboard là `NSPanel` kiểu `.nonactivatingPanel` nhận phím mà không kéo VNKey ra trước; dán bằng cách ghi
  pasteboard, đóng bảng rồi phát ⌘V (`KeyTap.postPaste`, mã phím 9 = "V" trên QWERTY). Vị trí con trỏ phải hỏi
  (`HUD.typingAnchor`) TRƯỚC khi bảng nhận tiêu điểm. Những việc này chưa được kiểm chứng tự động.
- Lịch sử clipboard (`~/Library/Application Support/VNKey/clipboard/`) và thư mục đồng bộ
  (`iCloud Drive/VNKey/items/`) chứa nguyên văn thứ người dùng đã sao chép: riêng tư như nhật ký, không đọc ra,
  không dán vào câu trả lời. `Log.write` cho clipboard chỉ ghi loại và độ dài. Thử đồng bộ thì trỏ khoá ẩn
  `clipboardSyncFolder` sang thư mục tạm. Đồng bộ qua iCloud thật chưa được kiểm chứng.
- Soát lỗi (`Proofing.swift`) đọc chữ của ô đang nhập qua Trợ năng mỗi 0,15–0,6 giây ở hàng đợi nền (không nằm
  trong callback của tap), không bao giờ đọc ô mật khẩu, không lưu và không ghi chữ vào nhật ký (dòng `PROOF` chỉ có
  số lượng, loại, thời gian). Chỉ chạy với ứng dụng trả lời `AXBoundsForRange` theo số ký tự (AppKit); trang web và
  Electron chưa làm. Thay chữ bằng `AXSelectedText`. TOÀN BỘ phần này chưa được kiểm chứng trên ứng dụng thật.
- Chuyển động (`Motion.swift`: thời lượng, đường cong, tôn trọng "Giảm chuyển động") không kiểm được bằng test hay
  `--snapshot`: nét gạch trượt ra, dải sáng khi chữ được thay (`Proofing.pulse`), bảng nổi phóng nhẹ lúc hiện. Nét gạch
  ẩn khi cửa sổ chứa ô nhập dời / đổi cỡ (`AXObserver` + so khung mỗi nhịp). Tất cả CHƯA được kiểm chứng trên app thật.
- Bảng AI cho câu và đoạn văn (`AIPanel` trong `Proofing.swift`, `SentenceFix.swift`, công tắc `proofreadSentence`),
  RIÊNG với bảng đề nghị cho từ. Mở bằng nút ✦ (`AIChip`) hiện ra khi chuột dừng 0,45 giây trên một câu (hỏi ứng dụng
  `AXRangeForPosition`), hoặc biểu tượng ✦ trong bảng từ. Bảng được ghim; có thẻ theo `SentenceTask` (fix, improve,
  rewrite, shorten, expand, translate Việt ↔ Anh, compose = viết thành câu từ vài ý), hai nút phạm vi (câu / đoạn),
  nút thử lại (`fresh`: bỏ bộ đệm, cho mô hình chọn từ ngẫu nhiên hơn), và "Dùng". Không tự thay.
  - Có Apple Intelligence (framework Foundation Models: macOS 26+, chip Apple; liên kết yếu nên app vẫn chạy trên
    macOS 12): mọi việc do mô hình TRÊN MÁY làm. Chỉ `fix` qua `SentenceFilter.merge` (giữ dấu câu, hoa thường, từ tiếng
    Anh của người gõ; mô hình tự thêm dấu chấm, viết hoa và DỊCH tiếng Anh). Các việc khác lấy nguyên câu mô hình viết,
    chất lượng thất thường ("mở rộng" hay thêm ý). Chỉ dẫn và lời nhắn theo ngôn ngữ của câu (`SentenceTask.prompt`).
  - Không có mô hình: chỉ còn thẻ `fix`, làm bằng `Proofreader.restore` (Viterbi trên bảng tần suất, bảng cặp, từ
    ghép; khoảng 1 ms mỗi câu), không có nút thử lại.
  - Đo 2026-11-25 trên M4 bằng `vnkey-tool fix-sentence` (20 câu mẫu, do chính người viết mã chọn và đã dùng để chỉnh
    trọng số, nên con số lạc quan): mô hình + lọc 19/20, 0,3–0,4 giây mỗi câu; `--local` 18/20. `--task <việc>` thử các
    việc khác. Nhật ký `SENTENCE` chỉ có độ dài và thời gian. Trong ứng dụng thật TẤT CẢ chưa được kiểm chứng.
- Thói quen gõ (bảng đếm từ và cặp từ, không có câu) lưu ở `~/Library/Application Support/VNKey/usage.json`.
  Coi nó riêng tư như nhật ký: không đọc ra, không dán vào câu trả lời.

## Commit

Tiêu đề tiếng Việt, ngắn, nói thay đổi gì. Chỉ commit khi người dùng yêu cầu. Chạy `./Scripts/test.sh`
trước khi commit thay đổi trong `Sources/VNEngine/`.
