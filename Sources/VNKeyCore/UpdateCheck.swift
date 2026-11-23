import Foundation

/// Phần logic của việc kiểm tra bản mới qua GitHub Releases: dựng địa chỉ, đọc câu trả lời, so phiên bản.
/// Không tự tải hay cài gì; app chỉ báo và mở trang tải trong trình duyệt.
public enum UpdateCheck {
    public struct Release: Equatable {
        public var version: String
        /// Trang của bản phát hành trên GitHub (luôn là https).
        public var page: URL
        public var notes: String
        public init(version: String, page: URL, notes: String) {
            self.version = version; self.page = page; self.notes = notes
        }
    }

    public enum Outcome: Equatable {
        case available(Release)
        case upToDate
        /// Kho chưa có bản phát hành nào (hoặc chưa tồn tại / không công khai).
        case noRelease
        case failed(String)
    }

    /// "chủ/tên" -> địa chỉ API của bản phát hành mới nhất; nil nếu tên kho không hợp lệ.
    public static func latestReleaseURL(repository: String) -> URL? {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let ok = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(ok.contains) }) else {
            return nil
        }
        return URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
    }

    /// Các số của phiên bản: "v0.2.0-beta" -> [0, 2, 0]; nil nếu không bắt đầu bằng số.
    static func numbers(_ version: String) -> [Int]? {
        var s = Substring(version.trimmingCharacters(in: .whitespaces))
        if s.first == "v" || s.first == "V" { s = s.dropFirst() }
        let core = s.prefix { $0.isNumber || $0 == "." }
        let parts = core.split(separator: ".").compactMap { Int($0) }
        return parts.isEmpty ? nil : parts
    }

    public static func isNewer(_ remote: String, than local: String) -> Bool {
        guard let r = numbers(remote), let l = numbers(local) else { return false }
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0, b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Đọc câu trả lời của `GET /repos/{chủ}/{tên}/releases/latest`. Bỏ qua bản nháp và bản thử.
    public static func release(from data: Data) -> Release? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = o["tag_name"] as? String, numbers(tag) != nil,
            let link = o["html_url"] as? String, let page = URL(string: link), page.scheme == "https",
            (o["draft"] as? Bool) != true, (o["prerelease"] as? Bool) != true
        else { return nil }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        return Release(version: version, page: page, notes: (o["body"] as? String) ?? "")
    }

    public static func outcome(status: Int, release: Release?, local: String) -> Outcome {
        switch status {
        case 200:
            guard let release else { return .noRelease }
            return isNewer(release.version, than: local) ? .available(release) : .upToDate
        case 404: return .noRelease
        default: return .failed("GitHub tạm từ chối (mã \(status)); thử lại sau.")
        }
    }

    /// Đã tới lúc tự kiểm tra chưa: mỗi ngày một lần.
    public static func isDue(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        let gap = now.timeIntervalSince(last)
        return gap < 0 || gap >= 86_400
    }
}
