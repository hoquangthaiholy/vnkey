
# [VNKey](http://vn-key.org)
### [Download bản mới nhất](https://github.com/tuyenvm/VNKey/releases)
[![GitHub release](https://img.shields.io/github/v/release/tuyenvm/VNKey.svg)](https://github.com/tuyenvm/VNKey/releases/latest)

### Open source Vietnamese Input App for macOS - Bộ gõ tiếng Việt nguồn mở cho macOS.
Bộ gõ tiếng Việt mới cho macOS, sử dụng kỹ thuật `Backspace`. Loại bỏ lỗi gạch chân khó chịu ở bộ gõ mặc định. Hoàn toàn miễn phí và là nguồn mở, luôn cập nhật và phát triển.

### Mã nguồn của ứng dụng được mở công khai, minh bạch dưới giấy phép GPL. Điều này nghĩa là bạn hoàn toàn có thể tải mã nguồn về tự build, cải tiến theo mục đích của bạn. Nếu bạn tái phân phối bản cải tiến của bạn, thì nó cũng phải là mã nguồn mở và thông báo bản gốc là VNKey.

### Lưu ý, khi sử dụng VNKey, bạn nên tắt hẳn bộ gõ khác vì 2 chương trình bộ gõ sẽ xung đột nhau, dẫn đến thao tác không chính xác.

![Giao diện](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/vnkey-main-control.png "Main UI")
![Giao diện](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/vnkey-main-control-2.png "Main UI")
![Giao diện](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/vnkey-main-control-3.png "Main UI")
![Menu](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/vnkey-small-control.png "Menu bar")
![Gõ tắt](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/vnkey-macro.png "Macro")
![Chuyển mã](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/vnkey-convert-tool.png "ConvertTool")

## Hỗ trợ kiểu gõ
- Telex
- VNI
- Simple Telex

## Bảng mã thông dụng:
- Unicode (Unicode dựng sẵn).
- TCVN3 (ABC).
- VNI Windows.
- Unicode Compound (Unicode tổ hợp).
- Vietnamese Locale CP 1258.
- ...

## Tính năng:
- **Modern orthography** (On/Off) - Đặt dấu oà, uý thay vì òa, úy.
- **Quick Telex** (On/Off) - Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th).
- **Grammar check** (On/Off) - Kiểm tra ngữ pháp.
- **Spelling check** (On/Off) - Kiểm tra chính tả.
- **Restore key if invalid word** (on/off) - Phục hồi phím với từ sai.
- **Run on startup** (On/Off) - Chạy cùng macOS.
- **Gray menu bar icon** (On/Off) - Biểu tượng xám trên thanh menu phù hợp với chế độ Dark mode.
- **Switch input mode by shortcut key** - Đổi chế độ gõ bằng phím tắt tùy chọn.
- **Autocorrect fixed** (On/Off) - Sửa lỗi autocorrect trên trình duyệt như Chrome, Safari, Firefox, Microsoft Excel.
- **Underline issue fixed on macOS** (On/Off) - Sửa lỗi gạch chân trên macOS.
- **Tạm tắt kiểm tra chính tả bằng phím Ctrl** (On/Off) (Bản 1.5 về sau).
- **Tạm tắt VNKey bằng phím Cmd/Alt** (On/Off) (Bản 2.0.1 về sau).
- **Cho phép dùng f z w j làm phụ âm đầu** (On/Off) (Bản 1.5 về sau).
- **Gõ tắt phụ âm đầu: f->ph, j->gi, w->qu** (On/Off) (Bản 1.6 về sau).
- **Gõ tắt phụ âm cuối: g->ng, h->nh, k->ch** (On/Off) (Bản 1.6 về sau).
- **Hiện biểu tượng trên thanh Dock** (On/Off) (Bản 2.0.1 về sau). Bấm vào icon trên thanh Dock sẽ mở nhanh Bảng điều khiển.
- **Macro** - Tính năng gõ tắt vô cùng tiện lợi. Gõ tắt của macOS chỉ hỗ trợ 20 ký tự, còn VNKey không giới hạn ký tự.
- **Chuyển chế độ thông minh:** (On/Off) (Bản 1.2 về sau) - Bạn đang dùng chế độ gõ Tiếng Việt trên ứng dụng A, bạn chuyển qua ứng dụng B trước đó bạn dùng chế độ gõ Tiếng Anh, VNKey sẽ tự động chuyển qua chế độ gõ Tiếng Anh cho bạn, khi bạn quay lại ứng dụng A, VNKey tất nhiên sẽ chuyển lại chế độ gõ tiếng Việt, rất cơ động.
- **Viết Hoa chữ cái đầu câu** (On/Off) (Bản 1.2 về sau) - Khi gõ văn bản dài, đôi khi bạn quên ghi hoa chữ cái đầu câu khi kết thúc một câu hoặc khi xuống hàng, tính năng này sẽ tự ghi hoa chữ cái đầu câu cho bạn, thật tuyệt vời.
- **Chế độ “Gửi từng phím”:** (On/Off) (Bản 1.1 về sau) mặc định dùng kỹ thuật mới gửi dữ liệu 1 lần thay vì gửi nhiều lần cho chuỗi ký tự, nên nếu có ứng dụng nào không tương thích, hãy bật tính năng này lên, mặc định thì nên tắt vì kỹ thuật mới sẽ chạy nhanh hơn.
- **Cập nhật tự động:** (Bản 1.3 về sau) tính năng hỗ trợ cập nhật phiên bản VNKey mới nhất mỗi khi mở VNKey hoặc tự check trong phần mục Giới thiệu.
- **Công cụ chuyển mã:** (Bản 1.4 về sau) hỗ trợ chuyển mã qua lại văn bản, thích hợp cho việc chuyển đổi văn bản cũ viết bằng VNI, TCVN3 qua Unicode,... Hỗ trợ cấu hình phím tắt chuyển mã nhanh, bảng cấu hình tùy chọn chuyển mã.
- **Tự ghi nhớ bảng mã theo ứng dụng:** (Bản 2.0.1 về sau) Phù hợp cho các bạn dùng Photoshop, CAD,... với các bảng mã VNI, TCVN3. VNKey tự ghi nhớ ứng dụng nào dùng bảng mã nào để lần sau sử dụng Photoshop, CAD,... VNKey có thể tự chuyển sang bảng mã đó.
- ...


[Changelog](https://github.com/tuyenvm/VNKey/blob/master/CHANGELOG.md)

## Cài đặt:
**Cài đặt thủ công:**  
Tải bản VNKey mới nhất từ [đây](https://github.com/tuyenvm/VNKey/releases/latest), mở file `dmg` ra rồi kéo thả `VNKey.app` vào thư mục `Application`.

**Cài bằng Homebrew:** (by nhymxu)  
Nếu chưa cài Homebrew, mở terminal, nhập:
```
$ /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

Kiểm tra phiên bản VNKey:
```
$ brew info --cask vnkey
```
Gõ lệnh sau để homebrew tự cài VNKey cho bạn:
```
$ brew install --cask vnkey
```

Để update phiên bản mới nhất của VNKey
```
$ brew upgrade --cask vnkey
```

## Note - Lưu ý:
VNKey cần cấp quyền, vào *System Preferences -> Security & Privacy -> Accessibility*, kích hoạt `VNKey.app`. **Không tắt nó khi đang dùng VNKey**.
![Guide](https://raw.githubusercontent.com/tuyenvm/tuyenvm.github.io/master/images/vnkey-guide.png "Accessibility").

## Tự build VNKey trên macOS

VNKey hiện dùng Tauri cho toàn bộ bảng điều khiển. Xcode project cũ trong
`Sources/VNKey/macOS` đã được loại bỏ để dọn dẹp mã nguồn.

### Yêu cầu

- Xcode Command Line Tools;
- Node.js và npm;
- Rust stable và Cargo.

### Build

Từ thư mục gốc:

```bash
./scripts/build_macos.sh [action]
```

Các tham số (actions) hỗ trợ:

- **`build`** (hoặc không truyền tham số): Chỉ build ra bundle `.app` tại:
  ```text
  Sources/src-tauri/target/release/bundle/macos/VNKey.app
  ```
- **`clean`**: Dọn dẹp toàn bộ các thư mục build tạm thời của cargo và frontend (`node_modules`, `.svelte-kit`, `build`).
- **`dmg`**: Build bundle `.app` và đóng gói thành tệp `.dmg` tại:
  ```text
  Sources/src-tauri/target/release/bundle/dmg/VNKey_1.0.0_aarch64.dmg
  ```
- **`install`**: Build bundle `.app`, đóng ứng dụng VNKey đang chạy (nếu có), thay thế ứng dụng cũ trong thư mục `/Applications/`, và mở ứng dụng mới.

### Chạy thử

```bash
open -g Sources/src-tauri/target/release/bundle/macos/VNKey.app
```

VNKey cần quyền Accessibility để event tap trên macOS bắt và gửi phím. Bundle
identifier được giữ là `com.theodore.vnkey` để tương thích với cấu hình quyền
của ứng dụng cũ.

DMG phát hành nên được tạo trong pipeline có Developer ID, hardened runtime và
notarization. Bundle local từ script sử dụng chữ ký ad-hoc dành cho phát triển.

## Tác giả
- theodore.
- Mọi góp ý, gửi cho mình qua maivutuyen.91@gmail.com  
- Fanpage: [https://www.facebook.com/VNKey](https://www.facebook.com/VNKey)

## Liên kết
- [Dự án VNKey Tauri (Hỗ trợ macOS, Windows, Linux)](https://github.com/tuyenvm/VNKey/tree/master/Sources)
## Một điều nhỏ nhoi
Đừng quên ủng hộ tác giả bằng cách mua ly cafe cho tác giả tỉnh ngủ nhé:  
[Buy me a coffee ^^](https://tuyenvm.github.io/donate.html)  
[Redbull cũng được ^^](https://paypal.me/tuyenmai)  
Hoặc trực tiếp qua ví momo:   
![Donate by momo](https://tuyenvm.github.io/images/momo.png "Momo").   

Cảm ơn các bạn rất nhiều.
