import AppKit
import VNKeyCore

/// Thông tin về ứng dụng dùng ở thẻ Giới thiệu và khi kiểm tra bản mới.
enum AppInfo {
    static let developer = "Hồ Quang Thái"
    /// Kho GitHub phát hành VNKey, dạng "chủ/tên". Bản mới được lấy từ mục Releases của kho này.
    static let repository = "hoquangthaiholy/vnkey"
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
        if case .done(.available(let r)) = state { return r }
        return nil
    }

    /// Tự kiểm tra nếu người dùng cho phép và đã quá một ngày kể từ lần trước.
    func checkIfDue() {
        guard defaults.bool(forKey: Key.autoUpdateCheck), UpdateCheck.isDue(last: lastChecked, now: Date()) else { return }
        check()
    }

    func check() {
        guard state != .checking else { return }
        guard let url = UpdateCheck.latestReleaseURL(repository: AppInfo.repository) else {
            state = .done(.failed("Chưa đặt kho GitHub phát hành VNKey."))
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
                outcome = .failed(error?.localizedDescription ?? "Không kết nối được.")
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
