import Foundation
import Testing

@testable import VNEngine

/// Từ điển giả đủ lớn để thử việc đoán từ gõ thiếu dấu.
final class PredictLexicon: Lexicon {
    let en: Set<String> = ["data", "user", "test", "this", "fix", "string", "window", "error", "can", "ban"]
    let vi: Set<String> = [
        "được", "dược", "đước", "người", "ngươi", "nguôi", "nguội", "không", "khống", "khổng", "tiếng",
        "việt", "viết", "tôi", "đã", "ngành", "là", "của", "ban", "bạn", "bán", "bàn", "to", "tô", "tơ", "la",
        "con", "nước", "học", "bài", "lầm", "lỗi", "lời", "lôi", "loi", "hôm", "nay", "này", "nãy",
        "lam", "làm", "do", "đỏ", "bè", "be", "bạn", "hóc", "trường", "trưởng", "thuốc", "thuộc", "gọn", "gòn", "sài", "một", "mốt",
    ]
    /// Câu trả lời giả cho tầng "gợi ý của macOS": từ gõ -> từ được chọn.
    var ranked: [String: String] = [:]
    func isEnglish(_ w: String) -> Bool { en.contains(w) }
    func isVietnamese(_ w: String) -> Bool { vi.contains(w) }
    /// Khoá là "từ trước + chữ đang hiện" (vd "tiếng viet") hoặc chỉ chữ đang hiện.
    func rank(_ candidates: [String], after context: [String], typed: String) -> String? {
        let withContext = context.last.map { $0.lowercased() + " " + typed }
        let pick = withContext.flatMap { ranked[$0] } ?? ranked[typed]
        return pick.flatMap { candidates.contains($0) ? $0 : nil }
    }
}

/// Từ điển dễ dãi như của macOS: mọi âm tiết đúng cấu trúc đều được coi là từ tiếng Việt ("tiêng", "dúng", "ròi").
final class LenientLexicon: Lexicon {
    var ranked: [String: String] = [:]
    func isEnglish(_ w: String) -> Bool { false }
    func isVietnamese(_ w: String) -> Bool { Charset.syllableKey(w) != nil }
    func rank(_ candidates: [String], after context: [String], typed: String) -> String? {
        let pick = context.last.flatMap { ranked[$0.lowercased() + " " + typed] } ?? ranked[typed]
        return pick.flatMap { candidates.contains($0) ? $0 : nil }
    }
}

/// Như `LenientLexicon`, và coi "dungs" là từ tiếng Anh (đúng như từ điển macOS).
final class EnglishDungs: Lexicon {
    let alsoEnglish: Set<String>
    init(alsoEnglish: Set<String> = []) { self.alsoEnglish = alsoEnglish }
    func isEnglish(_ w: String) -> Bool { w == "dungs" || alsoEnglish.contains(w) }
    func isVietnamese(_ w: String) -> Bool { Charset.syllableKey(w) != nil }
}


/// Thứ tự đề nghị khi một từ thiếu dấu có nhiều ứng viên, và những từ không được gạch chân. Trước 2026-11-25 các ca
/// này là "đoán rồi tự thay"; nay engine để nguyên chữ đã gõ và `Proofreader` đề nghị.
@Suite struct MissingMarkSuggestions {
    func check(_ text: String, model: ContextModel? = nil, lexicon: Lexicon = LenientLexicon()) -> [ProofIssue] {
        let p = Proofreader()
        p.lexicon = lexicon
        p.context = model
        return p.check(text)
    }

    func first(_ text: String, model: ContextModel? = nil) -> [String] {
        check(text, model: model).map { "\($0.text)>\($0.suggestions.first ?? "")" }
    }

    /// Từ điển của macOS coi "tiêng", "dúng", "ròi" là từ đúng; trọng tài ở đây là bảng tần suất.
    @Test(arguments: [("tiêng", "tiếng"), ("dúng", "đúng"), ("đung", "đúng"), ("ròi", "rồi"), ("đươc", "được"), ("duọc", "được"), ("duojc", "được"), ("tieesng", "tiếng")])
    func wordsMissingFromTheTableGetTheCommonCandidate(word: String, want: String) {
        #expect(first("nói \(word) xong") == ["\(word)>\(want)"])
    }

    /// Gõ thiếu một phím dễ xảy ra hơn thiếu hai: "dúng" là "đúng" (thiếu một) trước "đứng" (thiếu hai).
    @Test func fewerMissingKeysComesFirst() {
        let s = check("dúng").first?.suggestions ?? []
        #expect(s.first == "đúng")
        #expect(s.contains("đứng"))
    }

