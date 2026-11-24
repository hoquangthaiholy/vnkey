import Foundation
import VNEngine
import VNKeyCore

// vnkey-tool type [tuỳ chọn] "<chuỗi phím>"   Gõ lại chuỗi phím qua engine, in kết quả trên màn hình.
//                                              "<" = Backspace, "~" = phím đổi từ vừa gõ, "\n" "\t" như thường.
// vnkey-tool bench [tuỳ chọn]                  Đo thời gian xử lý mỗi phím.
// vnkey-tool convert [--from X] [--to Y] [--strip] "<văn bản>"   Chuyển bảng mã (unicode, decomposed, tcvn3, vni, viqr).
// Tuỳ chọn: --vni  --brackets  --no-w  --no-predict  --no-lexicon  --trace  --cap  --tidy  --expand  --modern

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}

var config = Config()
if flag("--vni") { config.method = .vni }
if flag("--brackets") { config.bracketKeys = true }
if flag("--no-predict") { config.predict = false }
if flag("--no-w") { config.standaloneW = false }
if flag("--cap") { config.autoCapitalize = true }
if flag("--tidy") { config.tidyPunctuation = true }
if flag("--expand") { config.expandTeen = true }
if flag("--modern") { config.modernTone = true }
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

default:
    print("cách dùng: vnkey-tool type [--vni] [--trace] [--no-lexicon] \"<chuỗi phím>\" | vnkey-tool bench"
        + " | vnkey-tool convert [--from <bảng mã>] [--to <bảng mã>] [--strip] \"<văn bản>\"")
    exit(2)
}
