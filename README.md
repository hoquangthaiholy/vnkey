# VNKey

Bộ gõ tiếng Việt cho macOS, viết thuần Swift, chạy trên thanh menu. VNKey theo dõi thứ tự phím bạn gõ để gõ xen kẽ
Việt – Anh mà không phải chuyển chế độ, gạch chân từ nghi gõ sai kèm đề nghị sửa, và học dần từ cách bạn gõ.

*A Vietnamese input method for macOS written in pure Swift. It tracks your keystroke order so you can mix Vietnamese
and English without switching modes, underlines likely typos with suggestions, and learns from how you type.*

- Trang web: <https://hoquangthaiholy.github.io/vnkey/>
- Tải về: [Releases](https://github.com/hoquangthaiholy/vnkey/releases/latest)
- Thay đổi qua các phiên bản: [CHANGELOG.md](CHANGELOG.md)

> **Bản 2.0 là bản viết lại hoàn toàn và chỉ dành cho macOS.** Bản 1.x đa nền tảng (Tauri, Rust, Svelte; có
> Windows và Linux) không còn được phát triển. Mã nguồn 1.x nằm ở thẻ [`1.0.2`](https://github.com/hoquangthaiholy/vnkey/tree/1.0.2),
> và các bản cài cũ vẫn tải được ở trang Releases.

## Tính năng

- **Gõ xen kẽ Việt – Anh:** `user`, `string`, `data` giữa câu tiếng Việt được trả lại đúng như đã gõ; giữ nguyên
  trong ngữ cảnh code (sau `@ # / . _`, chữ số).
- **Soát lỗi, không tự sửa:** từ nghi gõ sai được gạch chân ngay trong ô đang nhập: thiếu dấu (`viêt`), trật phím
  dấu (`veeg` thay cho `veef`), gõ đảo phím (`tieegns`), và cả tiếng Anh nếu bạn bật. Rê chuột lên đó (hoặc đưa con trỏ vào bằng `←` `→`) để chọn đề
  nghị (xếp theo từ đứng cạnh: `tiếng viêt` → `việt`, `bài viêt` → `viết`) hoặc thêm từ vào từ điển của bạn. VNKey không tự thay chữ của bạn. Hiện
  chạy trong ứng dụng macOS chuẩn (TextEdit, Ghi chú, Mail), chưa chạy trên trang web.
- **Trợ lý cho câu và đoạn văn (✦):** để chuột dừng trên một câu rồi vào nút ✦ để thêm dấu và sửa chính tả cả câu.
  Trên macOS 26 trở lên có Apple Intelligence còn có cải tiến, viết lại, rút gọn, mở rộng, dịch Việt ↔ Anh và viết thành
  câu từ vài ý, bằng mô hình ngôn ngữ chạy ngay trên máy. Bạn xem kết quả rồi mới thay.
- **Học từ cách bạn gõ:** nhớ từ bạn muốn giữ nguyên và các cặp từ bạn hay gõ; gõ `lầm lỗi` vài lần thì `lam loi`
  không dấu sẽ được đề nghị sửa thành `lầm lỗi`. Sửa cùng một lỗi hai lần (`goc` thành `gõ`) thì lần sau VNKey gạch
  chân và đề nghị. Dữ liệu chỉ nằm trên máy, xem và xoá được trong Cài đặt.
- **Gõ dấu tự do:** `dduwowcj`, `duojwcd` đều ra `được`.
- **Không có vùng soạn trước, không lặp chữ:** sửa chữ bằng kỹ thuật xoá lùi; có xử lý riêng cho thanh địa chỉ trình duyệt
  và Spotlight.
- **Bảng tạm:** `⌃⌥V` mở lịch sử clipboard ngay cạnh chỗ đang gõ (văn bản, đường dẫn, ảnh, tệp); gõ để tìm, `↩` để
  dán. Văn bản TCVN3, VNI Windows, VIQR tự dán thành Unicode, và dán ngược lại sang các bảng mã đó khi cần. Mặc định
  tắt; có thể đồng bộ văn bản qua iCloud Drive.
- **Telex và VNI**, gõ tắt dạng bảng, nhớ chế độ theo ứng dụng, tạm ngưng khi dùng bộ gõ khác của macOS.
- **Giao diện tiếng Việt và tiếng Anh**; **tự cập nhật** qua GitHub Releases (có kiểm tra chữ ký, chỉ cài khi bạn
  bấm) và xem nhật ký thay đổi ngay trong app.

## Cài đặt

1. Tải VNKey ở trang [Releases](https://github.com/hoquangthaiholy/vnkey/releases/latest), kéo vào thư mục Ứng dụng
   rồi mở. Có hai bản: `VNKey_<phiên bản>_universal.dmg` chạy trên mọi máy Mac (Apple silicon và Intel), và
   `VNKey_<phiên bản>_arm64.dmg` nhẹ hơn, chỉ dành cho máy Apple silicon.
2. Làm theo cửa sổ hướng dẫn để bật quyền **Trợ năng** (Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Trợ năng).
   VNKey cần quyền này để đọc phím bạn gõ và gửi lại chữ đã có dấu.
3. Biểu tượng **V** / **E** trên thanh menu cho biết đang gõ tiếng Việt hay tiếng Anh. Nhấn `⌃⇧` rồi thả để đổi;
   `⌃⌥Z` để đổi từ vừa gõ giữa phím gốc và tiếng Việt.

Yêu cầu: macOS 12 trở lên, máy Apple silicon hoặc Intel.

## Quyền riêng tư

- VNKey không gửi gì về việc bạn gõ đi đâu cả. Nó chỉ lên mạng để hỏi GitHub số phiên bản mới nhất (tắt được ở thẻ
  Giới thiệu) và tải bản mới khi bạn bấm cập nhật.
- Trên máy bạn, nó lưu: cài đặt, bảng gõ tắt, các từ đã nhớ, và một bảng đếm từ cùng cặp từ bạn hay gõ (không có
  câu) tại `~/Library/Application Support/VNKey/usage.json`.
- Để soát lỗi, VNKey đọc nội dung ô bạn đang nhập qua quyền Trợ năng. Việc này chỉ diễn ra trên máy, không lưu lại,
  không đọc ô mật khẩu, và tắt được ở Cài đặt › Chính tả. "Sửa cả câu" đưa câu đó cho mô hình ngôn ngữ của macOS chạy
  trên chính máy bạn; câu không được gửi đi đâu.
- Nhật ký gỡ lỗi (`~/Library/Logs/VNKey.log`) lưu cả nội dung gõ và **mặc định tắt**; chỉ bật khi cần báo lỗi.

## Dựng từ mã nguồn

Chỉ cần Command Line Tools của Xcode (không cần Xcode).

| Việc | Lệnh |
|---|---|
| Chạy test | `./Scripts/test.sh` |
| Đóng gói `build/VNKey.app` | `./Scripts/build-app.sh` |
| Đóng gói rồi mở lại app | `./Scripts/run.sh` |
| Gõ thử một chuỗi phím qua engine | `swift run vnkey-tool type --trace "tooi ddang"` |
| Đo hiệu năng engine | `swift run -c release vnkey-tool bench` |

Bố cục mã: `Sources/VNEngine` (engine gõ, không phụ thuộc hệ thống), `Sources/VNKeyCore` (logic của app, có test),
`Sources/VNKey` (app thanh menu bằng AppKit), `Sources/VNTool` (công cụ dòng lệnh), `Web` (trang web).

Bản dựng trên máy được ký bằng chứng chỉ tự ký "VNKey Dev" nếu có (để giữ quyền Trợ năng qua các lần dựng), không
thì ký ad-hoc. Bản phát hành do workflow [`release-macos.yml`](.github/workflows/release-macos.yml) dựng, ký bằng
Developer ID và công chứng với Apple.

## Ủng hộ

VNKey miễn phí và mã nguồn mở. Nếu thấy hữu ích, bạn có thể ủng hộ qua [PayPal](https://paypal.me/hqthai) hoặc mã
MoMo trên [trang web](https://hoquangthaiholy.github.io/vnkey/#donation).

## Dữ liệu

Bảng tần suất âm tiết dùng để đề nghị sửa từ thiếu dấu (`Sources/VNEngine/CommonWordsData.swift`) dẫn xuất từ danh sách
tiếng Việt của [FrequencyWords](https://github.com/hermitdave/FrequencyWords) (Hermit Dave), đếm trên kho phụ đề
OpenSubtitles 2018, giấy phép [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). VNKey chỉ giữ các
âm tiết tiếng Việt đúng chính tả, gộp các cách đặt dấu thanh, và bỏ mục dưới 100 lần.

Bảng cặp âm tiết dùng để xếp đề nghị theo từ đứng cạnh (`Sources/VNEngine/CommonPairsData.swift`) được đếm trực tiếp trên
kho phụ đề tiếng Việt [OpenSubtitles 2018](https://opus.nlpl.eu/OpenSubtitles/corpus/version/OpenSubtitles) do dự án
OPUS phát hành, gốc từ [opensubtitles.org](http://www.opensubtitles.org/) (P. Lison và J. Tiedemann, “OpenSubtitles2016:
Extracting Large Parallel Corpora from Movie and TV Subtitles”, LREC 2016). VNKey chỉ giữ số đếm của các cặp âm tiết
đứng liền nhau xuất hiện từ 20 lần trở lên, không chứa câu thoại nào.

Từ điển từ ghép dùng để nhận ra từ hiếm có thật và lỗi chính tả trong từ ghép (`Sources/VNEngine/CompoundsData.swift`)
dẫn xuất từ danh sách từ tiếng Việt Viet74K của Hồ Ngọc Đức (Free Vietnamese Dictionary Project), giấy phép GNU General
Public License, lấy từ bản sao [duyet/vietnamese-wordlist](https://github.com/duyet/vietnamese-wordlist). VNKey chỉ giữ các
mục một và hai âm tiết đúng chính tả, bỏ viết hoa, và nén lại.

## Giấy phép

[GPL-3.0](LICENSE). © 2026 Hồ Quang Thái.
