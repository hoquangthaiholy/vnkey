import Foundation
import Testing

@testable import VNEngine

/// Từ điển nhỏ riêng cho bộ này, để không đụng tới `FakeLexicon` mà các bộ khác đang dựa vào.
private final class TypoLexicon: Lexicon {
    let en: Set<String> = ["the", "user"]
    let vi: Set<String> = ["gõ", "ban", "bạn", "tôi", "anh", "muôn", "muốn"]
    func isEnglish(_ w: String) -> Bool { en.contains(w) }
    func isVietnamese(_ w: String) -> Bool { vi.contains(w) }
}

/// Học lỗi gõ từ chính những lần người dùng sửa: gõ "goc", sửa thành "gox" (gõ) hai lần thì lần sau tự sửa.
@Suite struct LearnedTypos {
    private let lexicon = TypoLexicon()

    private func engine(_ cfg: Config = Config()) -> (Engine, UsageModel) {
        let e = Engine(config: cfg), model = UsageModel()
        e.context = model
        return (e, model)
    }

    private func type(_ keys: String, _ e: Engine) -> String { run(keys, lexicon: lexicon, engine: e) }

    /// Ba cách sửa: xoá phím sai giữa từ; quay lại sau dấu cách; xoá hết rồi gõ lại.
    @Test(arguments: ["goc<x ", "goc <<x ", "goc<<<gox "])
    func learnsFromEachWayOfCorrecting(fix: String) {
        let (e, _) = engine()
        #expect(type(fix + fix, e) == "gõ gõ ")
        #expect(type("goc ", e) == "gõ ")
        #expect(e.fixedWord == "gõ")  // app nháy từ vừa được sửa
    }

    @Test func oneCorrectionIsNotEnough() {
        let (e, _) = engine()
        #expect(type("goc<x goc ", e) == "gõ goc ")
    }

    /// Người dùng cũng hay gõ "goc" rồi giữ nguyên: đó không phải lỗi gõ.
    @Test func keptAsOftenAsCorrectedIsNotATypo() {
        let (e, _) = engine()
        #expect(type("goc<x goc goc goc goc<x goc<x goc ", e) == "gõ goc goc goc gõ gõ goc ")
    }

    /// Quay lại sửa một từ đã giữ thì lần giữ đó không tính.
    @Test func goingBackToFixDoesNotCountAsKept() {
        let (e, _) = engine()
        // Một lần giữ thật ("goc" rồi gõ từ khác), hai lần sửa trong đó một lần là quay lại sau dấu cách. Nếu lần
        // quay lại ấy vẫn bị đếm là "giữ" thì giữ = 2 = số lần sửa và từ sẽ không được học.
        #expect(type("goc<x goc tooi goc <<x ", e) == "gõ goc tôi gõ ")
        #expect(type("goc ", e) == "gõ ")
    }

    /// Từ gõ chưa trọn mà lại là một từ thật ("muôn" thiếu dấu sắc của "muốn"): phần đoán dấu không được đụng
    /// tới nó, nhưng người dùng đã tự sửa đủ lần thì VNKey sửa theo. (Chữ gõ dở không phải từ thật như "dúng" nay
    /// đã được phần đoán dấu sửa ngay, xem `PredictionsWithLenientDictionary`.)
    /// Cả hai cách sửa: thêm phím còn thiếu sau khi quay lại, và xoá hết gõ lại.
    @Test(arguments: ["muoon <s ", "muoon<<<<muoons "])
    func fixesIncompleteWordsThatAreRealWords(fix: String) {
        let (e, _) = engine()
        #expect(type(fix + fix, e) == "muốn muốn ")
        #expect(type("muoon ", e) == "muốn ")
    }

    /// Từ có trong từ điển mà người dùng cũng hay gõ thật thì không bị thay: số lần để nguyên chặn lại.
    @Test func realWordTheUserAlsoTypesIsKept() {
        let (e, _) = engine()
        #expect(type("ban<nj ban tooi ban tooi ban tooi ban<nj ban<nj ban ", e) == "bạn ban tôi ban tôi ban tôi bạn bạn ban ")
    }

