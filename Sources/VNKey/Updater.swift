import AppKit
import VNKeyCore

/// Thông tin về ứng dụng dùng ở thẻ Giới thiệu và khi kiểm tra bản mới.
enum AppInfo {
    static let developer = "Hồ Quang Thái"
    /// Kho GitHub phát hành VNKey, dạng "chủ/tên". Bản mới được lấy từ mục Releases của kho này.
    static let repository = "hoquangthaiholy/vnkey"
    static let website = URL(string: "https://hoquangthaiholy.github.io/vnkey/")!
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }
}

/// Kiểm tra bản mới trên GitHub Releases. Chỉ hỏi số phiên bản mới nhất rồi báo; không tải, không cài.
/// Yêu cầu gửi đi không kèm gì về người dùng (phiên không cookie, không bộ đệm). Chỉ dùng trên luồng chính.
final class Updater {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case done(UpdateCheck.Outcome)
        /// Đang tải bản mới về.
        case downloading(UpdateCheck.Release)
        /// Đã tải và kiểm tra xong, đang thay app rồi mở lại.
        case installing(UpdateCheck.Release)
        /// Tự cập nhật thất bại; bản mới vẫn tải tay được ở trang phát hành.
        case installFailed(UpdateCheck.Release, String)
    }

    private(set) var state = State.idle { didSet { onChange?() } }
    var onChange: (() -> Void)?
    private let defaults = UserDefaults.standard
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    var lastChecked: Date? { defaults.object(forKey: Key.updateLastCheck) as? Date }

    /// Bản mới đang chờ (nếu lần kiểm tra gần nhất tìm thấy).
    var available: UpdateCheck.Release? {
        switch state {
        case .done(.available(let r)), .downloading(let r), .installing(let r), .installFailed(let r, _): return r
        default: return nil
        }
    }

    /// Bản đang chạy có tự cập nhật được không: phải được ký bằng Developer ID (bản dựng trên máy thì không),
    /// và bản phát hành phải có tệp ZIP.
    var canInstall: Bool {
        guard let r = available, r.download != nil else { return false }
        return Installer.runningIdentity().team != nil
    }

    /// Tải bản mới, kiểm tra chữ ký, thay app đang chạy rồi mở lại. Mọi bước sai đều dừng và giữ nguyên app cũ.
    func installUpdate() {
        guard let release = available, let url = release.download else { return }
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .downloading(release)
        Log.write("UPDATE tải \(url.lastPathComponent)")
        session.downloadTask(with: url) { file, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let file, status == 200 else {
                let why = error?.localizedDescription ?? "HTTP \(status)"
                DispatchQueue.main.async {
                    Log.write("UPDATE tải lỗi: \(why)")
                    self.state = .installFailed(release, L("Không tải được bản mới: \(why)", "Download failed: \(why)"))
                }
                return
            }
            // Tệp tạm của URLSession bị xoá ngay khi hàm này trả về: chuyển nó đi trước.
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("vnkey-update-\(UUID().uuidString)")
            let zip = work.appendingPathComponent("VNKey.zip")
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: file, to: zip)
            } catch {
                DispatchQueue.main.async { self.state = .installFailed(release, error.localizedDescription) }
                return
            }
            DispatchQueue.main.async { self.state = .installing(release) }
            let result = Installer.install(zip: zip, workDirectory: work)
            DispatchQueue.main.async {
                switch result {
                case .success(let app):
                    Log.write("UPDATE đã cài \(release.version), mở lại")
                    Log.flush()
                    Installer.relaunch(app)
                case .failure(let e):
                    Log.write("UPDATE cài lỗi: \(e.message)")
                    try? FileManager.default.removeItem(at: work)
                    self.state = .installFailed(release, e.message)
                }
            }
        }.resume()
    }

    /// Tự kiểm tra nếu người dùng cho phép và đã quá một ngày kể từ lần trước.
    func checkIfDue() {
        guard defaults.bool(forKey: Key.autoUpdateCheck), UpdateCheck.isDue(last: lastChecked, now: Date()) else { return }
        check()
    }

    func check() {
        guard state != .checking else { return }
        guard let url = UpdateCheck.latestReleaseURL(repository: AppInfo.repository) else {
            state = .done(.failed(L("Chưa đặt kho GitHub phát hành VNKey.", "No GitHub repository is configured for releases.")))
            return
        }
        state = .checking
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VNKey-update-check", forHTTPHeaderField: "User-Agent")
        let local = AppInfo.version
        session.dataTask(with: request) { data, response, error in
            let outcome: UpdateCheck.Outcome
            if let http = response as? HTTPURLResponse {
                outcome = UpdateCheck.outcome(
                    status: http.statusCode, release: data.flatMap(UpdateCheck.release(from:)), local: local)
            } else {
                outcome = .failed(error?.localizedDescription ?? L("Không kết nối được.", "Could not connect."))
            }
            DispatchQueue.main.async {
                // Lần hỏi thất bại vì mạng thì không tính là "đã kiểm tra", để lần sau thử lại sớm.
                if case .failed = outcome {} else { self.defaults.set(Date(), forKey: Key.updateLastCheck) }
                Log.write("UPDATE \(outcome)")
                self.state = .done(outcome)
            }
        }.resume()
    }
}

