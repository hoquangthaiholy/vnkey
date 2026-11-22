import Foundation
import VNEngine

// vnkey-tool type [tuỳ chọn] "<chuỗi phím>"   Gõ lại chuỗi phím qua engine, in kết quả trên màn hình.
//                                              "<" = Backspace, "~" = phím đổi từ vừa gõ, "\n" "\t" như thường.
// vnkey-tool bench [tuỳ chọn]                  Đo thời gian xử lý mỗi phím.
// Tuỳ chọn: --vni  --no-lexicon  --trace  --cap  --tidy  --expand  --modern

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}

var config = Config()
if flag("--vni") { config.method = .vni }
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
            print("\(ch == "\n" ? "⏎" : String(ch))  \(what)  | \(e.debugState)  => \"\(screen)\"")
        }
    }
    print(screen)

case "bench":
    let sample =
        "tooi ddang fix bug cuar user trong file string.swift, sau ddos meeting lucs 3h chieeuf nay. "
        + "Nguwowif dungf Vieetj hay gox xen kex tieengs Anh: this window class error, dduwowcj khoong? "
        + "ko dc ddaau nhes, zaayj thif thooi. tieegns nugowfi @user #test a/b/c foo_bar\n"
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

default:
    print("cách dùng: vnkey-tool type [--vni] [--trace] [--no-lexicon] \"<chuỗi phím>\" | vnkey-tool bench")
    exit(2)
}
