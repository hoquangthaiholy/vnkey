import Testing

@testable import VNEngine

/// Từ điển giả cho test (app thật dùng NSSpellChecker).
final class FakeLexicon: Lexicon {
    let en: Set<String> = ["string", "window", "class", "meeting", "form", "pass", "as", "ass", "off", "see", "this", "fair", "data", "user", "test", "error"]
    let vi: Set<String> = ["tiếng", "việt", "người", "được", "chào", "bạn", "thí", "tét", "á", "là", "sẽ"]
    static let shared = FakeLexicon()
    func isEnglish(_ w: String) -> Bool { en.contains(w) }
    func isVietnamese(_ w: String) -> Bool { vi.contains(w) }
}

/// Giả lập màn hình: gõ từng ký tự, "<" = Backspace, "~" = phím đổi qua lại (toggleLast).
func run(_ keys: String, _ cfg: Config = Config(), lexicon: Lexicon? = nil, engine: Engine? = nil) -> String {
    let e = engine ?? Engine(config: cfg)
    e.lexicon = lexicon
    var buf = ""
    for ch in keys {
        let out: Output
        switch ch {
        case "<": out = e.backspace()
        case "~": out = e.toggleLast()
        default: out = e.type(ch)
        }
        buf.removeLast(min(out.backspaces, buf.count))
        buf += out.text
        if out.passKey {
            if ch == "<" { if !buf.isEmpty { buf.removeLast() } } else if ch != "~" { buf.append(ch) }
        }
    }
    return buf
}

