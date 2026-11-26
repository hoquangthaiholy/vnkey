import Foundation

#if canImport(FoundationModels)
import FoundationModels
import VNEngine

/// Luôn chọn từ có xác suất cao nhất, để cùng một câu luôn cho cùng một kết quả. Tên tham số của Apple đổi giữa hai
/// SDK: `sampling:` ở SDK macOS 26 (máy dựng bản phát hành), `samplingMode:` từ SDK macOS 27 (đi cùng Swift 6.4).
/// Viết thẳng một trong hai tên thì bản phát hành không dựng được (đã gặp ở 2.1.0, 2026-11-26).
@available(macOS 26.0, *)
extension GenerationOptions {
    static func greedy(maxTokens: Int) -> GenerationOptions {
        #if compiler(>=6.4)
        return GenerationOptions(samplingMode: .greedy, maximumResponseTokens: maxTokens)
        #else
        return GenerationOptions(sampling: .greedy, maximumResponseTokens: maxTokens)
        #endif
    }
}

/// THỬ NGHIỆM (2026-11-25): sửa cả câu bằng mô hình ngôn ngữ chạy trên máy của macOS (Foundation Models, từ macOS 26,
/// cần bật Apple Intelligence). Chỉ là lệnh đo chất lượng và tốc độ trong `vnkey-tool`; ứng dụng chưa dùng. Không có
/// gì rời khỏi máy.
@available(macOS 26.0, *)
enum SentenceFixer {
    /// Câu mẫu (câu gõ, câu đúng): các câu viết tay trong `Eval/handwritten.tsv`. Đo đầy đủ thì dùng `vnkey-tool eval`.
    static var samples: [(String, String)] { (EvalSet.load(EvalSet.handwritten) ?? []).map { ($0.typed, $0.want) } }

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
                        to: task.prompt(for: text), options: .greedy(maxTokens: 400))
                    print(String(format: "%5.0f ms  %@\n          -> %@", Date().timeIntervalSince(start) * 1000, text, task.clean(answer.content, original: text)))
                } catch {
                    print("LỖI  \(text): \(error)")
                }
            }
            done.signal()
        }
        done.wait()
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
                        to: text, options: .greedy(maxTokens: 200))
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