    @Test func worksForEnglishToo() {
        let (e, _) = engine()
        #expect(type("teh<<he teh<<he teh<<he teh ", e) == "the the the the ")
    }

    @Test func keepsTheCaseOfWhatWasTyped() {
        let (e, _) = engine()
        _ = type("goc<x goc<x goc<x ", e)
        #expect(type("Goc ", e) == "Gõ ")
        #expect(type("GOC ", e) == "GÕ ")
    }

    /// Xoá cả từ để gõ từ khác hẳn không phải là sửa lỗi gõ.
    @Test func ignoresRewritesThatDifferByMoreThanOneKey() {
        let (e, model) = engine()
        _ = type("tooi<<<anh tooi<<<anh tooi<<<anh ", e)
        #expect(model.learnedTypos().isEmpty)
        #expect(type("tooi ", e) == "tôi ")
    }

    @Test func leavesCodeAlone() {
        let (e, model) = engine()
        _ = type("a.goc<x a.goc<x a.goc<x ", e)
        #expect(model.learnedTypos().isEmpty)
        _ = type("goc<x goc<x goc<x ", e)
        #expect(type("a.goc ", e) == "a.goc ")
    }

    /// Phím "Đổi từ vừa gõ" trả lại đúng những phím đã gõ và rút lại việc học.
    @Test func flipKeyRestoresAndUnlearns() {
        let (e, model) = engine()
        _ = type("goc<x goc<x goc<x ", e)
        #expect(type("goc ~", e) == "goc ")
        #expect(model.learnedTypos().isEmpty)
        #expect(type("goc ", e) == "goc ")
    }

    @Test func respectsTheSwitch() {
        var cfg = Config()
        cfg.fixTypos = false
        let (e, _) = engine(cfg)
        #expect(type("goc<x goc<x goc<x goc ", e) == "gõ gõ gõ goc ")
    }

    @Test func stopsLearningWhenRecordingIsOff() {
        let (e, model) = engine()
        model.recording = false
        #expect(type("goc<x goc<x goc<x goc ", e) == "gõ gõ gõ goc ")
    }

    @Test(arguments: [
        ("goc", "gox", true), ("teh", "the", true), ("ban", "banj", true), ("banj", "ban", true), ("tooi", "toi", true),
        ("goc", "goc", false), ("tooi", "anh", false), ("goc", "goxx", false), ("abc", "cba", false), ("ab", "ba", true),
    ])
    func oneKeyApart(a: String, b: String, expected: Bool) {
        #expect(Engine.oneKeyApart(a, b) == expected)
    }

    @Test func modelThresholdsAndStorage() {
        let model = UsageModel()
        for _ in 0..<3 { model.recordTypo("goc", fixed: "gox") }
        model.recordTypo("goc", fixed: "gos")
        #expect(model.typoFix(for: "goc") == "gox")
        model.recordTypo("goc", fixed: "gos")  // ứng viên thứ hai quá gần: không còn chắc
        #expect(model.typoFix(for: "goc") == nil)

        let back = UsageModel(data: model.data())
        #expect(back?.learnedTypos().isEmpty == true)
        for _ in 0..<3 { back?.recordTypo("goc", fixed: "gox") }
        #expect(back?.typoFix(for: "goc") == "gox")
        #expect(back?.learnedTypos() == [UsageModel.LearnedTypo(wrong: "goc", right: "gox", count: 6)])

        // Tệp của bản cũ không có bảng lỗi gõ vẫn đọc được.
        #expect(UsageModel(data: Data(#"{"version":1,"words":{"a":1},"pairs":{}}"#.utf8))?.count("a") == 1)

        back?.forgetTypo("goc", fixed: "gox")
        #expect(back?.typoFix(for: "goc") == nil)
        for _ in 0..<2 { back?.recordTypo("goc", fixed: "gox") }
        #expect(back?.typoFix(for: "goc") == nil)  // vừa bị từ chối: cần nhiều bằng chứng hơn mới học lại
        back?.clear()
        #expect(back?.learnedTypos().isEmpty == true)
    }
}
