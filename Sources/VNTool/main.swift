import Foundation
import VNEngine
import VNKeyCore

// vnkey-tool type [tuỳ chọn] "<chuỗi phím>"   Gõ lại chuỗi phím qua engine, in kết quả trên màn hình.
//                                              "<" = Backspace, "~" = phím đổi từ vừa gõ, "\n" "\t" như thường.
// vnkey-tool bench [tuỳ chọn]                  Đo thời gian xử lý mỗi phím.
// vnkey-tool fix-sentence ["<câu>"]           THỬ NGHIỆM: sửa cả câu bằng mô hình chạy trên máy của macOS.
// vnkey-tool eval [--engine local|apple|apple-raw|all]   Đo các đường sửa câu trên bộ câu trong `Eval/`.
// vnkey-tool eval-make <tệp câu> [--count N] [--seed S]  Sinh `Eval/generated.tsv` từ một tệp câu tiếng Việt sạch.
// vnkey-tool check [--english] "<văn bản>"     Soát lỗi một đoạn văn bản (`Proofreader`), in từng chỗ nghi sai.
// vnkey-tool convert [--from X] [--to Y] [--strip] "<văn bản>"   Chuyển bảng mã (unicode, decomposed, tcvn3, vni, viqr).
// Tuỳ chọn: --vni  --brackets  --no-w  --no-lexicon  --trace  --cap  --tidy  --expand  --modern  --smart

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}

var config = Config()
if flag("--vni") { config.method = .vni }
if flag("--brackets") { config.bracketKeys = true }
if flag("--no-w") { config.standaloneW = false }
if flag("--cap") { config.autoCapitalize = true }
if flag("--tidy") { config.tidyPunctuation = true }
if flag("--expand") { config.expandTeen = true }
if flag("--modern") { config.modernTone = true }
// Bảng gõ tắt thông minh mẫu, để thử `\\tên` từ dòng lệnh.
if flag("--smart") { config.smartMacros = ["homnay": "[ngay]", "bgio": "[gio]", "ngay": "[ngaydai]", "amlich": "[amlich]"] }
let trace = flag("--trace")
let lexicon: SystemLexicon? = flag("--no-lexicon") ? nil : SystemLexicon()

func makeEngine() -> Engine {
    let e = Engine(config: config)
    e.lexicon = lexicon
    return e
}

/// Áp một phím lên "màn hình" giả, giống hệt cách app gửi phím.
func apply(_ ch: Character, _ e: Engine, _ screen: inout String) -> Output {
    let out: Output
    switch ch {
    case "<": out = e.backspace()
    case "~": out = e.toggleLast()
    default: out = e.type(ch)
    }
    screen.removeLast(min(out.backspaces, screen.count))
    screen += out.text
    if out.passKey {
        if ch == "<" { if !screen.isEmpty { screen.removeLast() } } else if ch != "~" { screen.append(ch) }
    }
    return out
}

