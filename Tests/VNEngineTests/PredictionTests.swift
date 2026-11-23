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

@Suite struct Predictions {
    let lex = PredictLexicon()

    func engine(_ change: (inout Config) -> Void = { _ in }) -> Engine {
        var c = Config()
        change(&c)
        let e = Engine(config: c)
        e.lexicon = lex
        return e
    }

    func type(_ keys: String, _ e: Engine) -> String { run(keys, lexicon: lex, engine: e) }

    // MARK: - Từ đã có dấu

    @Test(arguments: [
        ("duojc ", "được "), ("dduowc ", "được "), ("dduocj ", "được "),
        ("nguoif ", "người "), ("khong ", "khong "),
        ("tieeng ", "tiếng "), ("nuowc ", "nước "), ("truowng ", "trường "),
        ("Duojc ", "Được "), ("DUOJC ", "ĐƯỢC "),
    ])
    func markedWordIsCompleted(keys: String, want: String) { #expect(type(keys, engine()) == want) }

    /// Gõ ra đúng một từ tiếng Việt khác thì đó là điều người dùng muốn: không đoán sang từ thông dụng hơn.
    @Test func realWordsAreNeverReplaced() {
        #expect(type("duowcj ", engine()) == "dược ")
        #expect(type("nguowi ", engine()) == "ngươi ")
        #expect(type("khoongs ", engine()) == "khống ")
    }

    @Test func worksWithPunctuationAndKeepsTheSeparator() {
        #expect(type("duojc, ", engine()) == "được, ")
        #expect(type("tooi duojc.", engine()) == "tôi được.")
    }

    @Test func ambiguousMarkedWordIsLeftAlone() {
        // "viêt": việt và viết đều thông dụng, không từ nào hơn hẳn.
        #expect(type("vieet ", engine()) == "viêt ")
        // "hoc" + sắc/nặng: học thông dụng hơn hẳn hóc.
        #expect(type("hocj ", engine()) == "học ")
    }

    // MARK: - Từ chưa có dấu nào

    @Test func unmarkedWordNeedsVietnameseContext() {
        #expect(type("tooi duoc ", engine()) == "tôi được ")
        #expect(type("tooi khong ", engine()) == "tôi không ")
        #expect(type("Vieejt Nam khong duoc ", engine()) == "Việt Nam không được ")  // "Nam" không dấu, "Việt" có
        #expect(type("con nguoi ", engine()) == "con nguoi ")  // "con" không dấu: chưa đủ bằng chứng
        #expect(type("duoc ", engine()) == "duoc ")  // đầu câu
        #expect(type("this user duoc ", engine()) == "this user duoc ")  // đang gõ tiếng Anh
    }

    @Test func unmarkedPredictionCanBeTurnedOff() {
        #expect(type("tooi duoc ", engine { $0.predictUnmarked = false }) == "tôi duoc ")
        #expect(type("duojc ", engine { $0.predictUnmarked = false }) == "được ")
    }

    // MARK: - Không được đụng tới

    @Test(arguments: [
        "ban ", "to ", "la ", "tooi ban ", "tooi to ",  // đã là từ tiếng Việt đúng
        "data ", "user ", "test ", "string ", "window ",  // tiếng Anh
        "tooi @duoc ", "a.duoc ", "duoc_x ",  // ngữ cảnh code
        "ko ", "dc ",  // viết tắt toàn phụ âm
    ])
    func leftAlone(keys: String) {
        let off = engine { $0.predict = false }
        #expect(type(keys, engine()) == type(keys, off), "\(keys)")
    }

    @Test func canBeTurnedOff() {
        #expect(type("duojc ", engine { $0.predict = false }) == "duojc ")
    }

    @Test func respectsLearnedWords() {
        let e = engine()
        e.preferRaw = ["duojc"]
        #expect(type("duojc ", e) == "duojc ")
    }

    // MARK: - Ngữ cảnh

    @Test func previousWordDecides() {
        let model = UsageModel()
        for _ in 0..<3 {
            model.record("được", after: "đã")
            model.record("dược", after: "ngành")
        }
        let e = engine()
        e.context = model
        #expect(type("ddax duojc ", e) == "đã được ")
        e.reset()
        #expect(type("nganhf duojc ", e) == "ngành dược ")
    }

    /// Chữ không dấu mà từ điển coi là từ đúng ("loi") chỉ được sửa bằng chính thói quen của người dùng: họ gõ
    /// "lầm lỗi" ít nhất ba lần VÀ nhiều hơn số lần gõ "lầm loi".
    @Test func learnedPairFixesAnUnmarkedRealWord() {
        let model = UsageModel()
        let e = engine()
        e.context = model
        #expect(type("laamf loi ", e) == "lầm loi ")  // chưa học gì: giữ nguyên
        e.reset()
        for _ in 0..<3 { _ = type("laamf looix ", e); e.reset() }
        #expect(model.pairCount("lỗi", after: "lầm") == 3)
        #expect(model.pairCount("loi", after: "lầm") == 1)  // lần gõ không dấu ở trên
        #expect(type("laamf loi ", e) == "lầm lỗi ")  // 3 lần có dấu > 1 lần không dấu
        #expect(model.pairCount("loi", after: "lầm") == 1)  // từ do VNKey sửa không tính là bằng chứng
    }

    /// Đúng trường hợp người dùng báo: thử "lầm loi" bốn lần trước khi VNKey học đủ, rồi gõ đúng bảy lần.
    @Test func earlierUnmarkedAttemptsDoNotBlockLearningForever() {
        let model = UsageModel()
        for _ in 0..<4 { model.record("loi", after: "lầm") }
        for _ in 0..<7 { model.record("lỗi", after: "lầm") }
        let e = engine()
        e.context = model
        #expect(type("laamf loi ", e) == "lầm lỗi ")
    }

    @Test func learnedPairNeedsAMajority() {
        let model = UsageModel()
        for _ in 0..<3 { model.record("này", after: "hôm") }
        for _ in 0..<3 { model.record("nay", after: "hôm") }
        let e = engine()
        e.context = model
        #expect(type("hoom nay ", e) == "hôm nay ")  // gõ không dấu cũng nhiều như có dấu: giữ nguyên
        // Hai lần có dấu chưa đủ để sửa.
        let few = UsageModel()
        for _ in 0..<2 { few.record("lỗi", after: "lầm") }
        let e2 = engine()
        e2.context = few
        #expect(type("laamf loi ", e2) == "lầm loi ")
    }

    /// Người dùng quay lại sửa một từ thì lần gõ cũ của từ đó không còn là bằng chứng (nó là gõ nhầm).
    @Test func correctedWordIsNotCountedTwice() {
        let model = UsageModel()
        let e = engine()
        e.context = model
        _ = type("laamf loi ", e)
        #expect(model.pairCount("loi", after: "lầm") == 1)
        _ = type("<<<<looix ", e)  // xoá "loi " rồi gõ lại có dấu
        #expect(model.pairCount("loi", after: "lầm") == 0)
        #expect(model.pairCount("lỗi", after: "lầm") == 1)
        // Quay lại sửa chữ cuối của một từ rồi gõ lại như cũ: vẫn chỉ tính một lần.
        _ = type("<<i ", e)
        #expect(model.pairCount("lỗi", after: "lầm") == 1)
    }

    /// Cả hai từ đều gõ không dấu ("lam loi"): nếu người dùng đã gõ "lầm lỗi" đủ nhiều, sửa luôn cả từ đứng trước.
    @Test func learnedPhraseFixesBothUnmarkedWords() {
        let model = UsageModel()
        for _ in 0..<3 { model.record("lỗi", after: "lầm") }
        let e = engine()
        e.context = model
        #expect(type("lam loi ", e) == "lầm lỗi ")
        #expect(e.fixedWord == "lầm lỗi")  // nháy cả hai từ vừa được thay
        e.reset()
        #expect(type("Lam loi, ", e) == "Lầm lỗi, ")  // giữ chữ hoa đầu của từ đứng trước
        e.reset()
        #expect(type("tooi lam loi ", e) == "tôi lầm lỗi ")
        // Từ do VNKey sửa không được ghi nhận là thói quen gõ không dấu.
        #expect(model.pairCount("loi", after: "lam") == 0)
        #expect(model.count("lam") == 0)
    }

    @Test func phraseFixNeedsClearEvidence() {
        // Chưa đủ ba lần.
        let few = UsageModel()
        for _ in 0..<2 { few.record("lỗi", after: "lầm") }
        let e1 = engine(); e1.context = few
        #expect(type("lam loi ", e1) == "lam loi ")
        // Người dùng cũng hay gõ đúng cụm không dấu đó ("to do" trong câu tiếng Anh): không sửa.
        let both = UsageModel()
        for _ in 0..<3 { both.record("đỏ", after: "tô") }
        for _ in 0..<3 { both.record("do", after: "to") }
        let e2 = engine(); e2.context = both
        #expect(type("to do ", e2) == "to do ")
        // Hai cụm có dấu cùng khớp và ngang nhau: không rõ.
        let two = UsageModel()
        for _ in 0..<3 { two.record("lỗi", after: "lầm") }
        for _ in 0..<3 { two.record("lời", after: "làm") }
        let e3 = engine(); e3.context = two
        #expect(type("lam loi ", e3) == "lam loi ")
        // Tắt đoán từ không dấu thì không sửa.
        let m = UsageModel()
        for _ in 0..<3 { m.record("lỗi", after: "lầm") }
        let e4 = engine { $0.predictUnmarked = false }; e4.context = m
        #expect(type("lam loi ", e4) == "lam loi ")
    }

    /// Gõ không dấu một cụm thì cụm đó được đếm, kể cả khi quanh đó không có từ nào có dấu: đây là bằng chứng
    /// duy nhất cho biết người dùng có thật sự viết cụm ấy không dấu hay không.
    @Test func plainPhrasesAreCounted() {
        let model = UsageModel()
        let e = engine()
        e.context = model
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
        let e = engine()
        e.context = model
        _ = type("hoom nay ", e)
        #expect(model.pairCount("nay", after: "hôm") == 1)
    }

    @Test func autoFixIsReportedForTheFlash() {
        let e = engine()
        _ = type("duojc", e)
        #expect(e.fixedWord == nil)
        _ = e.type(" ")
        #expect(e.fixedWord == "được")
        _ = e.type("a")
        #expect(e.fixedWord == nil)
        let e2 = engine()
        _ = type("tooi ", e2)  // gõ đúng, không sửa gì
        #expect(e2.fixedWord == nil)
    }

    @Test func engineRecordsWhatTheUserTypes() {
        let model = UsageModel()
        let e = engine()
        e.context = model
        _ = type("tooi ddax dduowcj hocj ", e)
        #expect(model.count("được") == 1)
        #expect(model.pairCount("được", after: "đã") == 1)
        #expect(model.pairCount("đã", after: "tôi") == 1)
        // Từ do VNKey đoán ra không được tính là bằng chứng.
        _ = type("duojc ", e)
        #expect(model.count("được") == 1)
    }

    /// Gợi ý theo câu của từ điển hệ thống phân biệt được nghĩa theo từ đứng trước, nên được hỏi trước danh
    /// sách từ thông dụng (vốn không biết ngữ cảnh).
    @Test func systemGuessUsesThePreviousWord() {
        lex.ranked["tiếng viet"] = "việt"
        lex.ranked["bài viet"] = "viết"
        lex.ranked["ngành duọc"] = "dược"
        #expect(type("tieengs viet ", engine()) == "tiếng việt ")
        #expect(type("baif viet ", engine()) == "bài viết ")
        #expect(type("nganhf duojc ", engine()) == "ngành dược ")  // thắng cả danh sách thông dụng ("được")
    }

    @Test func whatTheUserTypedBeforeBeatsTheSystemGuess() {
        lex.ranked["ngành duọc"] = "dược"
        let model = UsageModel()
        for _ in 0..<3 { model.record("được", after: "ngành") }
        let e = engine()
        e.context = model
        #expect(type("nganhf duojc ", e) == "ngành được ")
    }

    @Test func systemGuessBreaksTiesForMarkedWords() {
        lex.ranked["viêt"] = "việt"
        #expect(type("vieet ", engine()) == "việt ")
    }

    // MARK: - Hoàn tác, xoá lùi

    @Test func toggleRestoresTypedKeysAndRemembers() {
        let e = engine()
        #expect(type("duojc ~", e) == "duojc ")
        #expect(e.preferRaw.contains("duojc"))
        #expect(type("duojc ", e) == "duojc ")
    }

    @Test func backspaceAfterPredictionIsPlain() {
        let e = engine()
        #expect(type("duojc <<", e) == "đượ")
        #expect(e.currentWord == "đượ")
        #expect(type("duojc <<c ", engine()) == "được ")
    }

    @Test func retypingTheSameKeysKeepsThem() {
        let e = engine()
        #expect(type("duojc <<<<<duojc ", e) == "duojc ")
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
