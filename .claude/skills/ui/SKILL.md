---
name: ui
description: Sửa và cải thiện giao diện của VNKey — menu thanh trạng thái, cửa sổ Cài đặt, nhãn VN/EN cạnh con trỏ, biểu tượng, chuỗi hiển thị. Dùng khi người dùng muốn đổi bố cục, thêm tuỳ chọn, làm giao diện đẹp hơn hoặc báo giao diện bị lệch.
---

# Giao diện VNKey

## Ràng buộc

- **AppKit thuần, không SwiftUI.** Thiếu plugin `SwiftUIMacros` trong Command Line Tools nên
  `@State`, `@AppStorage` không biên dịch được. Đừng thử lại trừ khi người dùng đã cài Xcode.
- **Xem giao diện bằng chế độ chụp của app**, không phải `screencapture` (bị từ chối vì thiếu quyền
  Screen Recording). Xem mục "Xem thử". Giới hạn: chỉ đáng tin ở chế độ sáng, không chụp được menu thanh
  trạng thái lẫn nhãn HUD, và không thấy được hành vi (bấm, kéo, ghi phím tắt). Những thứ đó vẫn phải
  nhờ người dùng xem; nói rõ phần nào đã tự xem, phần nào chưa.
- Chuỗi hiển thị bằng tiếng Việt, ngắn, nói điều người dùng nhận được chứ không nói cơ chế.

## Bản đồ

| Thành phần | Tệp | Ghi chú |
|---|---|---|
| Biểu tượng thanh menu | `Sources/VNKey/StatusIcon.swift` | Ô bo góc tô đặc ở CẢ HAI chế độ, chữ V/E khoét rỗng, canh giữa theo khung bao của nét chữ |
| Menu thanh trạng thái | `Sources/VNKey/main.swift` (`menuNeedsUpdate`) | Chỉ có: cảnh báo (nếu có), Gõ tiếng Việt, Kiểu gõ, Cài đặt…, Thoát |
| Cửa sổ Cài đặt | `Sources/VNKey/Settings.swift` | Thanh thẻ kiểu macOS (`NSTabViewController`, `.toolbar`), cửa sổ tự cao theo từng thẻ |
| Nhãn cạnh con trỏ | `Sources/VNKey/HUD.swift` | `HUDPill` 32×20: nền `controlAccentColor` (màu nhấn người dùng chọn cho macOS), chữ trắng; `NSPanel` không kích hoạt, vị trí lấy qua AX |
| Biểu tượng app | `Resources/AppIcon.svg` → `Scripts/make-icon.swift` → `Resources/AppIcon.icns` | Hình gốc là tệp SVG; script đặt nó vào khuôn 824/1024, cắt bo góc kiểu macOS, cỡ lớn nhất 512 px, nén bằng pngquant + oxipng nếu máy có (`brew install pngquant oxipng`) |
| Khoá cài đặt | `Sources/VNKey/Shared.swift` (`Key`) | Mặc định trong `Key.registered` |

## Cách sắp xếp chức năng

Mỗi thẻ trả lời một câu hỏi của người dùng; thêm tuỳ chọn mới thì đặt theo câu hỏi đó, đừng tạo thẻ mới
cho một hai mục.

| Thẻ | Câu hỏi | Nội dung |
|---|---|---|
| Chung | App chạy thế nào? | Phím tắt, nhãn VN/EN, mở cùng lúc đăng nhập, nhật ký, phiên bản |
| Gõ | Tôi gõ kiểu gì? | Kiểu gõ (Telex/VNI), vị trí dấu thanh, phím w, viết hoa đầu câu, dọn khoảng trắng |
| Việt & Anh | Khi nào thì KHÔNG bỏ dấu? | Tự trả lại từ, đoán ngữ cảnh, sửa đảo phím, ngữ cảnh code, chữ teen, từ đã nhớ |
| Gõ tắt | Gõ ít ra nhiều | Gõ tắt của người dùng, bung viết tắt teen |
| Ứng dụng | Khác nhau theo ứng dụng | Nhớ chế độ theo app, sửa lặp chữ ở ô gợi ý, danh sách bắt đầu ở chế độ Anh |

