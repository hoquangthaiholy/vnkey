import Testing

@testable import VNEngine

/// Từ điển có vài từ tiếng Anh và gợi ý sửa, để thử phần soát tiếng Anh.
final class EnglishLexicon: Lexicon {
    let words: Set<String>
    let guesses: [String: [String]]
    init(words: Set<String>, guesses: [String: [String]] = [:]) { self.words = words; self.guesses = guesses }
    func isEnglish(_ w: String) -> Bool { words.contains(w) }
    func isVietnamese(_ w: String) -> Bool { Charset.syllableKey(w) != nil }
    func englishGuesses(_ word: String) -> [String] { guesses[word] ?? [] }
}

/// Bộ soát lỗi (`Proofreader`): thay cho tự sửa (người dùng chốt 2026-11-25). Nó chỉ CHỈ RA chỗ nghi sai và chữ đề
/// nghị; không gì trên màn hình bị đổi.
@Suite struct Proofreading {
    func reader(_ model: ContextModel? = nil, lexicon: Lexicon = LenientLexicon()) -> Proofreader {
        let p = Proofreader()
        p.lexicon = lexicon
        p.context = model
        return p
    }

    /// "chữ đang hiện>đề nghị đầu tiên" của từng chỗ.
    func found(_ text: String, _ p: Proofreader? = nil, caret: Int? = nil) -> [String] {
        (p ?? reader()).check(text, caret: caret).map { "\($0.text)>\($0.suggestions.first ?? "")" }
    }

    @Test(arguments: [
        ("tiếng viêt nam", "viêt>việt"), ("bài viêt này", "viêt>viết"), ("tôi đươc đi", "đươc>được"),
        ("nhiệt dới", "dới>đới"), ("Bài Viêt này", "Viêt>Viết"),
    ])
    func missingMarks(text: String, want: String) {
        let issues = reader().check(text)
        #expect(issues.map { "\($0.text)>\($0.suggestions.first ?? "")" } == [want])
        #expect(issues.first?.kind == .missingMark)
    }

    /// Chữ không phải tiếng Việt cũng không phải tiếng Anh vì LẶP hoặc ĐẢO chữ cái (đo 2026-11-26 bằng
    /// `vnkey-tool check-eval`: 25 chữ kiểu này bị bỏ sót vì không cách thêm dấu nào ra từ).
    @Test(arguments: [
        ("tôi khôgn biết", "khôgn>không"), ("đợi mộtt chút", "mộtt>một"), ("tôi đãã về", "đãã>đã"),
        ("đến lcú đó", "lcú>lúc"), ("để tôi xemm", "xemm>xem"), ("tôi rất vuii", "vuii>vui"),
        ("anh giúpp tôi", "giúpp>giúp"), ("đi ngayy đi", "ngayy>ngay"), ("tôi muaa sách", "muaa>mua"),
        ("tôi nghee nhạc", "nghee>nghe"), ("Khôgn sao đâu", "Khôgn>Không"),
    ])
    func repeatedAndSwappedLetters(text: String, want: String) {
        #expect(found(text) == [want])
    }

    @Test func repeatedLetterKinds() {
        #expect(reader().check("đợi mộtt chút").first?.kind == .doubledKey)
        #expect(reader().check("tôi khôgn biết").first?.kind == .swappedKeys)
    }

    /// Tên riêng viết hoa không bị đoán là viết sai của một từ thường (đo 2026-11-26: "Huế" bị đề nghị "Huệ",
    /// "Nguyễn" thành "Nguyện"). Thiếu dấu rõ ràng ("Viêt") vẫn gạch.
    @Test(arguments: [
        "Nguyễn Du là tác giả của Truyện Kiều.", "Cho tôi một tô bún bò Huế.", "Trịnh Công Sơn là nhạc sĩ tôi yêu thích.",
        "Sông Hương chảy qua thành phố Huế.", "Buôn Ma Thuột nổi tiếng về cà phê.", "Bé Bống năm nay lên ba tuổi.",
        "Chị Thuỷ quê ở Quảng Ngãi.",
    ])
    func properNamesAreLeftAlone(text: String) {
        #expect(found(text) == [])
    }

    @Test func capitalisedWordStillFlaggedForMissingMark() {
        #expect(found("tôi ở Viêt Nam") == ["Viêt>Việt"])
    }

