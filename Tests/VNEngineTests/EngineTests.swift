import Testing

@testable import VNEngine

/// Từ điển giả cho test (app thật dùng NSSpellChecker).
final class FakeLexicon: Lexicon {
    let en: Set<String> = ["fix", "bug", "www", "cu3a", "nghi4a", "now", "how", "string", "window", "class", "meeting", "form", "pass", "as", "ass", "off", "see", "this", "fair", "data", "user", "test", "error"]
    let vi: Set<String> = ["của", "tôi", "nơ", "hơ", "sê", "tiếng", "việt", "người", "được", "chào", "bạn", "thí", "tét", "á", "là", "sẽ", "ban"]
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
        ("tieengs<", "tiến"), ("tieengs<<<<<<", ""), ("hoanf<", "hoà"), ("dduwowcj<<", "đư"),
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
        ("tieegns ", "tieegns "), ("veitj ", "veitj "), ("vieejt ", "việt "), ("nugowfi ", "nugowfi "),
        ("dduwojwc ", "được "), ("form ", "form "), ("wnidow ", "wnidow "),
    ])
    /// Gõ đảo hai phím không còn được tự sửa (2026-11-25): chữ để nguyên, bộ soát lỗi đề nghị (`Proofreading`).
    /// Gõ dấu tự do ("vieejt", "dduwojwc") là việc của `Composer`, vẫn chạy.
    func swappedKeysAreNotFixedWhileTyping(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }

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

/// Các lỗi tìm được khi mở rộng độ phủ (22/11/2026).
@Suite struct Regressions {
    let lex = FakeLexicon.shared

    /// VNI: chuỗi phím gốc có chữ số nên không bao giờ là "từ tiếng Anh", kể cả khi trình
    /// kiểm tra chính tả bỏ qua từ có số.
    @Test(arguments: [
        ("fix bug cu3a ", "fix bug của "), ("fix bug to6i ", "fix bug tôi "), ("tie61gn ", "tie61gn "),
    ])
    func vniDigitsAreNotEnglish(keys: String, want: String) {
        var c = Config(); c.method = .vni
        #expect(run(keys, c, lexicon: lex) == want)
    }

    /// "ww" huỷ thành "w"; gõ tiếp "w" là muốn chữ w thật (www), không phải "ư".
    @Test(arguments: [("www", "www"), ("www.vnexpress.net ", "www.vnexpress.net "), ("ww", "w"), ("wwa", "wa")])
    func tripleW(keys: String, want: String) { #expect(run(keys) == want) }

    /// Từ tiếng Anh rất phổ biến mà nghĩa tiếng Việt hiếm gặp.
    @Test(arguments: [("now ", "now "), ("how ", "how "), ("see ", "see ")])
    func commonEnglish(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }
}

@Suite struct Coverage {
    let lex = FakeLexicon.shared

    @Test(arguments: [
        ("DDAAY LAF", "ĐÂY LÀ"), ("Tooi ", "Tôi "), ("TOOI", "TÔI"), ("tOOI", "tÔI"), ("VIEETJ NAM", "VIỆT NAM"),
        ("Uw", "Ư"), ("W ", "Ư "), ("OWr", "Ở"), ("DDc ", "Đc "), ("Ddc ", "Đc "), ("HOAF", "HÒA"),
        ("Giangr", "Giảng"), ("QUAS", "QUÁ"), ("User ", "User "), ("String ", "String "),
    ])
    func uppercase(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }

    @Test(arguments: [
        ("tooi ddang<<<<< ", "tôi "), ("string<<<", "str"), ("user <<<<<", ""), ("user <s", "users"),
        ("tooi  ddi<<<<<s", "tố"), ("ddc<<", ""), ("ass<", "a"), ("a<<<b", "b"), ("tieengs<<<<<<<tooi", "tôi"),
        ("ww<", ""), ("window <<s", "windos"), ("muoons <<<<", "m"), ("<<<tooi", "tôi"),
    ])
    func backspace(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }

    @Test(arguments: [
        ("user ~", "ủe "), ("user ~~", "user "), ("toi ~~", "toi "), ("tooi dda~ng", "tôi ddang"), ("tooi ~", "tooi "),
    ])
    func toggle(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }

    @Test(arguments: [
        ("khoong? cos! ", "không? có! "), ("(tooi) ", "(tôi) "), ("\"tooi\" ", "\"tôi\" "), ("ddi-veef ", "đi-về "),
        ("a.b.c ", "a.b.c "), ("abc@gmail.com ", "abc@gmail.com "), ("tooi,ban ", "tôi,ban "),
        ("http://vnexpress.net/tin-tuc ", "http://vnexpress.net/tin-tuc "),
        ("3 thangs 5 nawm ", "3 tháng 5 năm "), ("20k ddoongf ", "20k đồng "), ("covid19 ", "covid19 "),
    ])
    func punctuation(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }

    @Test(arguments: [
        ("gioiws ", "giới "), ("quoocs ", "quốc "), ("uoongs nuwowcs ", "uống nước "), ("khuyeens ", "khuyến "),
        ("ruwowuj ", "rượu "), ("huow ", "huơ "), ("quyeenf ", "quyền "), ("oong ", "ông "), ("uyr ", "ủy "),
    ])
    func syllables(keys: String, want: String) { #expect(run(keys) == want) }

    @Test(arguments: [
        ("to6i d9ang fix bug cu3a user ", "tôi đang fix bug của user "), ("window ", "window "), ("mp3 ", "mp3 "),
        ("0912345678 ", "0912345678 "), ("ngay2 22/11/2026 ", "ngày 22/11/2026 "), ("a1b2 ", "a1b2 "),
        ("user1 ", "user1 "), ("h2o ", "h2o "), ("vie65t<1", "viế"), ("A6m ", "Âm "), ("D9A6Y", "ĐÂY"),
        ("tie61ng2 ", "tiềng "), ("web3 ", "web3 "), ("u7o7c1 ", "ước "), ("thuo73 ", "thuở "),
        ("Nghi4a ", "Nghĩa "),
    ])
    func vniMixed(keys: String, want: String) {
        var c = Config(); c.method = .vni
        #expect(run(keys, c, lexicon: lex) == want)
    }

    @Test(arguments: [
        ("xin chaof. toio ", "xin chào. Tôi "), ("ok. @user ", "ok. @user "), ("a. b ", "a. b "),
    ])
    func capitalizeCombos(keys: String, want: String) {
        var c = Config(); c.autoCapitalize = true
        #expect(run(keys, c, lexicon: lex) == want)
    }

    @Test func optionCombos() {
        var c = Config(); c.tidyPunctuation = true; c.expandTeen = true; c.autoCapitalize = true
        #expect(run("ko dc ddaau . j z ", c) == "không được đâu. Gì vậy ")
    }
}

/// Lỗi "lâu lâu không gõ được tiếng Việt" (22/11/2026): giữ phím xoá lùi qua "việt", "tiếng" làm engine
/// dời dấu thanh sang nguyên âm trước ("tiế" -> "tí"), buộc app nuốt phím xoá rồi tự phát phím xoá + chữ
/// trong lúc phím thật đang lặp; màn hình và engine lệch nhau từ đó.
@Suite struct BackspaceIsPlain {
    /// Gõ nhầm một phím làm từ thành nguyên văn; xoá phím nhầm đi thì phải gõ tiếp tiếng Việt được,
    /// không bắt người dùng xoá về tận khoảng trắng.
    @Test func leavesLiteralWhenTypoIsDeleted() {
        #expect(run("thii<chs ") == "thích ")
        #expect(run("thii<<<<tois ") == "tói ")
        #expect(run("vieejk<t ") == "việt ")
        #expect(run("tieesg<<ngs ") == "tiếng ")
        #expect(run("slide<<<<<tooi ") == "tôi ")
        // Xoá tiếp sau phím nhầm: màn hình vẫn khớp với engine.
        #expect(run("vieejk<<<<eetj ") == "việt ")
        // Đã chủ động gõ lặp để huỷ dấu thì không hiểu lại.
        #expect(run("assk<k ") == "ask ")
        // Xoá chưa hết phần sai thì vẫn nguyên văn.
        #expect(run("slide<<<s") == "sls")
        // Quay lại từ trước rồi gõ nhầm, xoá, gõ tiếp.
        #expect(run("thich <<<i<chs ") == "thích ")
    }

