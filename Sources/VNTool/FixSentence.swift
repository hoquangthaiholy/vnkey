import Foundation

#if canImport(FoundationModels)
import FoundationModels
import VNEngine

/// THỬ NGHIỆM (2026-11-25): sửa cả câu bằng mô hình ngôn ngữ chạy trên máy của macOS (Foundation Models, từ macOS 26,
/// cần bật Apple Intelligence). Chỉ là lệnh đo chất lượng và tốc độ trong `vnkey-tool`; ứng dụng chưa dùng. Không có
/// gì rời khỏi máy.
@available(macOS 26.0, *)
enum SentenceFixer {
    /// Câu mẫu lấy từ các lỗi đã gặp khi làm bộ soát lỗi: (câu gõ, câu đúng).
    static let samples: [(String, String)] = [
        ("em co muon lam viec voi thay khong", "em có muốn làm việc với thầy không"),
        ("hom nay troi dep qua", "hôm nay trời đẹp quá"),
        ("toi dang hoc tieng viet", "tôi đang học tiếng việt"),
        ("Tiếng viet giàu và đẹp.", "Tiếng việt giàu và đẹp."),
        ("tôi đươc nghỉ hai ngày", "tôi được nghỉ hai ngày"),
        ("Đi vễ nhà thôi", "Đi về nhà thôi"),
        ("em làm việc dới thầy", "em làm việc với thầy"),
        ("trời xắp mưa rồi", "trời sắp mưa rồi"),
        ("chời ơi đẹp quá", "trời ơi đẹp quá"),
        ("anh lói gì thế", "anh nói gì thế"),
        ("cảm ơn bạn đã chia sẽ", "cảm ơn bạn đã chia sẻ"),
        ("xe đang sữa chữa", "xe đang sửa chữa"),
        ("con hưu cao cổ", "con hươu cao cổ"),
        ("bánh trưng ngày tết", "bánh chưng ngày tết"),
        ("dữ gìn sức khoẻ nhé", "giữ gìn sức khoẻ nhé"),
        ("đi ra ngoài rưng", "đi ra ngoài rừng"),
        ("tôi uống riệu với bạn", "tôi uống rượu với bạn"),
        ("anh ấy tậu xe mới", "anh ấy tậu xe mới"),  // câu đúng: không được đổi
        ("gửi file data cho user nhé", "gửi file data cho user nhé"),  // xen tiếng Anh: không được đổi
        ("mai hop luc 3 gio chieu o phong 204", "mai họp lúc 3 giờ chiều ở phòng 204"),
    ]

    /// Chạy một việc khác "sửa chính tả" (cải tiến, viết lại, rút gọn, mở rộng, dịch) trên vài câu và in kết quả.
    static func run(task: SentenceTask, _ inputs: [String]) {
        guard case .available = SystemLanguageModel.default.availability else { return print("Mô hình trên máy chưa dùng được.") }
        let texts = inputs.isEmpty
            ? ["em có muốn làm việc với thầy không", "hôm nay trời đẹp quá nên tôi đi dạo một chút rồi mới về nhà làm việc tiếp", "gửi file data cho user nhé", "The meeting was moved to Friday afternoon."]
            : inputs
        let done = DispatchSemaphore(value: 0)
        Task {
            for text in texts {
                let start = Date()
                do {
                    let answer = try await LanguageModelSession(instructions: task.instructions(for: text)).respond(
                        to: task.prompt(for: text), options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 400))
                    print(String(format: "%5.0f ms  %@\n          -> %@", Date().timeIntervalSince(start) * 1000, text, task.clean(answer.content, original: text)))
                } catch {
                    print("LỖI  \(text): \(error)")
                }
            }
            done.signal()
        }
        done.wait()
    }

    /// Đo đường dự phòng không dùng mô hình (`Proofreader.restore`) trên cùng bộ câu mẫu.
    static func runLocal(_ inputs: [String], lexicon: Lexicon?) {
        let reader = Proofreader()
        reader.lexicon = lexicon
        let cases: [(String, String?)] = inputs.isEmpty ? samples.map { ($0.0, $0.1) } : inputs.map { ($0, nil) }
        var right = 0, total = 0.0
        for (text, want) in cases {
            let start = Date()
            let fixed = reader.restore(text)
            let ms = Date().timeIntervalSince(start) * 1000
            total += ms
            var mark = ""
            if let want {
                let ok = SentenceFilter.same(fixed, want)
                if ok { right += 1 }
                mark = ok ? "ĐÚNG" : "SAI "
            }
            print(String(format: "%@ %6.1f ms  %@\n               -> %@", mark, ms, text, fixed))
        }
        if inputs.isEmpty { print(String(format: "\nThuật toán trên máy: %d/%d câu đúng, trung bình %.1f ms mỗi câu.", right, cases.count, total / Double(cases.count))) }
    }

    static func run(_ inputs: [String]) {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            print("Mô hình trên máy chưa dùng được: \(model.availability)")
            return
        }
        print("Hỗ trợ tiếng Việt (vi_VN): \(model.supportsLocale(Locale(identifier: "vi_VN")))")
        let cases: [(String, String?)] = inputs.isEmpty ? samples.map { ($0.0, $0.1) } : inputs.map { ($0, nil) }
        let done = DispatchSemaphore(value: 0)
        Task {
            var right = 0, rawRight = 0, total = 0.0
            for (text, want) in cases {
                // Mỗi câu một phiên mới: câu trước không ảnh hưởng câu sau.
                let session = LanguageModelSession(instructions: SentenceFilter.instructions)
                let start = Date()
                do {
                    let answer = try await session.respond(
                        to: text, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 200))
                    let ms = Date().timeIntervalSince(start) * 1000
                    total += ms
                    let raw = answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Chỉ giữ chỗ mô hình sửa dấu / sửa âm của từng từ; dấu câu, hoa thường, từ tiếng Anh theo câu gốc.
                    let fixed = SentenceFilter.merge(original: text, proposed: raw)
                    var mark = ""
                    if let want {
                        let ok = SentenceFilter.same(fixed, want)
                        if ok { right += 1 }
                        if SentenceFilter.same(raw, want) { rawRight += 1 }
                        mark = ok ? "ĐÚNG" : "SAI "
                    }
                    print(String(format: "%@ %5.0f ms  %@", mark, ms, text))
                    print("              mô hình: \(raw)")
                    print("              sau lọc: \(fixed)")
                } catch {
                    print("LỖI  \(text): \(error)")
                }
            }
            if inputs.isEmpty {
                print(String(format: "\nSau lọc: %d/%d câu đúng. Chưa lọc: %d/%d. Trung bình %.0f ms mỗi câu.", right, cases.count, rawRight, cases.count, total / Double(cases.count)))
            }
            done.signal()
        }
        done.wait()
    }
}
#endif