@Suite struct Telex {
    @Test(arguments: [
        ("tieengs vieetj", "tiếng việt"),
        ("Vieetj Nam", "Việt Nam"),
        ("dduwowcj", "được"), ("dduwocj", "được"), ("dduocwj", "được"),
        ("nguwowif", "người"), ("muowif", "mười"), ("thuowng", "thương"), ("thuowr", "thuở"),
        ("ruouwj", "rượu"), ("muaw", "mưa"), ("hoawcj", "hoặc"), ("quowr", "quở"),
        ("nhw", "như"), ("tw", "tư"), ("uwu", "ưu"), ("w", "ư"), ("ww", "w"),
        ("hoaf", "hòa"), ("thuyr", "thủy"), ("toans", "toán"), ("quyeets", "quyết"), ("quas", "quá"),
        ("gias", "giá"), ("gif", "gì"), ("giuwax", "giữa"), ("gieengs", "giếng"), ("cuar", "của"),
        ("khuyur", "khuỷu"), ("ngoafi", "ngoài"), ("nghieeng", "nghiêng"), ("yeeu", "yêu"),
        ("tiengse", "tiếng"), ("tieesng", "tiếng"), ("truongwf", "trường"),
        ("DDAAY", "ĐÂY"), ("Dduwowngf", "Đường"),
        ("tieengsf", "tiềng"),  // đổi thanh
        ("muowns", "mướn"), ("muownso", "muốn"),  // sửa dấu mũ/móc gõ nhầm
        ("tiengz", "tiengz"), ("tieengsz", "tiêng"),
    ])
    func compose(keys: String, want: String) { #expect(run(keys) == want) }

    @Test func modernTone() {
        var c = Config(); c.modernTone = true
        #expect(run("hoaf thuyr", c) == "hoà thuỷ")
    }

    @Test(arguments: [
        ("aaa", "aa"), ("ddd", "dd"), ("aww", "aw"), ("uww", "uw"), ("ooo", "oo"), ("tass", "tas"),
    ])
    func repeatCancels(keys: String, want: String) { #expect(run(keys) == want) }

    @Test(arguments: [
        ("tieengs<", "tiến"), ("tieengs<<<<<<", ""), ("hoanf<", "hòa"), ("dduwowcj<<", "đự"),
        ("vieetj <s", "viết"),  // quay lại từ trước và sửa thanh
        ("tieeng  <<s", "tiếng"),
        ("as<<", ""),
    ])
    func backspace(keys: String, want: String) { #expect(run(keys) == want) }
}

@Suite struct MixedLanguage {
    @Test(arguments: [
        // Phát hiện sớm: không thể là tiếng Việt -> hiện phím gốc ngay khi đang gõ
        ("string", "string"), ("window", "window"), ("class", "class"), ("your", "your"),
        ("address", "address"), ("windows", "windows"),
        // Phát hiện khi kết thúc từ
        ("user ", "user "), ("data ", "data "), ("good ", "good "), ("need ", "need "),
        ("text ", "text "), ("next ", "next "), ("for ", "for "), ("first ", "first "),
        ("add ", "add "), ("yes ", "yes "), ("more.", "more."), ("is,", "is,"),
        ("banana ", "banana "), ("express ", "express "),
        // Xen kẽ
        ("tooi ddang fix bug cuar user ", "tôi đang fix bug của user "),
        ("meeting lucs 3h chieeuf nay", "meeting lúc 3h chiều nay"),
    ])
    func english(keys: String, want: String) { #expect(run(keys) == want) }

    @Test(arguments: [
        ("ddc ", "đc "), ("ko dc", "ko dc"), ("j z", "j z"), ("zaayj ", "zậy "), ("dzoo ", "dzô "),
        ("ntn", "ntn"), ("hok bik", "hok bik"), ("ddt ", "đt "), ("jowf ", "jờ "),
    ])
    func teen(keys: String, want: String) { #expect(run(keys) == want) }

    @Test func teenExpansion() {
        var c = Config(); c.expandTeen = true
        #expect(run("Ko ddc ddaau ", c) == "Không được đâu ")
    }

    @Test func macros() {
        var c = Config(); c.macros = ["vn": "Việt Nam"]
        #expect(run("vn, ", c) == "Việt Nam, ")
    }

    @Test(arguments: [
        ("pass ", "pass "),  // "pas" không phải từ, "pass" là tiếng Anh
        ("as ", "as "), ("tass ", "tas "),
        ("off ", "off "), ("error ", "error "),
        ("see ", "see "),  // "sê" không có trong từ điển Việt
        ("this ", "thí "),  // mơ hồ thật sự: giữ tiếng Việt
        ("laf ", "là "),
    ])
    func withLexicon(keys: String, want: String) { #expect(run(keys, lexicon: FakeLexicon.shared) == want) }

    @Test func toggleAndLearn() {
        let e = Engine()
        let lex = FakeLexicon()
        #expect(run("this ~", lexicon: lex, engine: e) == "this ")  // đổi lại phím gốc
        e.reset()
        #expect(run("this ", lexicon: lex, engine: e) == "this ")  // đã học
        #expect(run("~", lexicon: lex, engine: e) == "thí ")  // đổi ngược lại
        e.reset()
        #expect(run("this ", lexicon: lex, engine: e) == "thí ")
        e.reset()
        #expect(run("tets~", lexicon: lex, engine: e) == "tets")  // đang gõ dở
    }
}

@Suite struct VNI {
    @Test(arguments: [
        ("tie61ng vie65t", "tiếng việt"), ("d9u7o75c", "được"), ("ngu7o7i2", "người"),
        ("hoa85c", "hoặc"), ("dung9", "đung"), ("a66", "a6"), ("so61 1", "số 1"), ("nam8 2024", "năm 2024"),
        ("a1<", ""),
    ])
    func compose(keys: String, want: String) {
        var c = Config(); c.method = .vni
        #expect(run(keys, c) == want)
    }
}

@Suite struct Experience {
    let lex = FakeLexicon.shared

    @Test(arguments: [
        ("string window this ", "string window this "),  // đang gõ tiếng Anh: "this" theo tiếng Anh
        ("string laf this ", "string là thí "),  // xen một từ Việt: quay về mặc định
        ("string this ", "string thí "),
    ])
    func languageContext(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }

    @Test(arguments: [
        ("@user ", "@user "), ("#test ", "#test "), ("a/user/more ", "a/user/more "),
        ("file.is ", "file.is "), ("bar_as ", "bar_as "), ("5s ", "5s "), ("mp3s ", "mp3s "),
        ("user ", "user "), ("@ laf ", "@ là "), ("@u<laf ", "@laf "),
    ])
    func codeContext(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }

    @Test(arguments: [
        ("tieegns ", "tiếng "), ("veitj ", "veitj "), ("vieejt ", "việt "), ("nugowfi ", "người "),
        ("dduwojwc ", "được "), ("form ", "form "), ("wnidow ", "wnidow "),
    ])
    func transposition(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }

    @Test(arguments: [
        ("chaof. banj ", "chào. Bạn "), ("chaof! banj", "chào! Bạn"), ("chaof... banj", "chào... bạn"),
        ("chaof\nbanj", "chào\nBạn"), ("chaof banj", "chào bạn"), ("chaof. b<banj", "chào. bạn"),
        ("v.v. banj", "v.v. bạn"), ("chaof.banj", "chào.banj"),
    ])
    func autoCapitalize(keys: String, want: String) {
        var c = Config(); c.autoCapitalize = true
        #expect(run(keys, c) == want)
    }

    @Test(arguments: [
        ("chaof , banj", "chào, bạn"), ("chaof .", "chào."), ("chaof  ,", "chào  ,"), ("chaof ,<s", "cháo"),
    ])
    func tidyPunctuation(keys: String, want: String) {
        var c = Config(); c.tidyPunctuation = true
        #expect(run(keys, c) == want)
    }
}
