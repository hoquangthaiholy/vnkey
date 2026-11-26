import Foundation
import VNEngine

#if canImport(FoundationModels)
import FoundationModels
#endif

// Bộ đo chung cho việc sửa cả câu: cùng một bộ câu, nhiều "đường" sửa (thuật toán trên máy, mô hình của macOS), cùng
// một cách chấm. Bộ câu nằm trong `Eval/` ở gốc dự án (xem `Eval/README.md`).

/// Một câu của bộ đo: câu gõ, câu đúng, loại lỗi.
struct EvalCase {
    var typed: String
    var want: String
    var kind: String
}

/// Một đường sửa câu. Thêm mô hình mới: viết một kiểu theo giao thức này và thêm vào `EvalRunner.engines`.
protocol SentenceEngine {
    var name: String { get }
    func fix(_ text: String) async throws -> String
}

#if canImport(FoundationModels)
/// Mô hình trên máy của macOS. `filtered`: qua `SentenceFilter.merge` như trong ứng dụng; không thì lấy nguyên câu.
/// `guard`: `strict` = bộ lọc an toàn mặc định; `retry` = mặc định, bị từ chối thì hỏi lại với mức dành cho việc biến
/// đổi văn bản (`permissiveContentTransformations`); `open` = luôn dùng mức đó.
@available(macOS 26.0, *)
final class AppleEngine: SentenceEngine {
    enum Guard: String { case strict, retry, open }
    let filtered: Bool
    let mode: Guard
    let instructions: String
    /// Số câu bị từ chối ở lần hỏi đầu rồi được trả lời ở lần hỏi lại.
    var rescued = 0
    init(filtered: Bool, mode: Guard = .strict, instructions: String = SentenceFilter.instructions) {
        self.filtered = filtered
        self.mode = mode
        self.instructions = instructions
    }
    var name: String { (filtered ? "apple" : "apple-raw") + (mode == .strict ? "" : "-" + mode.rawValue) }
    private func ask(_ text: String, permissive: Bool) async throws -> String {
        // Mỗi câu một phiên mới: câu trước không ảnh hưởng câu sau.
        let model = permissive ? SystemLanguageModel(guardrails: .permissiveContentTransformations) : SystemLanguageModel.default
        let session = LanguageModelSession(model: model, instructions: instructions)
        let answer = try await session.respond(to: text, options: .greedy(maxTokens: 200))
        return answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func fix(_ text: String) async throws -> String {
        var raw: String
        do {
            raw = try await ask(text, permissive: mode == .open)
        } catch let error as LanguageModelSession.GenerationError {
            guard mode == .retry else { throw error }
            switch error {
            case .guardrailViolation, .refusal:
                raw = try await ask(text, permissive: true)
                rescued += 1
            default: throw error
            }
        }
        return filtered ? SentenceFilter.merge(original: text, proposed: raw) : raw
    }
}
#endif

/// Bộ sinh số ngẫu nhiên có hạt giống (SplitMix64): cùng hạt giống thì cùng bộ câu.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum EvalSet {
    static let generated = "Eval/generated.tsv"
    static let handwritten = "Eval/handwritten.tsv"