    /// Từ rất thông dụng đứng cạnh một từ mà cặp đó không có trong bảng: không vì thế mà đoán nó viết sai.
    @Test(arguments: [
        "Có ai muốn một miếng bánh khác không?", "Bạn tới sớm quá.", "Ông ta luôn đặt lợi ích của bản thân lên trên hết.",
        "Sóng vỗ rì rào vào bờ cát.",
    ])
    // Chưa chắn được: "mài sắt" vẫn bị đề nghị "sắc" ("mài sắc" là từ ghép, "sắt" không đủ thông dụng).
    func commonWordsAreNotSecondGuessed(text: String) {
        #expect(found(text) == [])
    }

    /// Người dùng yêu cầu (2026-11-25): phân biệt chữ GÕ NHẦM ("duojc", "viêt": thiếu hoặc trật phím) với chữ SAI
    /// CHÍNH TẢ ("dới" viết cho "với": lẫn d / v / gi). Chữ là âm tiết đúng cấu tạo nhưng không có trong bảng thì thử
    /// thêm các cặp âm hay lẫn; đề nghị đứng đầu thuộc loại nào thì chỗ đó mang loại ấy (app tô đỏ / cam).
    @Test func misspellingIsToldApartFromMistyping() {
        let joke = reader().check("em có muốn làm việc dới thầy không")
        #expect(joke.count == 1)
        #expect(joke.first?.text == "dới")
        #expect(joke.first?.kind == .spelling)
        #expect(joke.first?.suggestions.first == "với")
        // Từ đứng trước ủng hộ cách thêm dấu: đó là gõ thiếu phím, không phải sai chính tả.
        let typo = reader().check("vùng nhiệt dới")
        #expect(typo.first?.kind == .missingMark)
        #expect(typo.first?.suggestions.first == "đới")
    }

    /// Các nhóm lỗi chính tả thường gặp (`Proofreader.initialMixups` …): âm đầu, vần, âm cuối, thanh.
    @Test(arguments: [
        ("trời xắp mưa", "xắp>sắp"), ("chời ơi đẹp quá", "chời>trời"), ("anh lói gì thế", "lói>nói"),  // s/x, ch/tr, l/n
        ("bác xĩ khám bệnh", "xĩ>sĩ"), ("em làm việc dới thầy", "dới>với"),  // s/x, d/v
        ("tôi uống riệu", "riệu>rượu"), ("tìm kím", "kím>kiếm"), ("mầu xanh", "mầu>màu"),  // iêu/ươu, i/iê, âu/au
        ("con muổi", "muổi>muỗi"),  // hỏi/ngã
    ])
    func commonMisspellings(text: String, want: String) {
        let issues = reader().check(text)
        #expect(issues.map { "\($0.text)>\($0.suggestions.first ?? "")" } == [want])
        #expect(issues.first?.kind == .spelling)
    }

    /// Người dùng hỏi (2026-11-25): vì sao "Đi vễ nhà" không đề nghị "về". Gõ nhầm phím dấu thanh (ngã thay cho huyền)
    /// không thuộc cặp thanh hay lẫn khi viết nào, nên phải thử mọi thanh khác; từ bên cạnh chọn ra thanh đúng.
    @Test(arguments: [("Đi vễ nhà", "vễ>về"), ("tôi đị học", "đị>đi"), ("ăn cờm", "cờm>cơm"), ("cảm ờn bạn", "ờn>ơn")])
    func wrongToneKey(text: String, want: String) {
        let issues = reader().check(text)
        #expect(issues.map { "\($0.text)>\($0.suggestions.first ?? "")" } == [want])
        #expect(issues.first?.kind == .wrongTone)
        #expect(issues.first?.isMisspelling == false)
    }

    /// Từ điển từ ghép (`Compounds`) bắt được lỗi chính tả trùng một âm tiết có thật: chữ đó không tạo thành từ với
    /// từ bên cạnh và cặp đó không hề gặp trong kho ngữ liệu, còn đổi một âm hay lẫn thì ra một từ ghép.
    @Test(arguments: [("bánh trưng ngon", "trưng>chưng"), ("dữ gìn sức khoẻ", "dữ>giữ")])
    func realSyllableInTheWrongCompound(text: String, want: String) {
        let issues = reader().check(text)
        #expect(issues.map { "\($0.text)>\($0.suggestions.first ?? "")" } == [want])
        #expect(issues.first?.kind == .spelling)
    }

