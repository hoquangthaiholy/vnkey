import Foundation
import Testing

@testable import VNEngine

/// Từ điển giả đủ lớn để thử việc đoán từ gõ thiếu dấu.
final class PredictLexicon: Lexicon {
    let en: Set<String> = ["data", "user", "test", "this", "fix", "string", "window", "error", "can", "ban"]
    let vi: Set<String> = [
        "được", "dược", "đước", "người", "ngươi", "nguôi", "nguội", "không", "khống", "khổng", "tiếng",
        "việt", "viết", "tôi", "đã", "ngành", "là", "của", "ban", "bạn", "bán", "bàn", "to", "tô", "tơ", "la",
        "con", "nước", "học", "hóc", "trường", "trưởng", "thuốc", "thuộc", "gọn", "gòn", "sài", "một", "mốt",
    ]
    /// Câu trả lời giả cho tầng "gợi ý của macOS": từ gõ -> từ được chọn.
    var ranked: [String: String] = [:]
    func isEnglish(_ w: String) -> Bool { en.contains(w) }
    func isVietnamese(_ w: String) -> Bool { vi.contains(w) }
    func rank(_ candidates: [String], after context: [String], typed: String) -> String? {
        ranked[typed].flatMap { candidates.contains($0) ? $0 : nil }
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
