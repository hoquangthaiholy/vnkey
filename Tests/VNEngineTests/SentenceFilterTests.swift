import Foundation
import Testing

@testable import VNEngine

/// Bộ lọc kết quả sửa cả câu (`SentenceFilter`). Các cặp (câu gốc, câu mô hình trả về) lấy từ lần đo thật ngày
/// 2026-11-25 với mô hình chạy trên máy của macOS.
@Suite struct SentenceFiltering {
    @Test(arguments: [
        // Chỉ nhận chỗ sửa dấu: bỏ dấu hỏi và chữ hoa mô hình tự thêm.
        ("em co muon lam viec voi thay khong", "Em có muốn làm việc với thầy không?", "em có muốn làm việc với thầy không"),
        ("tôi đươc nghỉ hai ngày", "Tôi được nghỉ hai ngày.", "tôi được nghỉ hai ngày"),
        ("mai hop luc 3 gio chieu o phong 204", "Mai họp lúc 3 giờ chiều ở phòng 204", "mai họp lúc 3 giờ chiều ở phòng 204"),
        // Giữ hoa thường và dấu câu của người gõ.
        ("Tiếng viet giàu và đẹp.", "Tiếng Việt giàu và đẹp.", "Tiếng việt giàu và đẹp."),
        ("bánh trưng ngày tết", "Bánh chưng ngày Tết", "bánh chưng ngày tết"),
        // Sửa âm: nhận.
        ("em làm việc dới thầy", "Em làm việc với thầy.", "em làm việc với thầy"),
        ("tôi uống riệu với bạn", "tôi uống rượu với bạn", "tôi uống rượu với bạn"),
        ("cảm ơn bạn đã chia sẽ", "Cảm ơn bạn đã chia sẻ.", "cảm ơn bạn đã chia sẻ"),
        // Chỉ khác chỗ đặt dấu thanh: giữ cách viết của người gõ.
        ("dữ gìn sức khoẻ nhé", "Giữ gìn sức khỏe nhé", "giữ gìn sức khoẻ nhé"),
        // Mô hình dịch từ tiếng Anh, thêm bớt từ, viết lại câu: giữ nguyên câu gốc ở những chỗ đó.
        ("gửi file data cho user nhé", "gửi file dữ liệu cho người dùng nhé", "gửi file data cho user nhé"),
        ("tôi đi hoc", "Tôi đang đi đến trường học", "tôi đi học"),  // từ thêm vào bị bỏ; "hoc" vẫn được thêm dấu
        ("anh ấy tậu xe mới", "Anh ấy tậu xe mới.", "anh ấy tậu xe mới"),
        ("", "Xin chào", ""), ("xin chao", "", "xin chao"),
    ])
    func keepsOnlySpellingFixes(original: String, proposed: String, want: String) {
        #expect(SentenceFilter.merge(original: original, proposed: proposed) == want)
    }

    /// Câu chứa một đoạn: cắt ở dấu kết câu và xuống dòng, bỏ khoảng trắng hai đầu, không lấy dấu kết câu.
    @Test func findsTheSentenceAroundARange() {
        let text = "Xin chào. em làm việc dới thầy không? Vâng\ndòng hai ở đây"
        func cut(_ r: Range<Int>?) -> String? { r.map { String(Array(text.utf16)[$0].map { Character(UnicodeScalar($0)!) }) } }
        let at = (text as NSString).range(of: "dới")
        #expect(cut(SentenceFilter.sentence(in: text, around: at.location..<(at.location + at.length))) == "em làm việc dới thầy không")
        let two = (text as NSString).range(of: "hai")
        #expect(cut(SentenceFilter.sentence(in: text, around: two.location..<(two.location + two.length))) == "dòng hai ở đây")
        // Chỉ một từ thì không có "câu" để sửa; câu dài quá giới hạn cũng không đưa cho mô hình.
        let one = (text as NSString).range(of: "Vâng")
        #expect(SentenceFilter.sentence(in: text, around: one.location..<(one.location + one.length)) == nil)
        #expect(SentenceFilter.sentence(in: text, around: at.location..<(at.location + at.length), limit: 10) == nil)
        #expect(SentenceFilter.sentence(in: "abc", around: 5..<9) == nil)
    }

