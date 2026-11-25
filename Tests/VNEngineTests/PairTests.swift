import Testing

@testable import VNEngine

/// Bảng cặp âm tiết dựng sẵn (`CommonPairs`): dữ liệu đọc được và đúng với những cặp ai cũng biết.
@Suite struct PairTable {
    @Test func matchesTheSyllableTable() {
        #expect(CommonPairs.syllableCount == CommonWords.entryCount)
        #expect(CommonWords.keys.count == CommonWords.entryCount)
        #expect(CommonPairs.pairCount > 50_000)
    }

    @Test(arguments: [
        ("hôm", "nay", "này"), ("tiếng", "việt", "viết"), ("bài", "viết", "việt"), ("không", "được", "dược"),
        ("nhiệt", "đới", "với"), ("việc", "với", "đới"), ("người", "bạn", "bàn"), ("cái", "bàn", "bạn"),
    ])
    func knowsWhichWordFollows(prev: String, likely: String, unlikely: String) {
        #expect(CommonPairs.count(likely, after: prev) >= CommonPairs.floor)
        #expect(CommonPairs.count(likely, after: prev) > 2 * CommonPairs.count(unlikely, after: prev))
    }

    @Test func ignoresCaseAndTonePlacement() {
        #expect(CommonPairs.count("Nay", after: "HÔM") == CommonPairs.count("nay", after: "hôm"))
        #expect(CommonPairs.count("hoà", after: "giải") == CommonPairs.count("hòa", after: "giải"))
    }

    @Test func unknownPairsCountZero() {
        #expect(CommonPairs.count("đới", after: "việc") == 0)
        #expect(CommonPairs.count("nay", after: "xyz") == 0)
        #expect(CommonPairs.count("", after: "") == 0)
    }

    /// Số đếm nén thành một byte: sai lệch nhỏ, và không bao giờ đảo thứ tự hai số cách xa nhau.
    @Test(arguments: [20, 21, 100, 1475, 13629, 162_465])
    func quantizationIsClose(n: Int) {
        let back = CommonPairs.expand(CommonPairs.quantize(n))
        #expect(abs(back - n) * 100 <= 4 * n)
    }
}

/// Gõ một chuỗi phím qua engine rồi soát chữ trên màn hình: trả về màn hình và "chữ>đề nghị đầu tiên" của từng chỗ.
func typedThenChecked(
    _ keys: String, lexicon: Lexicon = LenientLexicon(), model: ContextModel? = nil, _ change: (inout Config) -> Void = { _ in }
) -> (screen: String, found: [String]) {
    var c = Config()
    change(&c)
    let e = Engine(config: c)
    e.context = model
    let screen = run(keys, lexicon: lexicon, engine: e)
    let p = Proofreader()
    p.config = c
    p.lexicon = lexicon
    p.context = model
    return (screen, p.check(screen).map { "\($0.text)>\($0.suggestions.first ?? "")" })
}

/// Từ 2026-11-25 VNKey không tự sửa nữa: engine để nguyên chữ đã gõ, bộ soát lỗi đề nghị. Các ca dưới đây là những
/// ca bản tự sửa từng thay chữ (đoán dấu theo từ đứng trước, phím dấu gõ trượt).
@Suite struct TypedTextIsFlaggedNotChanged {
    /// Lỗi người dùng báo (2026-11-25): "dới" (viết đùa của "với") bị đổi thành "đới". Giờ không gì bị đổi.
    @Test func jokeSpellingStaysAsTyped() {
        let r = typedThenChecked("em cos muoons lamf vieejc dowis thaafy khoong ")
        #expect(r.screen == "em có muốn làm việc dới thầy không ")
        #expect(r.found == ["dới>với"])  // sai chính tả (d / v), không phải thiếu dấu
    }

    @Test(arguments: [
        ("nhieejt dowis ", "nhiệt dới ", "dới>đới"),
        // Hai ứng viên cùng hạng: từ đứng trước quyết định thứ tự đề nghị.
        ("tieesng vieet ", "tiếng viêt ", "viêt>việt"), ("baif vieet ", "bài viêt ", "viêt>viết"),
        ("duojc ", "duojc ", "duojc>được"), ("tieeng ", "tiêng ", "tiêng>tiếng"), ("vieejc roif ", "việc ròi ", "ròi>rồi"),
        ("tieegns ", "tieegns ", "tieegns>tiếng"), ("nugowfi ", "nugowfi ", "nugowfi>người"),
    ])
    func missingMarks(keys: String, screen: String, found: String) {
        let r = typedThenChecked(keys)
        #expect(r.screen == screen)
        #expect(r.found == [found])
    }