switch args.first {
case "type":
    guard args.count >= 2 else { fatalError("thiếu chuỗi phím") }
    let keys = args[1].replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
    let e = makeEngine()
    var screen = ""
    for ch in keys {
        let out = apply(ch, e, &screen)
        if trace {
            let what = out.isPass ? "pass" : "bs=\(out.backspaces) text=\"\(out.text)\" passKey=\(out.passKey)"
            print("\(ch == "\n" ? "⏎" : String(ch))  \(what)  | \(e.debugState)  => \"\(screen)\"\(e.note.isEmpty ? "" : "  [\(e.note)]")")
        }
    }
    print(screen)

case "check":
    let english = flag("--english")
    guard args.count >= 2 else { fatalError("thiếu văn bản") }
    let reader = Proofreader()
    reader.config = config
    reader.lexicon = lexicon
    reader.checkEnglish = english
    let start = DispatchTime.now().uptimeNanoseconds
    let issues = reader.check(args[1])
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    for i in issues {
        print("\(i.range.lowerBound)..<\(i.range.upperBound) [\(i.kind.rawValue)] \"\(i.text)\" -> \(i.suggestions.joined(separator: " | "))")
    }
    FileHandle.standardError.write("\(issues.count) chỗ, \(String(format: "%.2f", ms)) ms\n".data(using: .utf8)!)

case "bench":
    let sample =
        "tooi ddang fix bug cuar user trong file string.swift, sau ddos meeting lucs 3h chieeuf nay. "
        + "Nguwowif dungf Vieetj hay gox xen kex tieengs Anh: this window class error, dduwowcj khoong? "
        + "ko dc ddaau nhes, zaayj thif thooi. tieegns nugowfi @user #test a/b/c foo_bar\n"
        // Xoá lùi giữa từ, gõ nhầm rồi sửa, quay lại từ trước, và vài từ dài.
        + "nghieengx<<<eeng truwowngf thii<chs vieejk<t khoong <<<<ng internationalization responsibilities\n"
    let rounds = 200
    let e = makeEngine()
    var screen = ""
    for ch in sample { _ = apply(ch, e, &screen) }  // làm nóng bộ đệm từ điển
    var worst: UInt64 = 0, total: UInt64 = 0, count = 0
    for _ in 0..<rounds {
        e.reset(); screen = ""
        for ch in sample {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = apply(ch, e, &screen)
            let dt = DispatchTime.now().uptimeNanoseconds - t0
            total += dt; worst = max(worst, dt); count += 1
        }
    }
    let avg = Double(total) / Double(count) / 1000
    print(String(format: "phím: %d  trung bình: %.2f µs/phím  chậm nhất: %.1f µs  từ điển: %@",
                 count, avg, Double(worst) / 1000, lexicon == nil ? "tắt" : "bật"))
    // Ngân sách: callback của event tap phải xong trong vài trăm µs; macOS tắt tap nếu chậm cỡ giây.
    if avg > 50 { print("CẢNH BÁO: trung bình vượt ngân sách 50 µs/phím"); exit(1) }

case "bench-parts":
    // Các phần ngoài engine đo được mà không cần giao diện.
    func ms(_ body: () -> Void) -> Double {
        let t0 = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
    }
    let lex = SystemLexicon()
    print(String(format: "từ điển, lần gọi ĐẦU tiên (en): %.1f ms", ms { _ = lex.isEnglish("window") }))
    print(String(format: "từ điển, lần gọi ĐẦU tiên (vi): %.1f ms", ms { _ = lex.isVietnamese("tiếng") }))
    let words = (0..<300).map { "tu\($0 % 7)word\($0)" }
    let cold = ms { for w in words { _ = lex.isEnglish(w) } } / 300
    let warm = ms { for w in words { _ = lex.isEnglish(w) } } / 300
    print(String(format: "từ điển, từ chưa gặp: %.3f ms/từ   từ đã nhớ: %.4f ms/từ", cold, warm))

    Log.url = FileManager.default.temporaryDirectory.appendingPathComponent("vnkey-bench-\(getpid()).log")
    Log.enabled = true
    let line = "KEY code=31 ch=\"o\" mods= app=com.example.app | raw=\"toi\" shown=\"toi\" hist=0 -> bs=2 text=\"ôi\" passKey=false | raw=\"toio\" shown=\"tôi\" hist=0"
    Log.write(line)
    let n = 20000
    var worst = 0.0
    let total = ms { for _ in 0..<n { worst = max(worst, ms { Log.write(line) }) } }
    print(String(format: "ghi log: %.2f µs/dòng trung bình, chậm nhất %.2f ms", total * 1000 / Double(n), worst))
    Log.flush()
    try? FileManager.default.removeItem(at: Log.url)

case "convert":
    // Bảng mã: unicode, decomposed, tcvn3, vni, viqr. Thiếu --from thì tự đoán.
    func option(_ name: String) -> Charset? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        let value = args[i + 1]
        args.removeSubrange(i...i + 1)
        guard let cs = Charset(rawValue: value) else { fatalError("không biết bảng mã \"\(value)\"") }
        return cs
    }
    let from = option("--from"), to = option("--to") ?? .unicode
    let strip = flag("--strip")
    guard args.count >= 2 else { fatalError("thiếu văn bản") }
    let source = from ?? Charset.detect(args[1]) ?? .unicode
    if from == nil { print("đoán: \(source.rawValue)") }
    let unicode = Charset.convert(args[1], from: source, to: .unicode)
    print(Charset.convert(strip ? Charset.stripMarks(unicode) : unicode, from: .unicode, to: to))