    /// Từ có trong bảng không bao giờ bị gạch, dù có từ khác thông dụng hơn nhiều.
    @Test(arguments: ["muôn", "trương", "dược", "khống", "ngươi", "tôi bán nhà", "cái bàn này", "hôm nay", "Việt Nam"])
    func realWordsAreNeverFlagged(text: String) { #expect(first(text) == []) }

    /// Chữ không có trong bảng nhưng chính người dùng hay gõ: đó là từ của họ.
    @Test func wordsTheUserReallyTypesAreKept() {
        let model = UsageModel()
        #expect(first("làm việc dới thầy", model: model) == ["dới>với"])
        model.record("dới", after: "việc")
        model.record("dới", after: "việc")
        #expect(first("làm việc dới thầy", model: model) == [])
    }

    /// Cặp từ chính người dùng đã gõ đi trước kho ngữ liệu khi xếp thứ tự đề nghị.
    @Test func theUsersOwnPairsComeFirst() {
        #expect(first("bài viêt") == ["viêt>viết"])
        let model = UsageModel()
        for _ in 0..<3 { model.record("việt", after: "bài") }
        #expect(first("bài viêt", model: model) == ["viêt>việt"])
    }

    /// Từ đứng SAU cũng được xét: "viêt nam" là "việt nam" dù không có từ đứng trước.
    @Test func theNextWordCounts() {
        #expect(first("viêt nam") == ["viêt>việt"])
        #expect(first("viêt thư") == ["viêt>viết"])
    }

    @Test func frequencyTable() {
        #expect(CommonWords.count("được") > 100_000)
        #expect(CommonWords.count("Được") == CommonWords.count("được"))
        #expect(CommonWords.count("hoà") == CommonWords.count("hòa") && CommonWords.count("hòa") > 1000)  // hai cách đặt dấu
        #expect(CommonWords.count("tiêng") == 0 && CommonWords.count("xyz") == 0)
        #expect(CommonWords.count("muôn") >= CommonWords.tableFloor)
    }
}

/// Engine không còn đoán hay sửa gì; nó vẫn ghi thói quen gõ để bộ soát lỗi dùng.
@Suite struct TypingHabitsAreRecorded {
    let lex = PredictLexicon()

    func engine(_ model: UsageModel) -> Engine {
        let e = Engine()
        e.lexicon = lex
        e.context = model
        return e
    }

    func type(_ keys: String, _ e: Engine) -> String { run(keys, lexicon: lex, engine: e) }

    /// Những chuỗi bản tự sửa từng thay nay hiện đúng như đã gõ.
    @Test(arguments: [("duojc ", "duojc "), ("tieeng ", "tiêng "), ("tooi dduowc ", "tôi đươc "), ("lam loi ", "lam loi ")])
    func nothingIsGuessed(keys: String, want: String) {
        let model = UsageModel()
        for _ in 0..<3 {
            model.record("lầm", after: nil)
            model.record("lỗi", after: "lầm")
        }
        #expect(type(keys, engine(model)) == want)
    }

    /// Gõ không dấu một cụm thì cụm đó được đếm, kể cả khi quanh đó không có từ nào có dấu: đây là bằng chứng
    /// duy nhất cho biết người dùng có thật sự viết cụm ấy không dấu hay không.
    @Test func plainPhrasesAreCounted() {
        let model = UsageModel()
        let e = engine(model)
        _ = type("to do ", e)
        #expect(model.pairCount("do", after: "to") == 1)
        #expect(model.count("to") == 1)
        // Từ không phải tiếng Việt (kể cả khi là tiếng Anh) thì không đếm.
        e.reset()
        _ = type("user data ", e)
        #expect(model.count("user") == 0 && model.count("data") == 0)
    }

    @Test func unmarkedVietnameseWordsAreRecordedInContext() {
        let model = UsageModel()
        _ = type("hoom nay ", engine(model))
        #expect(model.pairCount("nay", after: "hôm") == 1)
    }

    @Test func engineRecordsWhatTheUserTypes() {
        let model = UsageModel()
        let e = engine(model)
        _ = type("tooi ddax dduowcj hocj ", e)
        #expect(model.count("được") == 1)
        #expect(model.pairCount("được", after: "đã") == 1)
        #expect(model.pairCount("đã", after: "tôi") == 1)
        // Chữ gõ thiếu dấu không phải từ tiếng Việt nên không được đếm.
        _ = type("duojc ", e)
        #expect(model.count("được") == 1)
    }