    /// Không gạch khi cụm đang viết là từ thật hoặc vẫn hay gặp, và không đụng tới i / y (lí / lý đều được chấp nhận).
    @Test(arguments: ["anh ăn chưa", "tôi sẽ đi", "cái bàn này", "con trâu", "xử lí", "kỹ thuật", "bánh chưng", "giữ gìn", "chia sẻ"])
    func realCompoundsAndCommonPairsAreLeftAlone(text: String) { #expect(found(text) == []) }

    /// Người dùng hỏi (2026-11-25): vì sao "ngoài rưng" không được đề nghị. "rưng" có trong từ điển ("rưng rưng") nên
    /// là từ hiếm có thật, và "rừng" (2.743 lần) chưa tới ngưỡng "rất thông dụng". Từ bên cạnh phải được tính: đề nghị
    /// hay đi với từ bên cạnh thì từ hiếm vẫn bị gạch.
    @Test(arguments: [("đi ra ngoài rưng", "rưng>rừng"), ("một khu rưng rậm", "rưng>rừng")])
    func rareWordNextToAWordThatWantsSomethingElse(text: String, want: String) {
        #expect(found(text) == [want])
    }

    /// Người dùng chọn (2026-11-25, sau khi đo 2.894 từ đơn hiếm của từ điển): từ hiếm có thật chỉ bị gạch khi đề
    /// nghị đứng đầu là THÊM DẤU ra một từ gặp từ 1.000 lần. Đề nghị kiểu lẫn âm hay đổi thanh cho một từ có thật chỉ
    /// là phỏng đoán ("tậu" không phải "tạo" viết sai): ở ngưỡng 1.000 chúng gạch nhầm hơn 1.000 từ thật.
    @Test(arguments: ["anh ấy tậu xe", "ăn cốm", "hơi nhớt", "phả hơi nóng"])
    func rareRealWordsAreNotSecondGuessed(text: String) { #expect(found(text) == []) }

    @Test func rareWordsThatOnlyLackAMarkAreStillFlagged() {
        #expect(found("dúng") == ["dúng>đúng"])
        #expect(found("ròi") == ["ròi>rồi"])
        #expect(found("rưng") == ["rưng>rừng"])
        // Có từ bên cạnh thì nó quyết định thứ tự, và mọi loại đề nghị đều được tính.
        #expect(reader().check("tôi dúng").first?.suggestions.contains("đúng") == true)
    }

    @Test func rareWordInItsOwnCompoundIsLeftAlone() { #expect(found("mắt rưng rưng nhìn theo") == []) }

    /// Âm tiết hiếm nhưng có trong từ điển (đứng một mình, hoặc trong từ ghép với từ bên cạnh) không bị gạch.
    @Test(arguments: ["con cá quẫy đuôi", "bánh chưng xanh"])
    func rareButRealWordsAreNotFlagged(text: String) { #expect(found(text) == []) }

    /// Chữ không phải âm tiết đúng cấu tạo, hoặc chuỗi phím còn nguyên, luôn là gõ nhầm.
    @Test(arguments: ["tiếng viêt", "tôi đươc", "tôi duojc đi", "nói tiêng anh"])
    func brokenSyllablesAreMistyping(text: String) {
        #expect(reader().check(text).first?.kind == .missingMark)
    }

    @Test(arguments: [("tôi veeg nhà", "veeg>về"), ("đó lag gì", "lag>là"), ("Đó Lag gì", "Lag>Là")])
    func slippedToneKey(text: String, want: String) {
        let issues = reader().check(text)
        #expect(issues.map { "\($0.text)>\($0.suggestions.first ?? "")" } == [want])
        #expect(issues.first?.kind == .slippedKey)
    }

    @Test func swappedKeys() {
        let issues = reader().check("nói tieegns Việt")
        #expect(issues.map { "\($0.text)>\($0.suggestions.first ?? "")" } == ["tieegns>tiếng"])
        #expect(issues.first?.kind == .swappedKeys)
    }

    @Test func learnedTypoNeedsTheUsersOwnFixes() {
        #expect(found("tôi goc phím") == ["goc>góc"])  // chưa học gì: chỉ là đề nghị thêm dấu
        let model = UsageModel()
        model.recordTypo("goc", fixed: "gox")
        model.recordTypo("goc", fixed: "gox")
        let issues = reader(model).check("tôi goc phím, Goc nữa")
        #expect(issues.map { "\($0.text)>\($0.suggestions.first ?? "")" } == ["goc>gõ", "Goc>Gõ"])
        #expect(issues.first?.kind == .learnedTypo)
    }

    /// Cụm không dấu mà người dùng hay gõ có dấu: đề nghị cho cả cụm.
    @Test func habitualPhrase() {
        let model = UsageModel()
        for _ in 0..<3 {
            model.record("lầm", after: nil)
            model.record("lỗi", after: "lầm")
        }
        #expect(found("lam loi", reader(model)) == ["lam loi>lầm lỗi"])
        #expect(found("Lam loi roi", reader(model)) == ["Lam loi>Lầm lỗi"])
        #expect(reader(model).check("lam loi").first?.kind == .phrase)
        #expect(found("lam loi") == [])
    }

    /// Hai từ liền nhau cùng sai: một chỗ gạch, đề nghị cả cụm.
    @Test func neighbouringIssuesMerge() {
        let issues = reader().check("học tiêng viêt nhé")
        #expect(issues.map { "\($0.text)>\($0.suggestions.first ?? "")" } == ["tiêng viêt>tiếng việt"])
        #expect(issues.first?.kind == .phrase)
    }

    @Test(arguments: [
        "tôi đang gõ tiếng Việt ở Hà Nội", "hôm nay trời đẹp quá", "toi dang go khong dau", "ok nhé", "",
        "TIÊNG VIÊT", "a b c",
    ])
    func cleanTextHasNoIssues(text: String) { #expect(found(text) == []) }

    @Test(arguments: ["biến viêt_nam và đươc_phép", "xem https://viêt.vn/đươc", "gửi a@đươc.com", "tệp đươc.txt", "viêt2 #đươc"])
    func codeAndAddressesAreSkipped(text: String) { #expect(found(text) == []) }

    /// Từ đang gõ dở (con trỏ nằm trong hoặc ngay sau nó) chưa soát.
    @Test func wordAtTheCaretIsSkipped() {
        #expect(found("tiếng viêt", caret: 10) == [])
        #expect(found("tiếng viêt", caret: 8) == [])
        #expect(found("tiếng viêt", caret: 0) == ["viêt>việt"])
        #expect(found("tiếng viêt nam", caret: 14) == ["viêt>việt"])
    }

    @Test func rangesAreUTF16() {
        let text = "😀 tiếng viêt."
        let issue = reader().check(text).first
        #expect(issue?.range == 9..<13)
        // Chữ tổ hợp (ê = e + dấu mũ rời): vẫn nhận ra, và vị trí tính theo văn bản gốc.
        let loose = "tiếng vie\u{302}t"
        let second = reader().check(loose).first
        #expect(second?.range == 6..<11)
        #expect(second?.suggestions.first == "việt")
    }

    /// Người dùng hỏi (2026-11-25): trong "Tiếng viet giàu và đẹp." vì sao "viet" không được đề nghị. Âm tiết kết thúc
    /// bằng c/ch/p/t bắt buộc có dấu sắc hoặc nặng, nên từ như vậy mà không dấu, đứng cạnh một từ có dấu (người viết
    /// đang gõ có dấu), chắc chắn là gõ thiếu.
    @Test(arguments: [
        ("Tiếng viet giàu và đẹp.", "viet>việt"), ("tôi duoc nghỉ", "duoc>được"), ("bài viet này", "viet>viết"),
        ("Tiếng Viet giàu", "Viet>Việt"),
    ])
    func unmarkedStopFinalNextToMarkedWord(text: String, want: String) {
        let issues = reader().check(text)
        #expect(issues.map { "\($0.text)>\($0.suggestions.first ?? "")" } == [want])
        #expect(issues.first?.kind == .missingMark)
    }

    /// Không có từ có dấu nào bên cạnh (người viết không dấu), từ tiếng Anh, hay âm tiết không cần dấu: không gạch.
    @Test func unmarkedWordsElsewhereAreLeftAlone() {
        #expect(found("toi viet thu cho ban") == [])
        #expect(found("viet") == [])
        #expect(found("tôi lam việc") == [])  // "lam" không kết thúc bằng c/ch/p/t: có thể là từ không dấu thật
        let lex = EnglishLexicon(words: ["chat", "at"])
        #expect(found("tôi chat với bạn at đây", reader(lexicon: lex)) == [])
    }

    @Test func skippedWordsAreNotFlagged() {
        let p = reader()
        p.skip = ["dới"]
        #expect(found("làm việc dới thầy, Dới nữa", p) == [])
    }

    @Test func englishIsCheckedOnlyWhenAsked() {
        let lex = EnglishLexicon(words: ["the", "receive", "mail", "don't"], guesses: ["recieve": ["receive", "relieve"], "dont": ["don't"]])
        let p = reader(lexicon: lex)
        #expect(found("recieve the mail", p) == [])
        p.checkEnglish = true
        let issues = p.check("recieve the mail")
        #expect(issues.map { "\($0.text)>\($0.suggestions.first ?? "")" } == ["recieve>receive"])
        #expect(issues.first?.kind == .english)
        #expect(found("the mail don't", p) == [])
        // Ngay cạnh một từ tiếng Việt có dấu: nhiều khả năng là chữ teen hay tên riêng, không soát tiếng Anh.
        #expect(found("tôi recieve", p) == [])
        #expect(found("Recieve the mail", p) == [])
    }
}
