import Foundation
import VNEngine
import VNKeyCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Sửa cả câu bằng mô hình ngôn ngữ chạy TRÊN MÁY của macOS (framework Foundation Models: macOS 26 trở lên, cần bật
/// Apple Intelligence). Không có gì rời khỏi máy. Kết quả của mô hình luôn đi qua `SentenceFilter.merge`: chỉ giữ chỗ
/// sửa dấu / sửa âm của từng từ; dấu câu, hoa thường và từ tiếng Anh theo câu người dùng đã gõ. VNKey không tự thay:
/// người dùng xem câu đề nghị trong bảng rồi mới chọn.
///
/// Đo 2026-11-25 trên M4: khoảng 0,3–0,4 giây mỗi câu sau lần đầu (lần đầu 2 giây vì nạp mô hình), sau lọc đúng
/// 19/20 câu mẫu (`vnkey-tool fix-sentence`). Nhật ký chỉ ghi độ dài và thời gian, không ghi câu.
enum SentenceFix {
    /// Máy này dùng được mô hình ngay bây giờ.
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    private static var cache: [String: String] = [:]
    private static var warmed = false

    /// Nạp mô hình trước (lần gọi đầu mất chừng 2 giây): gọi khi bảng đề nghị vừa mở.
    static func warm() {
        guard !warmed, available else { return }
        warmed = true
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            Task.detached(priority: .utility) { LanguageModelSession(instructions: SentenceFilter.instructions).prewarm() }
        }
        #endif
    }

    /// Hỏi mô hình cho `sentence`. `done` chạy ở luồng chính với câu mô hình đề nghị, hoặc nil nếu không có gì để sửa
    /// hay mô hình không trả lời được. Máy không có mô hình thì không có bảng AI (người dùng chốt 2026-11-26: không sửa
    /// cả câu bằng thuật toán nữa), nên hàm này chỉ trả nil.
    /// `fresh`: người dùng bấm "thử lại": bỏ kết quả đã nhớ và để mô hình chọn từ ngẫu nhiên hơn, để ra câu khác.
    static func fix(_ sentence: String, task: SentenceTask = .fix, fresh: Bool = false, done: @escaping (String?) -> Void) {
        let key = task.rawValue + "\u{1}" + sentence
        if !fresh, let hit = cache[key] { return done(hit == sentence ? nil : hit) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), available {
            let start = Date()
            Task.detached(priority: .userInitiated) {
                var fixed: String?
                var failure = ""
                var retried = false
                // Mỗi câu một phiên mới: câu trước không ảnh hưởng câu sau. Luôn chọn từ có xác suất cao nhất, để cùng
                // một câu luôn cho cùng một đề nghị.
                func ask(permissive: Bool) async throws -> String {
                    let model = permissive ? SystemLanguageModel(guardrails: .permissiveContentTransformations) : SystemLanguageModel.default
                    let session = LanguageModelSession(model: model, instructions: task.instructions(for: sentence))
                    let answer = try await session.respond(
                        to: task.prompt(for: sentence),
                        options: fresh
                            ? GenerationOptions(temperature: 0.9, maximumResponseTokens: 400)
                            : GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 400))
                    return task.clean(answer.content, original: sentence)
                }
                do {
                    fixed = try await ask(permissive: false)
                } catch let error as LanguageModelSession.GenerationError {
                    // Bộ lọc an toàn của mô hình từ chối cả câu vô hại (đo 2026-11-26: 30 trong 1.001 câu). Hỏi lại ở mức
                    // Apple dành cho việc BIẾN ĐỔI văn bản của chính người dùng; cả 30 câu đều được trả lời.
                    switch error {
                    case .guardrailViolation, .refusal:
                        retried = true
                        do { fixed = try await ask(permissive: true) } catch { failure = String(describing: type(of: error)) }
                    default: failure = String(describing: type(of: error))
                    }
                } catch {
                    failure = String(describing: type(of: error))
                }
                let ms = Date().timeIntervalSince(start) * 1000
                let result = fixed
                let again = retried
                let note = failure + (again ? ", đã hỏi lại" : "")
                await MainActor.run {
                    if let result {
                        if cache.count > 200 { cache.removeAll() }
                        cache[key] = result
                    }
                    Log.write(
                        String(format: "SENTENCE %@ %d ký tự, %.0f ms: ", task.rawValue, sentence.utf16.count, ms)
                            + (result == nil ? "mô hình lỗi (\(note))" : (result == sentence ? "không có gì để sửa" : "có đề nghị") + (again ? " (hỏi lại sau khi bị từ chối)" : "")))
                    done(result == sentence ? nil : result)
                }
            }
            return
        }
        #endif
        done(nil)
    }
}
