import Foundation
import VNEngine

#if canImport(FoundationModels)
import FoundationModels
#endif

// Bộ đo chung cho việc sửa cả câu: cùng một bộ câu, nhiều "đường" sửa (thuật toán trên máy, mô hình của macOS, và
// sau này là mô hình riêng), cùng một cách chấm. Bộ câu nằm trong `Eval/` ở gốc dự án (xem `Eval/README.md`).

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

/// Thuật toán không dùng mô hình (`Proofreader.restore`).
struct LocalEngine: SentenceEngine {
    let name = "local"
    let reader = Proofreader()
    init(lexicon: Lexicon?) { reader.lexicon = lexicon }
    func fix(_ text: String) async throws -> String { reader.restore(text) }
}

/// Kết quả tính sẵn của một mô hình chạy ngoài công cụ này (tệp `câu gõ <TAB> kết quả`, ví dụ từ
/// `Training/fixer.py predict`). `filtered`: qua `SentenceFilter.merge` như mô hình của macOS. Thời gian đo ở đây vô nghĩa.
struct FileEngine: SentenceEngine {
    let filtered: Bool
    let answers: [String: String]
    var name: String { filtered ? "model" : "model-raw" }
    struct Missing: Error {}
    init?(path: String, filtered: Bool) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var map: [String: String] = [:]
        for line in text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isNewline) {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            if f.count >= 2 { map[String(f[0])] = String(f[1]) }
        }
        self.answers = map
        self.filtered = filtered
    }
    func fix(_ text: String) async throws -> String {
        guard let raw = answers[text] else { throw Missing() }
        return filtered ? SentenceFilter.merge(original: text, proposed: raw) : raw
    }
}

/// THỬ NGHIỆM: `Proofreader.restore` có thêm điểm của mô hình tự train cho từng từ (tệp JSON mỗi dòng một câu, từ
/// `Training/fixer.py predict --scores`). Thời gian đo ở đây chỉ là phần của `restore`.
final class HybridEngine: SentenceEngine {
    let name = "hybrid"
    let reader = Proofreader()
    var scores: [String: [[String: Double]]] = [:]
    /// Số câu mà mô hình và `restore` tách ra số từ khác nhau (khi đó `restore` chạy không có mô hình).
    var mismatched = 0

    init?(path: String, lexicon: Lexicon?, weight: Double, floor: Double, adds: Int) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let typed = row["typed"] as? String, let words = row["words"] as? [[String: Double]]
            else { continue }
            scores[typed.precomposedStringWithCanonicalMapping] = words.map { word in
                var out: [String: Double] = [:]
                for (w, lp) in word { out[w.isEmpty ? "" : (Charset.syllableKey(w) ?? w)] = lp }
                return out
            }
        }
        reader.lexicon = lexicon
        reader.guideWeight = weight
        reader.guideFloor = floor
        reader.guideAdds = adds
    }

    func fix(_ text: String) async throws -> String {
        let hints = scores[text]
        reader.guide = { [unowned self] words in
            guard let hints else { return nil }
            if hints.count != words.count { self.mismatched += 1 }
            return hints
        }
        return reader.restore(text)
    }
}

#if canImport(FoundationModels)
/// Mô hình trên máy của macOS. `filtered`: qua `SentenceFilter.merge` như trong ứng dụng; không thì lấy nguyên câu.
@available(macOS 26.0, *)
struct AppleEngine: SentenceEngine {
    let filtered: Bool
    var name: String { filtered ? "apple" : "apple-raw" }
    func fix(_ text: String) async throws -> String {
        // Mỗi câu một phiên mới: câu trước không ảnh hưởng câu sau.
        let session = LanguageModelSession(instructions: SentenceFilter.instructions)
        let answer = try await session.respond(to: text, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 200))
        let raw = answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
    /// Tham số của đường ghép (`--guide-weight`, `--guide-floor`, `--guide-adds`).
    static var guide = (weight: 2.0, floor: -10.0, adds: 2)

    static func engines(_ list: String, lexicon: Lexicon?) -> [any SentenceEngine] {
        // Nhiều đường thì ngăn bằng dấu phẩy: `local,apple,file:ket-qua.tsv`.
        list.split(separator: ",").flatMap { one(String($0), lexicon: lexicon) }
    }

    private static func one(_ wanted: String, lexicon: Lexicon?) -> [any SentenceEngine] {
        var out: [any SentenceEngine] = []
        if wanted.hasPrefix("file:") {
            let path = String(wanted.dropFirst(5))
            guard let raw = FileEngine(path: path, filtered: false), let merged = FileEngine(path: path, filtered: true) else {
                print("Không đọc được \(path).")
                return []
            }
            return [merged, raw]
        }
        if wanted.hasPrefix("hybrid:") {
            guard let e = HybridEngine(path: String(wanted.dropFirst(7)), lexicon: lexicon, weight: guide.weight, floor: guide.floor, adds: guide.adds)
            else {
                print("Không đọc được \(wanted.dropFirst(7)).")
                return []
            }
            return [e]
        }
        let all = wanted == "all"
        if all || wanted == "local" { out.append(LocalEngine(lexicon: lexicon)) }
        if all || wanted.hasPrefix("apple") {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                if case .available = SystemLanguageModel.default.availability {
                    if all || wanted == "apple" { out.append(AppleEngine(filtered: true)) }
                    if all || wanted == "apple-raw" { out.append(AppleEngine(filtered: false)) }
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

    /// Bộ nhớ đỉnh của tiến trình này, tính bằng MB.
    static func peakMemory() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576
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
            if let h = engine as? HybridEngine, h.mismatched > 0 { print("  \(h.mismatched) câu tách từ lệch với mô hình: chạy không có mô hình") }
            if engine is LocalEngine { print(String(format: "  bộ nhớ đỉnh của tiến trình sau đường này: %.0f MB", peakMemory())) }
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
