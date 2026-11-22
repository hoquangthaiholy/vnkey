import AppKit

enum Key {
    static let enabled = "enabled", method = "method", modernTone = "modernTone", standaloneW = "standaloneW"
    static let teen = "teenInitials", autoRestore = "autoRestore", expandTeen = "expandTeen"
    static let perApp = "perAppLanguage", appStates = "appStates", fixBrowser = "fixAutocomplete"
    static let preferRaw = "preferRaw", preferVN = "preferVN", macros = "macros"
    static let codeAware = "codeAware", fixTransposition = "fixTransposition", contextAware = "contextAware"
    static let autoCapitalize = "autoCapitalize", tidyPunctuation = "tidyPunctuation", showHUD = "showHUD"
    static let toggleHotkey = "toggleHotkey", restoreHotkey = "restoreHotkey", excludedApps = "excludedApps"

    static let registered: [String: Any] = [
        enabled: true, method: "telex", standaloneW: true, teen: true, autoRestore: true, fixBrowser: true,
        codeAware: true, fixTransposition: true, contextAware: true, showHUD: true,
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

/// Phím tắt: tổ hợp phím bổ trợ + một phím, hoặc chỉ phím bổ trợ (code = -1, nhấn rồi thả).
struct Hotkey: Equatable {
    static let modMask: UInt =
        NSEvent.ModifierFlags([.control, .option, .shift, .command]).rawValue

    var code: Int
    var mods: UInt
    var keyLabel: String

    static let defaultToggle = Hotkey(
        code: -1, mods: NSEvent.ModifierFlags([.control, .shift]).rawValue, keyLabel: "")
    static let defaultRestore = Hotkey(
        code: 6, mods: NSEvent.ModifierFlags([.control, .option]).rawValue, keyLabel: "Z")

    var string: String { "\(code):\(mods):\(keyLabel)" }

    init(code: Int, mods: UInt, keyLabel: String) {
        self.code = code; self.mods = mods & Hotkey.modMask; self.keyLabel = keyLabel
    }

    init?(string: String) {
        let p = string.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard p.count == 3, let c = Int(p[0]), let m = UInt(p[1]), m & Hotkey.modMask != 0 else { return nil }
        self.init(code: c, mods: m, keyLabel: String(p[2]))
    }

    var label: String {
        let f = NSEvent.ModifierFlags(rawValue: mods)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + keyLabel
    }
}
