import Foundation

/// Thống kê thời gian xử lý phím trong callback của event tap, gom theo từng đợt.
public struct PerfStats {
    public private(set) var keys = 0
    public private(set) var totalNs: UInt64 = 0
    public private(set) var maxNs: UInt64 = 0
    /// Số phím mất từ 1 ms / 10 ms trở lên.
    public private(set) var over1ms = 0
    public private(set) var over10ms = 0
    public private(set) var axCalls = 0
    public private(set) var axTotalNs: UInt64 = 0
    public private(set) var axMaxNs: UInt64 = 0

    public init() {}

    public mutating func key(_ ns: UInt64) {
        keys += 1; totalNs += ns; maxNs = max(maxNs, ns)
        if ns >= 1_000_000 { over1ms += 1 }
        if ns >= 10_000_000 { over10ms += 1 }
    }

    /// Một lần hỏi Accessibility (đã nằm trong thời gian của phím tương ứng).
    public mutating func ax(_ ns: UInt64) {
        axCalls += 1; axTotalNs += ns; axMaxNs = max(axMaxNs, ns)
    }

    public var summary: String {
        func us(_ ns: UInt64, _ n: Int) -> String { n == 0 ? "-" : String(format: "%.0f", Double(ns) / Double(n) / 1000) }
        func ms(_ ns: UInt64) -> String { String(format: "%.2f", Double(ns) / 1e6) }
        return "phím=\(keys) tb=\(us(totalNs, keys))µs max=\(ms(maxNs))ms ≥1ms=\(over1ms) ≥10ms=\(over10ms)"
            + " | ax=\(axCalls) tb=\(us(axTotalNs, axCalls))µs max=\(ms(axMaxNs))ms"
    }

    public mutating func reset() { self = PerfStats() }
}