Menu thanh trạng thái chỉ giữ thứ dùng hằng ngày. Đừng đưa tuỳ chọn bật/tắt vào menu.

## Thêm một tuỳ chọn bật/tắt

1. Thêm khoá vào `Key` và giá trị mặc định vào `Key.registered`.
2. Thêm `toggle("Tên", "Mô tả ngắn", key: Key.tên)` vào một `Card` của đúng thẻ. Tuỳ chọn phụ thuộc
   tuỳ chọn khác: thêm `dependsOn: Key.cha` để nó mờ đi khi cha tắt.
3. Đọc nó trong `AppDelegate.applySettings` (vào `Config` nếu là hành vi engine).
4. Nếu là hành vi engine: thêm trường vào `Config`, thêm test.

Công tắc gắn thẳng vào UserDefaults bằng Cocoa Bindings, không cần viết action.

## Thành phần dựng sẵn trong `Settings.swift`

- `page([...])`: một thẻ; lề 20pt, cao vừa nội dung. `Card`, `NSScrollView` và view có
  `identifier == SettingsController.wide` tự giãn hết chiều ngang.
- `title`, `note`: tiêu đề nhóm và chú thích nhỏ.
- `Card(rows:)`: khung bo góc, tự kẻ đường mảnh giữa các dòng.
- `row(tên, mô tả, điều khiển…)`: tên bên trái, điều khiển bên phải. `toggle(...)` là `row` với `NSSwitch`.
- `ListEditor` (ô văn bản mỗi dòng một mục), `AppList` (bảng ứng dụng), `HotkeyButton`.

Khoảng cách: mọi con số nằm trong `Metrics` (lưới 4pt). Đổi ở đó; đừng viết số lẻ ở nơi dùng.

Chuyển thẻ: nội dung đổi NGAY, không mờ chuyển (`transitionOptions = []`; người dùng đã yêu cầu bỏ hiệu ứng
mờ). Chỉ còn cửa sổ trượt tới chiều cao mới trong 0,22 giây, mép trên đứng yên, bỏ qua khi hệ thống bật
"Giảm chuyển động". Thẻ không được đòi chiều cao tối thiểu (ràng buộc mép dưới ưu tiên thấp), nếu không
cửa sổ không co lại được. Kiểm tra bằng chiều cao các ảnh `settings-N.png`: mỗi thẻ phải cao khác nhau.

Thuật ngữ: Telex/VNI gọi là "Kiểu gõ" ở mọi nơi (không dùng "Bảng gõ").

Quy ước chữ: tên dòng nói điều người dùng nhận được; mô tả một câu, có ví dụ cụ thể (`user, string…`).

## Xem thử

Tự xem bố cục (không cần người dùng, không đụng tới bản đang chạy):

```bash
swift build -c release --product VNKey && .build/release/VNKey --snapshot <thư mục tạm>
```

Sinh `settings-1.png` … `settings-8.png` (từng thẻ Cài đặt), `clipboard.png`, `clipboard-off.png` (bảng clipboard với dữ liệu mẫu), `hud-vn.png`, `hud-en.png` (nhãn cạnh con
trỏ, phóng to 6 lần) và `status-vn.png`, `status-en.png` (biểu tượng thanh menu phóng to; thêm `--dark` để xem trên nền tối). Mở ảnh bằng Read để nhìn. Chế độ này
KHÔNG khởi động event tap, nên chạy song song với bản người dùng đang dùng được. Luôn chạy và xem lại
sau mỗi thay đổi bố cục, trước khi nhờ người dùng.

Cho người dùng xem trên màn hình thật:

```bash
./Scripts/run.sh --settings
```

Biểu tượng app: thay `Resources/AppIcon.svg`, chạy `swift Scripts/make-icon.swift`, xem
`build/AppIcon.iconset/icon_512x512.png`, rồi commit `Resources/AppIcon.icns`.