    /// Đọc tệp `câu gõ <TAB> câu đúng <TAB> loại`. Dòng trống và dòng bắt đầu bằng `#` bị bỏ qua.
    static func load(_ path: String) -> [EvalCase]? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var out: [EvalCase] = []
        for line in text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 2, !f[0].isEmpty else { continue }
            out.append(EvalCase(typed: f[0], want: f[1], kind: f.count > 2 && !f[2].isEmpty ? f[2] : "tay"))
        }
        return out
    }

    /// Tách câu thành các mẩu, mẩu nào là từ (toàn chữ cái) thì `word` là true.
    static func pieces(_ text: String) -> [(text: String, word: Bool)] {
        var out: [(String, Bool)] = []
        var current = "", isWord = false
        for ch in text {
            let letter = ch.isLetter
            if !current.isEmpty, letter != isWord { out.append((current, isWord)); current = "" }
            isWord = letter
            current.append(ch)
        }
        if !current.isEmpty { out.append((current, isWord)) }
        return out
    }

    /// Sinh bộ câu từ một tệp câu tiếng Việt sạch (mỗi dòng một câu; nếu dòng có tab thì lấy cột cuối, như tệp xuất
    /// của Tatoeba). In ra đầu ra chuẩn.
    static func make(from path: String, count: Int, seed: UInt64) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fatalError("không đọc được \(path)") }
        var seen = Set<String>()
        var pool: [String] = []
        for line in text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isNewline) {
            guard let last = line.split(separator: "\t").last else { continue }
            let sentence = last.trimmingCharacters(in: .whitespaces)
            let words = pieces(sentence).filter(\.word).map(\.text)
            // Câu thuần Việt, dài vừa phải: mọi từ là âm tiết đúng cấu tạo, có ít nhất một chữ mang dấu, không có số.
            guard (4...20).contains(words.count), !sentence.contains(where: \.isNumber),
                sentence.contains(where: { !$0.isASCII && $0.isLetter }),
                words.allSatisfy({ Charset.syllableKey($0) != nil }), seen.insert(sentence.lowercased()).inserted
            else { continue }
            pool.append(sentence)
        }
        var rng = SeededRandom(state: seed)
        pool.shuffle(using: &rng)
        let reader = Proofreader()
        let plan: [(kind: String, share: Double)] = [("khong-dau", 0.30), ("thieu-dau", 0.25), ("lan-am", 0.20), ("sai-thanh", 0.10), ("dung", 0.15)]

        /// Câu sau khi cấy lỗi loại `kind`, nil nếu câu không cấy được loại lỗi đó.
        func corrupt(_ sentence: String, _ kind: String) -> String? {
            var parts = pieces(sentence)
            let words = parts.indices.filter { parts[$0].word }
            switch kind {
            case "khong-dau":
                return Charset.stripMarks(sentence)
            case "thieu-dau":
                let marked = words.filter { Charset.stripMarks(parts[$0].text) != parts[$0].text }.shuffled(using: &rng)
                guard marked.count >= 2 else { return nil }
                for i in marked.prefix(Int.random(in: 1...2, using: &rng)) { parts[i].text = Charset.stripMarks(parts[i].text) }
            case "ngoai-bang":
                // Lỗi ra một âm tiết KHÔNG có trong bảng thông dụng (lẫn âm hoặc sai thanh bất kỳ): "về" -> "vễ", "dề".
                let options = words.compactMap { i -> (Int, String)? in
                    let w = parts[i].text
                    guard w == w.lowercased(), Proofreader.frequency(of: w) > 0 else { return nil }
                    let odd = (reader.confusions(of: w, anySyllable: true) + reader.retoned(w)).filter { Proofreader.frequency(of: $0) == 0 }
                    return odd.randomElement(using: &rng).map { (i, $0) }
                }
                guard let pick = options.randomElement(using: &rng) else { return nil }
                parts[pick.0].text = pick.1
            case "lan-am", "sai-thanh":
                // Chỉ đổi từ viết thường, để khỏi phải dựng lại chữ hoa.
                let options = words.compactMap { i -> (Int, String)? in
                    let w = parts[i].text
                    guard w == w.lowercased() else { return nil }
                    return reader.confusions(of: w, tonesOnly: kind == "sai-thanh").randomElement(using: &rng).map { (i, $0) }
                }
                guard let pick = options.randomElement(using: &rng) else { return nil }
                parts[pick.0].text = pick.1
            default:
                return sentence
            }
            return parts.map(\.text).joined()
        }

        print("# TỆP SINH TỰ ĐỘNG bằng `vnkey-tool eval-make` (hạt giống \(seed)): đừng sửa tay. Xem Eval/README.md.")
        print("# Câu đúng lấy từ Tatoeba (https://tatoeba.org), giấy phép CC BY 2.0 FR. Câu gõ là câu đúng bị cấy lỗi.")
        print("# câu gõ<TAB>câu đúng<TAB>loại")
        var next = 0, made = 0
        // Nhóm thêm sau (2026-11-26) nối vào cuối, lấy câu tiếp theo trong cùng thứ tự: các câu sinh trước không đổi.
        for (kind, share) in plan + [("ngoai-bang", 0.15)] {
            var need = Int((Double(count) * share).rounded())
            while need > 0, next < pool.count {
                let sentence = pool[next]
                next += 1
                guard let typed = corrupt(sentence, kind) else { continue }
                print("\(typed)\t\(sentence)\t\(kind)")
                need -= 1
                made += 1
            }
        }
        FileHandle.standardError.write("\(pool.count) câu dùng được, đã sinh \(made) câu\n".data(using: .utf8)!)
    }
}