    static let words = [
        "tieengs", "vieetj", "dduwowcj", "hoanf", "nguwowif", "quyeets", "thuyr", "khuyur", "muoons", "giuwax",
        "DDAAY", "toio", "ruwowuj", "oong", "uyr", "hoaf", "user", "string", "ddc", "ass", "ww",
    ]

    /// Xoá lùi luôn chỉ xoá đúng một ký tự cuối: engine không bao giờ đòi sửa chữ khác.
    @Test(arguments: words) func neverRewrites(word: String) {
        for method in [Method.telex] {
            var c = Config(); c.method = method
            let e = Engine(config: c)
            var screen = ""
            for ch in word {
                let out = e.type(ch)
                screen.removeLast(min(out.backspaces, screen.count)); screen += out.text
                if out.passKey { screen.append(ch) }
            }
            while !screen.isEmpty {
                let out = e.backspace()
                #expect(out.isPass, "xoá lùi từ \"\(screen)\" (gõ \(word)) phải đi thẳng")
                screen.removeLast()
                #expect(e.currentWord == screen)
            }
        }
    }

    /// Xoá chữ mang dấu thanh thì dấu mất theo; xoá chữ khác thì dấu ở yên.
    @Test(arguments: [
        ("tieengs<<<", "ti"), ("vieetj<<", "vi"), ("dduwowcj<", "đượ"), ("hoanf<<", "ho"), ("quas<", "qu"),
        ("tieengs<<<eens", "tiến"),  // xoá rồi gõ tiếp vẫn bỏ dấu được
        ("tieengs vieetj<<<<<<<<s", "tí"),  // xoá ngược qua hai từ
        ("hoanf<n ", "hoàn "), ("hoanf< ", "hòa "),  // dấu về đúng chỗ khi kết thúc từ
    ])
    func toneGoesWithItsLetter(keys: String, want: String) { #expect(run(keys) == want) }
}

@Suite struct Glyphs {
    /// Bảng tra chữ hiển thị phải cho đúng kết quả của cách chuẩn hoá Unicode, với mọi chữ, dấu, thanh, hoa/thường.
    @Test func tableMatchesNormalization() {
        let marks: [Mark] = [.none, .hat, .breve, .horn, .bar]
        for base in "abcdefghijklmnopqrstuvwxyz" {
            for mark in marks {
                for upper in [false, true] {
                    for t in 0...5 {
                        let tone = Tone(rawValue: t)!
                        let l = Letter(base: base, mark: mark, upper: upper)
                        #expect(l.glyph(tone) == Letter.compose(l.plain, tone, upper: upper), "\(base) \(mark) \(tone) \(upper)")
                    }
                }
            }
        }
        #expect(Letter(base: "e", mark: .hat, upper: true).glyph(.sac) == "Ế")
        #expect(Letter(base: "d", mark: .bar, upper: true).glyph(.none) == "Đ")
    }

    /// Giữ phím cách rất lâu sau một từ: engine thôi theo dõi từ đó chứ không tích luỹ mãi.
    @Test func longSeparatorRunIsBounded() {
        let e = Engine(config: Config())
        for ch in "tooi" { _ = e.type(ch) }
        for _ in 0..<500 { _ = e.type(" ") }
        #expect(e.toggleLast().isPass)
        #expect(run("tooi" + String(repeating: " ", count: 100) + "ddi ") == "tôi" + String(repeating: " ", count: 100) + "đi ")
    }
}

/// Xoá ngay từ VNKey vừa xử lý rồi gõ lại y nguyên: người dùng muốn dạng còn lại; đổi luôn và nhớ.
@Suite struct LearnFromRetype {
    @Test func vietnameseWordRetypedBecomesRaw() {
        let e = Engine(config: Config())
        #expect(run("this ", lexicon: FakeLexicon.shared, engine: e) == "thí ")
        #expect(run("this <<<<this ", lexicon: FakeLexicon.shared) == "this ")
        let e2 = Engine(config: Config())
        _ = run("this <<<<this ", lexicon: FakeLexicon.shared, engine: e2)
        #expect(e2.preferRaw.contains("this"))
        #expect(run("this ", lexicon: FakeLexicon.shared, engine: e2) == "this ")
    }