    /// Phím dấu thanh gõ trượt sang phím kề bên ("lag" thay cho "laf" = là: g sát f; d sát s).
    @Test(arguments: [
        ("ddos lag ", "đó lag ", "lag>là"), ("tooi veeg ", "tôi veeg ", "veeg>về"), ("nhuwng mag ", "nhưng mag ", "mag>mà"),
        ("tooi cod ", "tôi cod ", "cod>có"), ("Ddos Lag ", "Đó Lag ", "Lag>Là"),
    ])
    func slippedToneKey(keys: String, screen: String, found: String) {
        let r = typedThenChecked(keys)
        #expect(r.screen == screen)
        #expect(r.found == [found])
    }

    @Test func swappedKeysWithVNI() {
        let r = typedThenChecked("tie61gn ") { $0.method = .vni }
        #expect(r.screen == "tie61gn ")
        #expect(r.found == ["tie61gn>tiếng"])
        #expect(typedThenChecked("mp3s 2024a ") { $0.method = .vni }.found == [])
    }

    @Test func slippedToneKeyWithVNI() {
        let r = typedThenChecked("to6i gor ") { $0.method = .vni }  // r nằm dưới phím 4
        #expect(r.screen == "tôi gor ")
        #expect(r.found == ["gor>gõ"])
    }

    /// Chữ không dấu kết thúc bằng c/ch/p/t đứng cạnh từ có dấu: không coi là trật phím ("goc" có thể là "góc" chứ
    /// chưa chắc là "gõ"), mà là thiếu dấu, vì âm tiết như vậy bắt buộc có thanh sắc hoặc nặng.
    @Test(arguments: [("tooi goc ", "goc>góc"), ("owr nhat ", "nhat>nhật"), ("nguwowif mat ", "mat>mất"), ("ddi tet ", "tet>tết")])
    func unmarkedStopFinalsGetMarkSuggestions(keys: String, found: String) {
        #expect(typedThenChecked(keys).found == [found])
    }

    /// Không gạch chân khi không đủ bằng chứng: từ thật, chữ teen, viết tắt, hoặc không có từ bên cạnh ủng hộ.
    @Test(arguments: [
        "tooi ban ", "tooi lo ", "ddos las ", "lag ", "cuar lag ",
        "tooi bik ", "vaajy ak ", "tooi ko ", "tooi ae ", "tooi hehe ", "vieejc rooif ",
    ])
    func leftAloneWithoutClearEvidence(keys: String) { #expect(typedThenChecked(keys).found == []) }

    /// Từ tiếng Anh theo từ điển thì không gạch ("lag" là từ tiếng Anh trong từ điển của macOS).
    @Test func englishWordsAreLeftAlone() {
        #expect(typedThenChecked("ddos lag ", lexicon: EnglishDungs(alsoEnglish: ["lag"])).found == [])
    }
}

/// Từ điển từ ghép dựng sẵn (`Compounds`): dữ liệu đọc được và đúng với những từ ai cũng biết.
@Suite struct CompoundTable {
    @Test func loads() {
        #expect(Compounds.baseCount == CommonWords.entryCount)
        #expect(Compounds.compoundCount > 40_000)
    }

    @Test(arguments: [("bánh", "chưng"), ("giữ", "gìn"), ("chia", "sẻ"), ("sửa", "chữa"), ("học", "sinh"), ("Học", "Sinh"), ("hoà", "bình"), ("hòa", "bình")])
    func knowsRealCompounds(a: String, b: String) { #expect(Compounds.contains(a, b)) }

    @Test(arguments: [("bánh", "trưng"), ("dữ", "gìn"), ("chia", "sẽ"), ("sinh", "học2"), ("", ""), ("xyz", "abc")])
    func rejectsTheRest(a: String, b: String) { #expect(!Compounds.contains(a, b)) }

    /// Từ đơn hiếm: có trong từ điển, không có trong bảng tần suất.
    @Test func rareWords() {
        #expect(Compounds.isRareWord("quẫy"))
        #expect(!Compounds.isRareWord("được"))  // có trong bảng tần suất
        #expect(!Compounds.isRareWord("dới"))
    }
}