case "syllables":
    // Lọc một tệp tần suất ("từ số_lần" mỗi dòng) lấy các âm tiết tiếng Việt hợp lệ, gộp theo khoá chuẩn, in
    // "khoá số_lần" giảm dần. Dùng để sinh lại `CommonWordsData.swift` (xem chú thích ở đầu tệp đó).
    guard args.count >= 2, let text = try? String(contentsOfFile: args[1], encoding: .utf8) else { fatalError("thiếu tệp") }
    let floor = args.count >= 3 ? Int(args[2]) ?? 100 : 100
    var counts: [String: Int] = [:]
    for line in text.split(separator: "\n") {
        let p = line.split(separator: " ")
        guard p.count == 2, let n = Int(p[1]), let key = Charset.syllableKey(String(p[0]).lowercased()) else { continue }
        counts[key, default: 0] += n
    }
    for (key, n) in counts.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) where n >= floor { print(key, n) }

case "pairs":
    // Đếm cặp âm tiết kề nhau trong một kho văn bản (mỗi dòng một câu) và in ra khối dữ liệu của
    // `CommonPairsData.swift` (xem chú thích ở đầu tệp đó). Tham số: tệp văn bản, ngưỡng số lần (mặc định 20).
    guard args.count >= 2, let text = try? String(contentsOfFile: args[1], encoding: .utf8) else { fatalError("thiếu tệp") }
    let floor = args.count >= 3 ? Int(args[2]) ?? 20 : 20
    let r = CommonPairs.encode(text: text, floor: floor)
    print("    static let floor = \(floor)")
    print("    static let pairCount = \(r.pairs)")
    print("    static let data = \"\"\"")
    var rest = Substring(r.base64)
    while !rest.isEmpty {
        print("        " + rest.prefix(120))
        rest = rest.dropFirst(120)
    }
    print("        \"\"\"")
    FileHandle.standardError.write("\(r.words) từ, \(r.pairs) cặp từ \(floor) lần trở lên, \(r.base64.count * 3 / 4) byte\n".data(using: .utf8)!)

case "compounds":
    // Dựng từ điển từ ghép từ một danh sách từ (mỗi dòng một từ) và in ra phần thân của `CompoundsData.swift`.
    guard args.count >= 2, let list = try? String(contentsOfFile: args[1], encoding: .utf8) else { fatalError("thiếu tệp") }
    let r = Compounds.encode(list: list.precomposedStringWithCanonicalMapping)
    func block(_ name: String, _ text: String, _ width: Int) {
        print("    static let \(name) = \"\"\"")
        var rest = Substring(text)
        while !rest.isEmpty {
            // Cắt ở khoảng trắng để không chẻ đôi một âm tiết.
            var cut = rest.index(rest.startIndex, offsetBy: min(width, rest.count))
            if cut < rest.endIndex, let space = rest[..<cut].lastIndex(of: " ") { cut = space }
            print("        " + rest[..<cut])
            rest = rest[cut...].drop(while: { $0 == " " })
        }
        print("        \"\"\"")
    }
    print("    static let baseCount = \(r.base)")
    print("    static let compoundCount = \(r.compounds)")
    block("words", r.words.joined(separator: " "), 120)
    block("parts", r.parts.joined(separator: " "), 120)
    block("data", r.base64, 120)
    FileHandle.standardError.write(
        "\(r.compounds) từ ghép, \(r.words.count) từ đơn hiếm, \(r.parts.count) âm tiết chỉ có trong từ ghép, \(r.base64.count * 3 / 4) byte nhị phân\n".data(using: .utf8)!)

case "rare-words":
    // So các ngưỡng gạch chân từ đơn hiếm: với mỗi từ đơn trong danh sách từ mà `Compounds` coi là hiếm, in từ đó,
    // đề nghị đứng đầu khi soát nó đứng một mình, và số lần đề nghị ấy gặp trong kho ngữ liệu (tab ngăn cách).
    guard args.count >= 2, let list = try? String(contentsOfFile: args[1], encoding: .utf8) else { fatalError("thiếu tệp") }
    let reader = Proofreader()
    reader.config = config
    reader.rareWordFloor = 0
    var seen = Set<String>()
    for line in list.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isNewline) {
        let word = line.lowercased()
        guard !word.contains(" "), Compounds.isRareWord(word), seen.insert(word).inserted else { continue }
        guard let issue = reader.check(word).first, let top = issue.suggestions.first else {
            print("\(word)\t\t0\t-")
            continue
        }
        print("\(word)\t\(top)\t\(Proofreader.frequency(of: top))\t\(issue.kind.rawValue)")
    }

