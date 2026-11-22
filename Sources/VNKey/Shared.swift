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

/// Nhật ký gỡ lỗi đầy đủ: mọi phím, kết quả của engine, cách gửi phím và các sự kiện hệ thống.
/// LƯU Ý: khi bật, tệp log chứa nguyên văn những gì bạn gõ (trừ ô mật khẩu — macOS không cho
/// bộ gõ thấy phím ở đó). Tệp chỉ nằm trên máy này: ~/Library/Logs/VNKey.log
enum Log {
    static var enabled = false
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/VNKey.log")
    private static var handle: FileHandle?
    private static let maxBytes: UInt64 = 5 << 20
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ line: @autoclosure () -> String) {
        guard enabled, let data = "\(stamp.string(from: Date())) \(line())\n".data(using: .utf8) else { return }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
        }
        guard let h = handle else { return }
        if h.offsetInFile > maxBytes {  // quá 5 MB: giữ bản cũ thành .1 rồi ghi tệp mới
            try? h.close()
            handle = nil
            let old = url.appendingPathExtension("1")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
            write(line())
            return
        }
        h.write(data)
    }

    static func show(_ s: String) -> String { showControl(s) }
}