## Hướng cải thiện đã biết

- "Gõ tắt" và "Từ đã nhớ" vẫn là ô văn bản; có thể nâng lên bảng như `AppList` (giữ định dạng lưu).
- Nhãn HUD rơi về vị trí chuột ở các app không báo vị trí con trỏ (nhiều app Electron).
- Chế độ tối, cỡ chữ lớn và VoiceOver của cửa sổ Cài đặt chưa được ai xem.
- Ảnh chụp không thấy thanh thẻ (nằm trên thanh công cụ của cửa sổ), menu thanh trạng thái, lẫn chuyển
  động đổi thẻ (chỉ thấy trạng thái cuối sau khi chuyển động chạy xong).

## Cửa sổ hướng dẫn cấp quyền

`Sources/VNKey/Onboarding.swift` (`OnboardingController`): tự mở khi khởi động mà chưa có quyền Trợ năng, và từ
mục menu "Cấp quyền Trợ năng…". `update(ready:)` được gọi mỗi 2 giây từ AppDelegate; có quyền thì đổi sang
"Đã sẵn sàng". `--snapshot` chụp cả hai trạng thái (`onboarding-wait.png`, `onboarding-ready.png`).

## Điều cần nhớ khi thêm điều khiển

- Điều khiển dựng tay (không qua `toggle`) phải tự `setAccessibilityLabel`.
- Thẻ có nội dung đổi theo dữ liệu (dòng trạng thái của ô gõ tắt) thì giữ chiều cao cố định, vì cửa sổ chỉ
  tính lại chiều cao khi đổi thẻ.
- Nhãn VN/EN hiện khi đổi chế độ bằng phím tắt, bằng menu, và khi chế độ tự đổi lúc chuyển ứng dụng.
- `--snapshot` không được tạo hay ẩn `NSStatusItem`: trạng thái ẩn bị lưu vào cài đặt (`NSStatusItem VisibleCC
  Item-0 = 0`) và biểu tượng của bản đang chạy biến mất. Nếu gặp lại: thoát app, `defaults delete local.vnkey
  "NSStatusItem VisibleCC Item-0"`, mở lại.

## Bảng soạn danh sách

`Sources/VNKey/EntryTable.swift` (`EntryTable`): bảng sửa ngay trong ô, nút +/−, phím Delete, ô tìm kiếm. Dùng cho
thẻ "Gõ tắt" (hai cột chữ) và bảng "đã nhớ" (chuỗi phím + cột lựa chọn Phím gốc / Tiếng Việt). Bảng "đã nhớ" KHÔNG còn
là một thẻ (người dùng yêu cầu gộp và tinh gọn, 2026-11-24): nó là một sheet mở từ dòng "Những gì VNKey đã nhớ" ở thẻ
Tự sửa (`SettingsController.showMemory`, `memoryWindow`), có nút chuyển giữa "Từ đã nhớ" và "Đã học từ cách gõ". Danh
sách sau là bảng chỉ-đọc (`readOnly: true`: chỉ xem và xoá dòng) gồm lỗi gõ đã học (`UsageModel.learnedTypos()`) rồi
cặp từ (`learnedPairs()`) — chỉ những mục đã đủ điều kiện sửa; xoá dòng gọi `forgetTypo` / `forget`. Thẻ Tự sửa đặt ví
dụ ngay trong tên dòng ("Gõ đảo hai phím: tieegns → tiếng") để khỏi cần dòng mô tả. `--snapshot` chụp sheet này ra
`settings-memory-words.png` và `settings-memory-learned.png`. Định dạng lưu
trong UserDefaults không đổi (`macros`: từ điển; `preferRaw` / `preferVN`: hai mảng). Luật hợp lệ của từng dòng
nằm ở `ListFormat.macros(fromRows:)` và `ListFormat.learned(fromRows:)` trong VNKeyCore, có test.