case "train-tables":
    // Bảng cho việc train mô hình sửa câu (`Training/`): âm tiết <TAB> số lần <TAB> lẫn âm <TAB> lẫn thanh
    // <TAB> lẫn âm kể cả ra âm tiết ngoài bảng <TAB> mọi dấu thanh khác.
    for row in Proofreader().confusionTable() {
        print("\(row.word)\t\(row.count)\t\(row.sound.joined(separator: " "))\t\(row.tone.joined(separator: " "))"
            + "\t\(row.anySound.joined(separator: " "))\t\(row.anyTone.joined(separator: " "))")
    }

case "eval-make":
    // Sinh bộ câu kiểm tra từ một tệp câu tiếng Việt sạch: `vnkey-tool eval-make <tệp> [--count 400] [--seed 1]`.
    var rest = Array(args.dropFirst())
    func option(_ name: String) -> String? {
        guard let i = rest.firstIndex(of: name), i + 1 < rest.count else { return nil }
        defer { rest.removeSubrange(i...(i + 1)) }
        return rest[i + 1]
    }
    let count = option("--count").flatMap(Int.init) ?? 400
    let seed = option("--seed").flatMap(UInt64.init) ?? 1
    guard let path = rest.first else { fatalError("thiếu tệp câu") }
    EvalSet.make(from: path, count: count, seed: seed)

case "eval":
    // Đo các đường sửa câu trên bộ câu trong `Eval/`:
    // `vnkey-tool eval [--engine local|apple|apple-raw|all] [--set <tệp.tsv>] [--kind <loại>] [--limit N] [--json <tệp>]`.
    var rest = Array(args.dropFirst())
    func option(_ name: String) -> String? {
        guard let i = rest.firstIndex(of: name), i + 1 < rest.count else { return nil }
        defer { rest.removeSubrange(i...(i + 1)) }
        return rest[i + 1]
    }
    let wanted = option("--engine") ?? "all"
    var cases: [EvalCase] = []
    if let set = option("--set") {
        guard let loaded = EvalSet.load(set) else { fatalError("không đọc được \(set)") }
        cases = loaded
    } else {
        for path in [EvalSet.generated, EvalSet.handwritten] {
            if let loaded = EvalSet.load(path) { cases += loaded } else { print("Không có \(path) (chạy từ gốc dự án).") }
        }
    }
    if let kind = option("--kind") { cases = cases.filter { $0.kind == kind } }
    if let limit = option("--limit").flatMap(Int.init) { cases = Array(cases.prefix(limit)) }
    let json = option("--json")
    if let w = option("--guide-weight").flatMap(Double.init) { EvalRunner.guide.weight = w }
    if let f = option("--guide-floor").flatMap(Double.init) { EvalRunner.guide.floor = f }
    if let a = option("--guide-adds").flatMap(Int.init) { EvalRunner.guide.adds = a }
    let engines = EvalRunner.engines(wanted, lexicon: lexicon)
    guard !cases.isEmpty, !engines.isEmpty else { print("Không có câu hoặc không có đường nào để đo."); exit(1) }
    print("\(cases.count) câu, đường: \(engines.map(\.name).joined(separator: ", "))")
    let finished = DispatchSemaphore(value: 0)
    Task {
        await EvalRunner.run(cases: cases, engines: engines, json: json)
        finished.signal()
    }
    finished.wait()

case "fix-sentence":
    // THỬ NGHIỆM: sửa cả câu bằng mô hình chạy trên máy của macOS. Không có câu nào thì chạy bộ câu mẫu.
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
        var rest = Array(args.dropFirst())
        // `--local`: đường dự phòng không dùng mô hình (bảng cặp, từ ghép). `--task …`: thử một việc khác với câu.
        if let i = rest.firstIndex(of: "--local") {
            rest.remove(at: i)
            SentenceFixer.runLocal(rest, lexicon: lexicon)
        } else if let i = rest.firstIndex(of: "--task"), i + 1 < rest.count, let task = SentenceTask(rawValue: rest[i + 1]) {
            rest.removeSubrange(i...(i + 1))
            SentenceFixer.run(task: task, rest)
        } else {
            SentenceFixer.run(rest)
        }
    } else {
        print("Cần macOS 26 trở lên.")
    }
    #else
    print("Bộ công cụ biên dịch này không có framework Foundation Models.")
    #endif

default:
    print("cách dùng: vnkey-tool type [--vni] [--trace] [--no-lexicon] \"<chuỗi phím>\" | vnkey-tool bench"
        + " | vnkey-tool convert [--from <bảng mã>] [--to <bảng mã>] [--strip] \"<văn bản>\"")
    exit(2)
}