    @Test func restoredWordRetypedBecomesVietnamese() {
        let e = Engine(config: Config())
        #expect(run("test <<<<<test ", lexicon: FakeLexicon.shared, engine: e) == "tét ")
        #expect(e.preferVN.contains("test"))
    }

    @Test func worksAcrossPunctuation() {
        #expect(run("this, <<<<<this, ", lexicon: FakeLexicon.shared) == "this, ")
    }

    @Test func doesNotTriggerWithoutExactRetype() {
        let lex = FakeLexicon.shared
        // Gõ lại khác chữ hoa/thường, hoặc khác phím: không học.
        #expect(run("tooi <<<<Tooi ", lexicon: lex) == "Tôi ")
        // Chỉ xoá một phần rồi gõ lại: đang sửa từ, không học.
        #expect(run("this <<is ", lexicon: lex) == "thí ")
        // Xoá lan sang từ trước rồi mới gõ lại: không học.
        #expect(run("la this <<<<<<a this ", lexicon: lex) == "la thí ")
        // Từ không phải từ vừa gõ gần nhất (đã gõ từ khác sau nó).
        let e = Engine(config: Config())
        #expect(run("this laf <<<<<<<<this ", lexicon: lex, engine: e) == "thí ")
        #expect(e.preferRaw.isEmpty)
        // Từ không có dạng nào khác (gõ ra đúng phím gốc).
        #expect(run("ban <<<<ban ", lexicon: lex) == "ban ")
    }

    @Test func canBeTurnedOff() {
        var c = Config(); c.learnFromRetype = false
        #expect(run("this <<<<this ", c, lexicon: FakeLexicon.shared) == "thí ")
    }
}

/// Hai tuỳ chọn của Telex: phím [ ] thành ơ ư (`bracketKeys`) và phím w đứng riêng thành ư (`standaloneW`).
@Suite struct TelexOptions {
    func cfg(brackets: Bool = false, w: Bool = true, _ m: Method = .telex) -> Config {
        var c = Config(); c.method = m; c.bracketKeys = brackets; c.standaloneW = w; return c
    }

    @Test(arguments: [
        ("[", "ơ"), ("]", "ư"), ("{", "Ơ"), ("}", "Ư"),
        ("m[i", "mơi"), ("m[is", "mới"), ("t]", "tư"), ("ch]a", "chưa"), ("ch]as", "chứa"),
        ("th]", "thư"), ("b[r", "bở"), ("n]]c", "n]c"),
        ("[[", "["), ("]]", "]"), ("{{", "{"),
        ("d]]cj", "d]cj"),
        ("d][cj", "dược"), ("dd][cj", "được"), ("ng][if", "người"),
    ])
    func bracketsOn(keys: String, want: String) { #expect(run(keys, cfg(brackets: true)) == want) }

    @Test func bracketsStayPunctuationWhereTheyCannotBeLetters() {
        let c = cfg(brackets: true)
        #expect(run("tab[0] ", c) == "tab[0] ")  // sau phụ âm cuối không thể có ơ
        #expect(run("x = a.b[", c) == "x = a.b[")  // ngữ cảnh code: sau dấu chấm
        #expect(run("[link] ", c) == "[link] ")  // không thành âm tiết -> trả lại phím gốc
        #expect(run("tooi [", c).hasSuffix(" ơ"))
        #expect(run("m[<", c) == "m")  // xoá lùi xoá đúng chữ ơ
    }

    @Test func bracketsOffByDefault() {
        #expect(Config().bracketKeys == false)
        #expect(run("[", Config()) == "[")
        #expect(run("m[i] ", Config()) == "m[i] ")
        #expect(run("m[i] ", cfg(brackets: true, .vni)) == "m[i] ")  // VNI không dùng phím ngoặc
    }

    @Test func standaloneWCanBeTurnedOff() {
        #expect(run("w", cfg()) == "ư")
        #expect(run("nhw", cfg()) == "như")
        #expect(run("w", cfg(w: false)) == "w")
        #expect(run("nhw", cfg(w: false)) == "nhw")
        #expect(run("tw ", cfg(w: false)) == "tw ")
        // Tắt w đứng riêng không ảnh hưởng dấu móc/trăng sau nguyên âm.
        #expect(run("muaw dduwowcj ", cfg(w: false)) == "mưa được ")
    }
}

/// Lỗi người dùng báo (2026-11-25): đang ở chế độ tiếng Việt mà "cos" ra "cos" thay vì "có". Nhật ký: mạch tiếng
/// Anh đang là 2 (`en×2`), nên từ hợp lệ ở cả hai ngôn ngữ bị coi là tiếng Anh; chính lần trả lại đó lại nối dài
/// mạch (`en×3`…`en×6`), gõ lại bao nhiêu lần vẫn ra "cos". Từ tiếng Việt thông dụng phải thắng mạch tiếng Anh.
@Suite struct VietnameseWinsInVietnameseMode {
    final class Lex: Lexicon {
        let en: Set<String> = ["user", "data", "cos", "this", "error"]
        func isEnglish(_ w: String) -> Bool { en.contains(w) }
        func isVietnamese(_ w: String) -> Bool { Charset.syllableKey(w) != nil }
    }
    let lex = Lex()