Cửa sổ Cài đặt (rộng 580pt) có 8 thẻ: Chung, Gõ, Việt & Anh, Tự sửa, Gõ tắt, Ứng dụng, Bảng tạm, Giới thiệu (Giới thiệu luôn ở cuối). Thẻ nào dài quá ~500pt
thì tách (người dùng đã phàn nàn thẻ Việt & Anh dài 650pt). Kiểu gõ chỉ có Telex và VNI; hai
công tắc của Telex (w đứng riêng, phím [ ]) nằm ngay dưới và mờ đi khi chọn VNI.

- Khi màn hình ngủ hoặc bị khoá, macOS KHÔNG chạy chuyển động đổi khung cửa sổ. `--snapshot` vì thế chọn thẻ
  không qua chuyển động (`selectTab(_, animated: false)`); đừng kết luận "cửa sổ không co giãn" từ một lần chạy
  lúc màn hình đang khoá.


## Nhãn cạnh con trỏ (HUD)

- Hiện PHÍA TRÊN con trỏ soạn thảo (nhãn báo bộ gõ của macOS hiện phía dưới; người dùng yêu cầu tránh chồng nhau),
  lệch trái 14pt, kiểu giống hệt nhãn của macOS (người dùng đã gửi ảnh mẫu): viên thuốc nền màu nhấn, chữ trắng
  đậm, không viền, không bóng; nội dung "VN - Telex" / "VN - VNI" / "EN", giữ 1,2 giây.
- CHỈ hiện khi đang ở trong ô gõ được chữ (vai trò ô nhập, hoặc vùng soạn thảo của trang web); không còn rơi về
  khung cửa sổ hay vị trí chuột.
- Tìm vị trí theo thứ tự: vùng chọn → ký tự trước con trỏ → text marker (web, Electron) → khung ô → khung cửa sổ →
  chuột. Ứng dụng Electron chỉ trả lời sau khi được đặt cờ `AXManualAccessibility` (`HUD.focusedElement`).
  Dòng log `HUD vị trí=…` cho biết cách nào đã dùng.

## Giới thiệu và cập nhật

- Thẻ "Giới thiệu": tên, phiên bản, nhà phát triển (`AppInfo` trong `Sources/VNKey/Updater.swift`) và dòng trạng thái
  cập nhật.
- Kiểm tra bản mới: `Updater` hỏi GitHub Releases của `AppInfo.repository` (người dùng đã xác nhận tên kho), mỗi
  ngày một lần nếu bật, hoặc khi bấm nút. Chỉ báo và mở trang tải; KHÔNG tự tải hay cài (app ký bằng chứng chỉ tự
  tạo). Logic thuần ở `UpdateCheck` (VNKeyCore) có test; yêu cầu mạng không được chạy trong test.
- Phiên bản của app nằm trong `Scripts/build-app.sh` (`CFBundleShortVersionString`); so sánh với thẻ phát hành.

## Hai ngôn ngữ, cập nhật, nhật ký thay đổi

- Giao diện song ngữ qua `L(vi, en)`; ngôn ngữ chọn ở Cài đặt › Chung (`Key.language`: auto/vi/en). Đổi ngôn ngữ thì
  AppDelegate dựng lại cửa sổ Cài đặt. Chụp thử bản tiếng Anh: `VNKey --snapshot <thư mục> --en`. Tên thẻ tiếng Anh
  phải ngắn (8 thẻ trên thanh công cụ).
- Tự cập nhật (`Updater.installUpdate`, `Installer`): tải ZIP của bản phát hành từ github.com, kiểm tra chữ ký phải
  do Apple cấp và cùng Team ID với bản đang chạy (`UpdateCheck.mayInstall`), cất bản cũ rồi mới đưa bản mới vào, mở
  lại. Bản dựng trên máy (không có Team ID) không bao giờ tự cài. CHƯA kiểm chứng trọn vẹn trên bản phát hành thật.
- Cửa sổ "Có gì mới" (`ChangelogWindow`) đọc `CHANGELOG.md` đóng gói kèm app (`build-app.sh` chép vào Resources).

