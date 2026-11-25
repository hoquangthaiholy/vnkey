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

    /// Hỏi mô hình cho `sentence`. `done` chạy ở luồng chính với câu đã lọc, hoặc nil nếu không có gì để sửa hay mô
    /// hình không trả lời được.
    /// Việc dùng được trên máy này: có mô hình thì đủ cả; không thì chỉ còn sửa chính tả bằng thuật toán trên máy.
    static var tasks: [SentenceTask] { available ? SentenceTask.allCases : [.fix] }
    /// Đường dự phòng cho việc sửa chính tả khi máy không có mô hình (hoặc mô hình lỗi): `Proofreader.restore`, không
    /// cần Apple Intelligence. `Proofing` cấp.
    static var local: ((String) -> String)?

    /// `fresh`: người dùng bấm "thử lại": bỏ kết quả đã nhớ và để mô hình chọn từ ngẫu nhiên hơn, để ra câu khác.
    static func fix(_ sentence: String, task: SentenceTask = .fix, fresh: Bool = false, done: @escaping (String?) -> Void) {
        let key = task.rawValue + "\u{1}" + sentence
        if !fresh, let hit = cache[key] { return done(hit == sentence ? nil : hit) }
        if !available {
            // Không có mô hình: chỉ việc sửa chính tả làm được, bằng bảng cặp và từ ghép.
            let result = task == .fix ? local?(sentence) : nil
            Log.write("SENTENCE \(task.rawValue) \(sentence.utf16.count) ký tự: thuật toán trên máy, \(result == nil ? "không làm được" : result == sentence ? "không có gì để sửa" : "có đề nghị")")
            return done(result == sentence ? nil : result)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), available {
            let start = Date()
            Task.detached(priority: .userInitiated) {
                var fixed: String?
                var failure = ""
                do {
                    // Mỗi câu một phiên mới: câu trước không ảnh hưởng câu sau. Luôn chọn từ có xác suất cao nhất, để
                    // cùng một câu luôn cho cùng một đề nghị.
                    let session = LanguageModelSession(instructions: task.instructions(for: sentence))
                    let answer = try await session.respond(
                        to: task.prompt(for: sentence),
                        options: fresh
                            ? GenerationOptions(temperature: 0.9, maximumResponseTokens: 400)
                            : GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 400))
                    fixed = task.clean(answer.content, original: sentence)
                } catch {
                    failure = String(describing: type(of: error))
                }
                let ms = Date().timeIntervalSince(start) * 1000
                let result = fixed
                let note = failure
                await MainActor.run {
                    if let result {
                        if cache.count > 200 { cache.removeAll() }
                        cache[key] = result
                    }
                    Log.write(
                        String(format: "SENTENCE %@ %d ký tự, %.0f ms: ", task.rawValue, sentence.utf16.count, ms)
                            + (result == nil ? "mô hình lỗi (\(note))" : result == sentence ? "không có gì để sửa" : "có đề nghị"))
                    done(result == sentence ? nil : result)
                }
            }
            return
        }
        #endif
        done(nil)
    }
}
