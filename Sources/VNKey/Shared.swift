import AppKit
import VNKeyCore

enum Key {
    static let enabled = "enabled", method = "method", modernTone = "modernTone"
    static let standaloneW = "standaloneW", bracketKeys = "bracketKeys"
    static let teen = "teenInitials", autoRestore = "autoRestore", expandTeen = "expandTeen"
    static let perApp = "perAppLanguage", appStates = "appStates", fixBrowser = "fixAutocomplete"
    static let preferRaw = "preferRaw", preferVN = "preferVN", macros = "macros"
    static let codeAware = "codeAware", contextAware = "contextAware"
    static let autoCapitalize = "autoCapitalize", tidyPunctuation = "tidyPunctuation", showHUD = "showHUD"
    static let toggleHotkey = "toggleHotkey", restoreHotkey = "restoreHotkey", excludedApps = "excludedApps"
    static let debugLog = "debugLog"
    /// Công tắc chính của nhóm "Ngôn ngữ GenZ" (chữ teen): tắt thì `teen` và `expandTeen` không còn tác dụng.
    static let genZ = "genZ"
    /// Gõ tắt thông minh: công tắc, và bảng tên -> nội dung (gõ `\tên` rồi ngắt từ). Người dùng sửa được cả bảng.
    static let smartMacros = "smartMacros", smartMacroTable = "smartMacroTable"
    static let followInputSource = "followInputSource"
    static let autoUpdateCheck = "autoUpdateCheck", updateLastCheck = "updateLastCheck"
    static let language = "language"
    static let learnUsage = "learnUsage"
    /// Soát lỗi: gạch chân từ nghi gõ sai trong ô đang nhập (VNKey không tự thay chữ); soát cả tiếng Anh; các từ
    /// người dùng bảo bỏ qua (mảng chữ thường).
    static let proofread = "proofread", proofreadEnglish = "proofreadEnglish", proofreadIgnored = "proofreadIgnored"
    /// Thêm dòng "Sửa cả câu…" vào bảng đề nghị (mô hình chạy trên máy của macOS; xem `SentenceFix`).
    static let proofreadSentence = "proofreadSentence"
    static let clipboardEnabled = "clipboardEnabled", clipboardHotkey = "clipboardHotkey", clipboardSync = "clipboardSync"
    static let clipboardExcludedApps = "clipboardExcludedApps"
    /// Khoá ẩn (không có trong Cài đặt): trỏ thư mục đồng bộ sang chỗ khác khi thử nghiệm.
    static let clipboardSyncFolder = "clipboardSyncFolder"

    static let registered: [String: Any] = [
        enabled: true, method: "telex", standaloneW: true, bracketKeys: false, teen: true, autoRestore: true, fixBrowser: true,
        codeAware: true, contextAware: true, showHUD: true,
        modernTone: false, expandTeen: false, perApp: false, autoCapitalize: false, tidyPunctuation: false,
        // Nhật ký gỡ lỗi lưu cả nội dung gõ: mặc định TẮT ở mọi bản dựng. Bật trong Cài đặt › Chung khi cần
        // tìm lỗi (không hỏi ở cửa sổ thiết lập ban đầu).
        debugLog: false,
        genZ: true, smartMacros: true, followInputSource: true,
        smartMacroTable: [
            "homnay": "[ngay]", "bgio": "[gio]", "thu": "[thu]", "ngay": "[ngaydai]", "amlich": "[amlich]", "hoten": "[hoten]",
        ],
        // Hai gõ tắt thường làm mẫu, chỉ có khi người dùng chưa từng lưu bảng nào.
        macros: ["vn": "Việt Nam", "tphcm": "Thành phố Hồ Chí Minh"], autoUpdateCheck: true, language: "auto", learnUsage: true,
        proofread: true, proofreadEnglish: false, proofreadSentence: true,
        toggleHotkey: Hotkey.defaultToggle.string, restoreHotkey: Hotkey.defaultRestore.string,
        // Lịch sử clipboard ghi mọi thứ đã sao chép xuống đĩa: mặc định TẮT, người dùng tự bật.
        clipboardEnabled: false, clipboardSync: false, clipboardHotkey: Hotkey.defaultClipboard.string,
        clipboardExcludedApps: ["com.apple.Passwords", "com.apple.keychainaccess"],
        // Terminal mặc định bắt đầu ở chế độ Anh; vẫn bật lại được bằng phím tắt.
        excludedApps: [
            "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
            "io.alacritty", "com.mitchellh.ghostty",
        ],
    ]
}

/// Ngôn ngữ giao diện: theo hệ thống (mặc định), hoặc người dùng chọn tiếng Việt / tiếng Anh trong Cài đặt.
enum AppLanguage {
    /// Giá trị lưu ở `Key.language`: "auto", "vi", "en".
    static var setting: String { UserDefaults.standard.string(forKey: Key.language) ?? "auto" }

    /// Ép ngôn ngữ cho lần chạy này mà không đụng tới cài đặt (chế độ chụp giao diện `--snapshot … --en`).
    static var override: String?

    static var isVietnamese: Bool {
        switch override ?? setting {
        case "vi": return true
        case "en": return false
        default: return (Locale.preferredLanguages.first ?? "vi").hasPrefix("vi")
        }
    }
}

/// Chuỗi giao diện song ngữ: viết cả hai bản ngay tại chỗ dùng. Máy chỉ có Command Line Tools nên không dùng
/// được tệp .strings / String Catalog của Xcode; cách này cũng giữ hai bản dịch cạnh nhau khi sửa.
func L(_ vi: String, _ en: String) -> String { AppLanguage.isVietnamese ? vi : en }

/// Cửa sổ cài đặt đang ghi phím tắt: KeyTap tạm thời cho mọi phím đi qua.
var hotkeyRecording = false