    @Test func commonVietnameseWordBeatsAnEnglishRun() {
        #expect(run("user data cos ", lexicon: lex) == "user data có ")
        #expect(run("user data error cos cos cos ", lexicon: lex) == "user data error có có có ")
    }

    /// Từ tiếng Việt hiếm ("thí") giữa một mạch tiếng Anh vẫn được coi là tiếng Anh như trước.
    @Test func rareVietnameseReadingStillFollowsTheRun() {
        #expect(run("this ", lexicon: lex) == "thí ")
        #expect(run("user data this ", lexicon: lex) == "user data this ")
    }

    @Test func switchStillTurnsTheRunRuleOff() {
        var c = Config()
        c.contextAware = false
        #expect(run("user data this ", c, lexicon: lex) == "user data thí ")
    }
}

/// Lỗi người dùng báo (2026-11-25): gõ "Đạt" ra "Đajt". Nhật ký: họ gõ "Dd", lỡ gõ "j" (phím dấu khi chưa có nguyên
/// âm: từ thành nguyên văn "Đj"), xoá "j", rồi gõ "ajt". Sau lần xoá, phần còn lại của từ nguyên văn là chữ "Đ" chứ
/// không còn là chuỗi phím, nên engine không hiểu lại được và giữ nguyên văn tới hết từ.
@Suite struct RetryAfterAStrayToneKey {
    @Test(arguments: [
        ("Ddj<ajt ", "Đạt "), ("ddj<ajt ", "đạt "), ("ddj<i ", "đi "), ("DDJ<AJT ", "ĐẠT "), ("ddf<<dduowcj ", "được "),
        ("ddj<<<", ""), ("ddj<j", "đj"),
    ])
    func telex(keys: String, want: String) { #expect(run(keys) == want) }

    @Test func vni() {
        var c = Config()
        c.method = .vni
        #expect(run("D95<a5t ", c) == "Đạt ")
    }
}

/// Người dùng hỏi (2026-11-25): gõ "ddaayy" (thừa chữ y) thì VNKey trả lại phím gốc "ddaayy"; xoá chữ y thừa đi, từ
/// có quay lại "đây" không. Engine không được sửa chữ lúc xoá lùi (`BackspaceIsPlain`), nhưng lúc NGẮT TỪ thì được:
/// phần còn lại được hiểu lại như vừa gõ mới, giống khi gõ tiếp một chữ ("ddaayy<s" -> "đấy").
@Suite struct RetryAtWordBreak {
    let lex = FakeLexicon.shared

    @Test(arguments: [
        ("ddaayy< ", "đây "), ("ddaayy<, ", "đây, "), ("ddaayy <<  ", "đây  "), ("vieejtt< ", "việt "), ("DDAAYY< ", "ĐÂY "),
        ("testt< ", "test "),  // từ tiếng Anh vẫn là tiếng Anh
        ("ass< ", "a "),  // gõ lặp để huỷ dấu được tôn trọng: không hiểu lại thành "á"
    ])
    func strayKeyDeletedThenBreak(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }

