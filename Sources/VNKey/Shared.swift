import AppKit
import VNKeyCore

enum Key {
    static let enabled = "enabled", method = "method", modernTone = "modernTone"
    static let standaloneW = "standaloneW", bracketKeys = "bracketKeys"
    static let teen = "teenInitials", autoRestore = "autoRestore", expandTeen = "expandTeen"
    static let perApp = "perAppLanguage", appStates = "appStates", fixBrowser = "fixAutocomplete"
    static let preferRaw = "preferRaw", preferVN = "preferVN", macros = "macros"
    static let codeAware = "codeAware", fixTransposition = "fixTransposition", contextAware = "contextAware"
    static let autoCapitalize = "autoCapitalize", tidyPunctuation = "tidyPunctuation", showHUD = "showHUD"
    static let toggleHotkey = "toggleHotkey", restoreHotkey = "restoreHotkey", excludedApps = "excludedApps"
    static let debugLog = "debugLog"
    static let learnFromRetype = "learnFromRetype"
    static let followInputSource = "followInputSource", flashFix = "flashFix"
    static let autoUpdateCheck = "autoUpdateCheck", updateLastCheck = "updateLastCheck"
    static let language = "language"
    static let predict = "predict", predictUnmarked = "predictUnmarked", learnUsage = "learnUsage"
    static let clipboardEnabled = "clipboardEnabled", clipboardHotkey = "clipboardHotkey", clipboardSync = "clipboardSync"
    static let clipboardExcludedApps = "clipboardExcludedApps"
    /// Khoá ẩn (không có trong Cài đặt): trỏ thư mục đồng bộ sang chỗ khác khi thử nghiệm.
    static let clipboardSyncFolder = "clipboardSyncFolder"

    static let registered: [String: Any] = [
        enabled: true, method: "telex", standaloneW: true, bracketKeys: false, teen: true, autoRestore: true, fixBrowser: true,
        codeAware: true, fixTransposition: true, contextAware: true, showHUD: true,
        modernTone: false, expandTeen: false, perApp: false, autoCapitalize: false, tidyPunctuation: false,
        // Nhật ký gỡ lỗi lưu cả nội dung gõ: mặc định TẮT ở mọi bản dựng. Bật trong Cài đặt › Chung khi cần
        // tìm lỗi (không hỏi ở cửa sổ thiết lập ban đầu).
        debugLog: false,
        learnFromRetype: true, followInputSource: true, flashFix: true, autoUpdateCheck: true, language: "auto", predict: true, predictUnmarked: true, learnUsage: true,
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