    /// Phím Đổi từ chỉ còn hai dạng: phím gốc và tiếng Việt.
    @Test func flipKeyHasTwoForms() {
        let model = UsageModel()
        #expect(type("duojc ~", engine(model)) == "duọc ")
        #expect(type("duojc ~~", engine(model)) == "duojc ")
    }
}

@Suite struct UsageModels {
    @Test func countsWordsAndPairs() {
        let m = UsageModel()
        m.record("được", after: "đã")
        m.record("được", after: nil)
        #expect(m.count("được") == 2)
        #expect(m.pairCount("được", after: "đã") == 1)
        #expect(m.pairCount("được", after: "ngành") == 0)
    }

    @Test func survivesSaveAndLoad() throws {
        let m = UsageModel()
        m.record("được", after: "đã")
        let copy = try #require(UsageModel(data: m.data()))
        #expect(copy.count("được") == 1)
        #expect(copy.pairCount("được", after: "đã") == 1)
        #expect(UsageModel(data: Data("rác".utf8)) == nil)
    }

    @Test func staysBounded() {
        let m = UsageModel(wordLimit: 50, pairLimit: 50)
        for _ in 0..<5 { m.record("được", after: "đã") }
        for i in 0..<500 { m.record("từ\(i)", after: "trước\(i)") }
        #expect(m.wordCount <= 50)
        #expect(m.pairTotal <= 50)
        #expect(m.count("được") == 5)  // từ dùng nhiều được giữ lại
    }

    @Test func findsThePhraseBehindPlainTyping() {
        let m = UsageModel()
        for _ in 0..<5 { m.record("lỗi", after: "lầm") }
        m.record("lời", after: "làm")
        m.record("loi", after: "lam")
        let hit = m.phrase(plainPrev: "lam", plainWord: "loi")
        #expect(hit?.prev == "lầm" && hit?.word == "lỗi" && hit?.count == 5)
        #expect(m.phrase(plainPrev: "lam", plainWord: "xyz") == nil)
        // Sống sót qua lưu/đọc lại và sau khi quên.
        let copy = UsageModel(data: m.data())
        #expect(copy?.phrase(plainPrev: "lam", plainWord: "loi")?.word == "lỗi")
        m.forget(prev: "lầm", word: "lỗi")
        #expect(m.phrase(plainPrev: "lam", plainWord: "loi") == nil)  // còn 1 lần "làm lời": chưa đủ ba
    }

    @Test func recordCanBeTakenBack() {
        let m = UsageModel()
        m.record("lỗi", after: "lầm")
        m.record("lỗi", after: "lầm")
        m.unrecord("lỗi", after: "lầm")
        #expect(m.count("lỗi") == 1 && m.pairCount("lỗi", after: "lầm") == 1)
        m.unrecord("lỗi", after: "lầm")
        m.unrecord("lỗi", after: "lầm")  // không âm
        #expect(m.count("lỗi") == 0 && m.pairCount("lỗi", after: "lầm") == 0 && m.wordCount == 0)
    }

    /// Danh sách hiện cho người dùng: chỉ những cặp đã đủ điều kiện để VNKey sửa dạng gõ không dấu.
    @Test func listsPairsThatWillBeFixed() {
        let m = UsageModel()
        for _ in 0..<7 { m.record("lỗi", after: "lầm") }
        for _ in 0..<4 { m.record("loi", after: "lầm") }  // gõ không dấu ít hơn: vẫn sửa
        for _ in 0..<3 { m.record("đắn", after: "đúng") }
        for _ in 0..<3 { m.record("dan", after: "đúng") }  // hoà: chưa sửa
        for _ in 0..<2 { m.record("được", after: "đã") }  // chưa đủ ba lần
        for _ in 0..<5 { m.record("nay", after: "hôm") }  // từ không dấu: không có gì để sửa
        for _ in 0..<4 { m.record("việt", after: "bài") }
        for _ in 0..<3 { m.record("viết", after: "bài") }  // hai dạng có dấu ngang nhau: không rõ
        #expect(m.learnedPairs() == [UsageModel.LearnedPair(prev: "lầm", word: "lỗi", plain: "loi", count: 7)])
    }

    @Test func forgettingAPairStopsTheFix() {
        let m = UsageModel()
        for _ in 0..<3 { m.record("lỗi", after: "lầm") }
        m.record("lỗi", after: "xin")
        m.markSaved()
        m.forget(prev: "lầm", word: "lỗi")
        #expect(m.pairCount("lỗi", after: "lầm") == 0)
        #expect(m.count("lỗi") == 1)  // lần gõ sau "xin" vẫn còn
        #expect(m.learnedPairs().isEmpty)
        #expect(m.dirty)
    }

    @Test func pausedModelRecordsNothing() {
        let m = UsageModel()
        m.recording = false
        m.record("được", after: "đã")
        #expect(m.count("được") == 0)
        m.recording = true
        m.record("được", after: "đã")
        m.clear()
        #expect(m.count("được") == 0 && m.wordCount == 0)
    }
}