    /// Xoá lùi vẫn không đụng tới màn hình: chữ chỉ đổi khi ngắt từ.
    @Test func backspaceItselfStillChangesNothing() { #expect(run("ddaayy<", lexicon: lex) == "ddaay") }
}

/// Lỗi người dùng báo (2026-11-25): gõ "userr" ra "uer", mất chữ s. Chữ s đã thành dấu sắc, chữ r đầu đổi nó thành
/// dấu hỏi, chữ r thứ hai huỷ dấu và mọi phím dấu biến mất. Gõ lặp chỉ là "huỷ dấu" khi từ mới có MỘT phím dấu
/// ("ass" -> "as"); đã có phím dấu khác bị đè lên trước đó thì đây không còn là âm tiết đang gõ dở: trả lại đủ các phím.
@Suite struct RepeatedToneKeyAfterAnotherTone {
    let lex = FakeLexicon.shared

    @Test(arguments: [
        ("userr", "userr"), ("userr ", "userr "), ("USERR ", "USERR "), ("asrr", "asrr"), ("afss ", "afss "),
        ("userr< ", "user "),  // xoá phím thừa rồi ngắt từ: hiểu lại, "user" là tiếng Anh
        ("asrr< ", "ả "),  // còn "asr": á rồi đổi thành ả
        ("ass", "as"), ("tass ", "tas "), ("arr ", "ar "),  // huỷ dấu thường vẫn như cũ
    ])
    func keepsEveryKey(keys: String, want: String) { #expect(run(keys, lexicon: lex) == want) }

    @Test func vni() {
        var c = Config()
        c.method = .vni
        #expect(run("a122 ", c) == "a122 ")
        #expect(run("a11 ", c) == "a1 ")
    }
}

/// THỬ NGHIỆM `Config.retryOnBackspace` (người dùng yêu cầu chạy thử 2026-11-25, mặc định tắt): chữ đổi NGAY khi xoá
/// phím gõ thừa. Bật cờ cho cả bộ test thì chỉ có hai chỗ va chạm, ghi ở hai test cuối.
@Suite struct RetryOnBackspace {
    let lex = FakeLexicon.shared

    func type(_ keys: String) -> String {
        var c = Config()
        c.retryOnBackspace = true
        return run(keys, c, lexicon: lex)
    }

    @Test(arguments: [
        ("ddaayy<", "đây"), ("ddaayy<<", "đâ"), ("ddaayy< ", "đây "), ("vieejtt<", "việt"), ("DDAAYY<", "ĐÂY"),
        ("ddaayy<s ", "đấy "), ("tooi ddaayy<", "tôi đây"),
        ("testt<", "test"), ("testt< ", "test "),  // phần còn lại là từ tiếng Anh: không đổi
        ("ass<", "a"), ("slide<<<", "sl"),  // huỷ dấu chủ động, phần còn lại chưa thành từ: không đổi
    ])
    func changesAsSoonAsTheStrayKeyIsDeleted(keys: String, want: String) { #expect(type(keys) == want) }

    /// Va chạm 1 (đã chặn): từ đã gõ xong rồi mở lại bằng phím xoá không được hiểu lại, nếu không xoá dần một từ
    /// tiếng Anh sẽ ra tiếng Việt giữa chừng ("test" -> "tes" -> "té") và việc học khi gõ lại bị hỏng.
    @Test func reopenedWordsAreLeftAlone() {
        #expect(type("test <<") == "tes")
        #expect(type("test <<<<<test ") == "tét ")  // vẫn học được như `restoredWordRetypedBecomesVietnamese`
    }

    /// Va chạm 2 (theo thiết kế): đang giữ phím xoá thì không đổi chữ.
    @Test func heldBackspaceNeverChangesText() {
        var c = Config()
        c.retryOnBackspace = true
        let e = Engine(config: c)
        for ch in "ddaayy" { _ = e.type(ch) }
        #expect(e.backspace(held: true).isPass)
        #expect(e.currentWord == "ddaay")
    }
}
