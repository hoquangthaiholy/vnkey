import AppKit
import VNKeyCore

enum Key {
    static let enabled = "enabled", method = "method", modernTone = "modernTone", standaloneW = "standaloneW"
    static let teen = "teenInitials", autoRestore = "autoRestore", expandTeen = "expandTeen"
    static let perApp = "perAppLanguage", appStates = "appStates", fixBrowser = "fixAutocomplete"
    static let preferRaw = "preferRaw", preferVN = "preferVN", macros = "macros"
    static let codeAware = "codeAware", fixTransposition = "fixTransposition", contextAware = "contextAware"
    static let autoCapitalize = "autoCapitalize", tidyPunctuation = "tidyPunctuation", showHUD = "showHUD"
    static let toggleHotkey = "toggleHotkey", restoreHotkey = "restoreHotkey", excludedApps = "excludedApps"
    static let debugLog = "debugLog"

    static let registered: [String: Any] = [
        enabled: true, method: "telex", standaloneW: true, teen: true, autoRestore: true, fixBrowser: true,
        codeAware: true, fixTransposition: true, contextAware: true, showHUD: true,
        // Đang phát triển: ghi nhật ký đầy đủ theo mặc định (tắt được trong menu).
        debugLog: true,
        toggleHotkey: Hotkey.defaultToggle.string, restoreHotkey: Hotkey.defaultRestore.string,
        // Terminal mặc định bắt đầu ở chế độ Anh; vẫn bật lại được bằng phím tắt.
        excludedApps: [
            "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
            "io.alacritty", "com.mitchellh.ghostty",
        ],
    ]
}

/// Cửa sổ cài đặt đang ghi phím tắt: KeyTap tạm thời cho mọi phím đi qua.
var hotkeyRecording = false