    /// Các việc khác với câu: chỉ dẫn và lời nhắn viết theo ngôn ngữ của câu. (Lỗi đã gặp: mọi câu bị coi là tiếng
    /// Việt vì bảng tra chữ có cả nguyên âm không dấu, nên câu tiếng Anh nhận yêu cầu tiếng Việt.)
    @Test func tasksFollowTheLanguageOfTheSentence() {
        #expect(SentenceTask.isVietnamese("em có muốn làm việc không"))
        #expect(SentenceTask.isVietnamese("gửi file data cho user nhé"))
        #expect(!SentenceTask.isVietnamese("The meeting was moved to Friday afternoon."))
        #expect(!SentenceTask.isVietnamese("a e i o u y d"))
        #expect(SentenceTask.improve.prompt(for: "The meeting was moved.").contains("answer in English"))
        #expect(SentenceTask.translate.prompt(for: "The meeting was moved.").contains("tiếng Việt"))
        #expect(SentenceTask.translate.prompt(for: "tôi đi học").contains("into English"))
        #expect(SentenceTask.fix.prompt(for: "tôi đi hoc") == "tôi đi hoc")
        // Việc khác `fix` không qua bộ lọc: lấy câu mô hình trả về, bỏ ngoặc kép bao ngoài.
        #expect(SentenceTask.rewrite.clean(" “Em có sẵn sàng không?” ", original: "em có muốn không") == "Em có sẵn sàng không?")
        #expect(SentenceTask.fix.clean("Em có muốn không?", original: "em co muon khong") == "em có muốn không")
    }

    @Test func comparesIgnoringCaseAndToneplacement() {
        #expect(SentenceFilter.same("Giữ gìn sức khoẻ", "giữ gìn sức khỏe"))
        #expect(!SentenceFilter.same("con hưu", "con hươu"))
        #expect(!SentenceFilter.same("xong rồi", "xong rồi."))
    }
}

/// Chấm điểm một lần sửa câu (`SentenceFilter.score`), cho bộ đo `vnkey-tool eval`.
@Suite struct SentenceScoring {
    @Test func countsFixedMissedAndHarmed() {
        // "hop" được sửa, "luc" bị bỏ sót, "mai" vốn đúng bị đổi bậy.
        let s = SentenceFilter.score(typed: "mai hop luc ba giờ", want: "mai họp lúc ba giờ", got: "mái họp luc ba giờ")
        #expect(s.syllables == 5)
        #expect(s.errors == 2)
        #expect(s.right == 3)
        #expect(s.missed == 1)
        #expect(s.harmed == 1)
        #expect(!s.exact)
        #expect(!s.reshaped)
    }

    @Test func ignoresCaseAndToneplacement() {
        let s = SentenceFilter.score(typed: "suc khoe", want: "sức khoẻ", got: "Sức khỏe")
        #expect(s.right == 2)
        #expect(s.exact)
    }

    @Test func punctuationOnlyBreaksTheWholeSentence() {
        let s = SentenceFilter.score(typed: "toi di hoc", want: "tôi đi học", got: "Tôi đi học.")
        #expect(s.right == 3)
        #expect(!s.exact)
    }

    @Test func changedWordCountIsNotScoredPerSyllable() {
        let s = SentenceFilter.score(typed: "toi di hoc", want: "tôi đi học", got: "tôi đang đi học")
        #expect(s.reshaped)
        #expect(s.right == 0)
        #expect(s.missed == 3)
    }

    @Test func confusionsSplitToneFromSound() {
        let reader = Proofreader()
        #expect(reader.confusions(of: "sẻ", tonesOnly: true).contains("sẽ"))
        #expect(!reader.confusions(of: "sẻ").contains("sẽ"))
        #expect(reader.confusions(of: "chưng").contains("trưng"))
    }
}