/// Thay app đang chạy bằng bản vừa tải. Nguyên tắc: không tin gì lấy từ mạng cho tới khi chữ ký được kiểm tra,
/// và không bao giờ để máy rơi vào trạng thái không còn app nào (bản cũ được giữ lại cho tới khi bản mới vào chỗ).
enum Installer {
    struct Failure: Error { let message: String }

    /// Nhóm ký (Team ID) của một app; nil nếu không ký bằng chứng chỉ có Team ID (ad-hoc, tự ký).
    private static func team(of code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let d = info as? [String: Any]
        else { return nil }
        return d[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func runningIdentity() -> UpdateCheck.Identity {
        var code: SecStaticCode?
        SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code)
        return (Bundle.main.bundleIdentifier ?? "", code.flatMap(team(of:)), AppInfo.version)
    }

    /// Giải nén, kiểm tra chữ ký rồi đổi chỗ. Chạy trên luồng nền.
    static func install(zip: URL, workDirectory work: URL) -> Result<URL, Failure> {
        let fm = FileManager.default
        let unpacked = work.appendingPathComponent("unpacked")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        do { try ditto.run() } catch { return .failure(Failure(message: error.localizedDescription)) }
        ditto.waitUntilExit()
        let fresh = unpacked.appendingPathComponent("VNKey.app")
        guard ditto.terminationStatus == 0, fm.fileExists(atPath: fresh.path) else {
            return .failure(Failure(message: L("Tệp tải về không chứa VNKey.app.", "The download does not contain VNKey.app.")))
        }

        // Chữ ký phải hợp lệ trên mọi kiến trúc, do Apple cấp chứng chỉ, và cùng nhóm ký với bản đang chạy.
        let running = runningIdentity()
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(fresh as CFURL, [], &code) == errSecSuccess, let code else {
            return .failure(Failure(message: L("Không đọc được chữ ký của bản tải về.", "Cannot read the download's signature.")))
        }
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[subject.OU] = \"\(running.team ?? "-")\""
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
            SecStaticCodeCheckValidity(
                code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode),
                requirement) == errSecSuccess
        else {
            return .failure(Failure(message: L("Chữ ký của bản tải về không hợp lệ.", "The download's signature is not valid.")))
        }
        let plist = NSDictionary(contentsOf: fresh.appendingPathComponent("Contents/Info.plist"))
        let candidate: UpdateCheck.Identity = (
            plist?["CFBundleIdentifier"] as? String ?? "", team(of: code), plist?["CFBundleShortVersionString"] as? String ?? ""
        )
        if let why = UpdateCheck.mayInstall(candidate: candidate, running: running) {
            return .failure(Failure(message: L("Không cài: \(why).", "Not installed: \(why).")))
        }

        // Đổi chỗ: cất bản cũ sang thư mục tạm, đưa bản mới vào; lỗi giữa chừng thì trả bản cũ về.
        let current = Bundle.main.bundleURL
        let backup = work.appendingPathComponent("previous.app")
        do {
            try fm.moveItem(at: current, to: backup)
        } catch {
            return .failure(Failure(message: L(
                "Không thay được app ở \(current.path): \(error.localizedDescription)",
                "Cannot replace the app at \(current.path): \(error.localizedDescription)")))
        }
        do {
            try fm.moveItem(at: fresh, to: current)
        } catch {
            try? fm.moveItem(at: backup, to: current)
            return .failure(Failure(message: error.localizedDescription))
        }
        return .success(current)
    }

    /// Mở bản mới sau khi tiến trình này thoát.
    static func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