enum EvalRunner {
    struct Outcome {
        var out: String
        var ms: Double
        var score: SentenceFilter.Score
        /// Lần gọi báo lỗi: như trong ứng dụng, câu giữ nguyên (chấm như chưa sửa gì).
        var failed = false
    }

    /// Các đường theo tên. Đường cần mô hình mà máy không có thì bỏ, kèm lý do in ra.
    static func engines(_ list: String) -> [any SentenceEngine] {
        // Nhiều đường thì ngăn bằng dấu phẩy: `apple,apple-retry`.
        list.split(separator: ",").flatMap { one(String($0)) }
    }

    /// Chỉ dẫn cho mô hình của macOS; `--instructions <tệp>` thay bằng nội dung tệp để thử lời nhắc khác.
    static var instructions = SentenceFilter.instructions

    private static func one(_ wanted: String) -> [any SentenceEngine] {
        var out: [any SentenceEngine] = []
        let all = wanted == "all"
        if all || wanted.hasPrefix("apple") {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                if case .available = SystemLanguageModel.default.availability {
                    if all || wanted == "apple" { out.append(AppleEngine(filtered: true, instructions: instructions)) }
                    if all || wanted == "apple-raw" { out.append(AppleEngine(filtered: false, instructions: instructions)) }
                    if wanted == "apple-retry" { out.append(AppleEngine(filtered: true, mode: .retry, instructions: instructions)) }
                    if wanted == "apple-open" { out.append(AppleEngine(filtered: true, mode: .open, instructions: instructions)) }
                } else {
                    print("Bỏ qua mô hình của macOS: chưa dùng được (\(SystemLanguageModel.default.availability)).")
                }
            } else {
                print("Bỏ qua mô hình của macOS: cần macOS 26 trở lên.")
            }
            #else
            print("Bỏ qua mô hình của macOS: bộ công cụ biên dịch này không có framework Foundation Models.")
            #endif
        }
        return out
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.down)))]
    }

    static func run(cases: [EvalCase], engines: [any SentenceEngine], json: String?) async {
        var results: [[Outcome?]] = []  // [đường][câu]
        for engine in engines {
            var row: [Outcome?] = []
            var errors: [String: Int] = [:]
            for (i, c) in cases.enumerated() {
                let start = Date()
                do {
                    let out = try await engine.fix(c.typed)
                    let ms = Date().timeIntervalSince(start) * 1000
                    row.append(Outcome(out: out, ms: ms, score: SentenceFilter.score(typed: c.typed, want: c.want, got: out)))
                } catch {
                    // Chỉ giữ tên loại lỗi (phần trước dấu ngoặc), không giữ nội dung kèm theo.
                    errors[String("\(error)".prefix { $0 != "(" }), default: 0] += 1
                    row.append(Outcome(out: c.typed, ms: Date().timeIntervalSince(start) * 1000,
                        score: SentenceFilter.score(typed: c.typed, want: c.want, got: c.typed), failed: true))
                }
                if (i + 1) % 50 == 0 { FileHandle.standardError.write("\(engine.name): \(i + 1)/\(cases.count)\n".data(using: .utf8)!) }
            }
            results.append(row)
            report(engine.name, cases, row)
            for (name, count) in errors.sorted(by: { $0.value > $1.value }) { print("  lỗi gọi: \(count) lần \(name)") }
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *), let a = engine as? AppleEngine, a.rescued > 0 { print("  \(a.rescued) câu bị từ chối rồi được trả lời khi hỏi lại") }
            #endif
        }
        print("\nGhi chú: mô hình của macOS chạy trong tiến trình của hệ thống, bộ nhớ của nó không đo được từ đây.")
        disagreements(cases, engines, results)
        if let json { write(json, cases, engines, results) }
    }

    static func report(_ name: String, _ cases: [EvalCase], _ row: [Outcome?]) {
        print("\n== \(name) ==")
        print("loại          số câu  câu đúng  âm tiết đúng  bỏ sót (trên lỗi)  sửa bậy/1000 âm tiết  đổi số từ  lỗi gọi")
        var kinds: [String] = []
        for c in cases where !kinds.contains(c.kind) { kinds.append(c.kind) }
        func line(_ label: String, _ picked: [Int]) {
            var s = SentenceFilter.Score(), exact = 0, reshaped = 0, failed = 0
            for i in picked {
                guard let o = row[i] else { continue }
                if o.failed { failed += 1 }
                s.syllables += o.score.syllables
                s.right += o.score.right
                s.errors += o.score.errors
                s.missed += o.score.missed
                s.harmed += o.score.harmed
                if o.score.exact { exact += 1 }
                if o.score.reshaped { reshaped += 1 }
            }
            let n = max(picked.count, 1)
            let missed = s.errors == 0 ? "      -" : String(format: "%6.1f%%", 100 * Double(s.missed) / Double(s.errors))
            print(
                label.padding(toLength: 13, withPad: " ", startingAt: 0)
                    + String(format: "%7d  %7.1f%%  %11.1f%%  %@ (%d)", picked.count, 100 * Double(exact) / Double(n),
                        100 * Double(s.right) / Double(max(s.syllables, 1)), missed, s.errors).padding(toLength: 58, withPad: " ", startingAt: 0)
                    + String(format: "%14.1f  %15d  %7d", 1000 * Double(s.harmed) / Double(max(s.syllables, 1)), reshaped, failed))
        }
        for kind in kinds { line(kind, cases.indices.filter { cases[$0].kind == kind }) }
        line("TỔNG", Array(cases.indices))
        let times = row.compactMap { $0?.failed == false ? $0?.ms : nil }
        if let first = times.first {
            let rest = times.dropFirst().sorted()
            print(String(format: "  thời gian mỗi câu: lần đầu %.1f ms; các lần sau trung vị %.1f ms, p95 %.1f ms", first, percentile(rest, 0.5), percentile(rest, 0.95)))
        }
    }

    /// Những câu mà các đường cho kết quả đúng / sai khác nhau (tối đa 25 câu).
    static func disagreements(_ cases: [EvalCase], _ engines: [any SentenceEngine], _ results: [[Outcome?]]) {
        guard engines.count > 1 else { return }
        let differing = cases.indices.filter { i in Set(results.map { $0[i]?.score.exact ?? false }).count > 1 }
        print("\n\(differing.count) câu mà các đường đúng / sai khác nhau" + (differing.count > 25 ? " (in 25 câu đầu):" : ":"))
        for i in differing.prefix(25) {
            print("  [\(cases[i].kind)] \(cases[i].typed)\n      đúng: \(cases[i].want)")
            for (e, engine) in engines.enumerated() {
                let o = results[e][i]
                print("      \(o?.score.exact == true ? "ĐÚNG" : "SAI ") \(engine.name): \(o?.failed == true ? "(lỗi gọi, giữ nguyên câu)" : o?.out ?? "")")
            }
        }
    }

    static func write(_ path: String, _ cases: [EvalCase], _ engines: [any SentenceEngine], _ results: [[Outcome?]]) {
        let rows: [[String: Any]] = cases.indices.map { i in
            var per: [String: Any] = [:]
            for (e, engine) in engines.enumerated() {
                guard let o = results[e][i] else { continue }
                per[engine.name] = ["out": o.out, "ms": (o.ms * 10).rounded() / 10, "exact": o.score.exact, "missed": o.score.missed, "harmed": o.score.harmed, "failed": o.failed]
            }
            return ["typed": cases[i].typed, "want": cases[i].want, "kind": cases[i].kind, "results": per]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
            (try? data.write(to: URL(fileURLWithPath: path))) != nil
        else { return print("Không ghi được \(path).") }
        print("Đã ghi kết quả từng câu vào \(path).")
    }
}
