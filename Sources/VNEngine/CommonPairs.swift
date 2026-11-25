import Foundation

/// Độ hay đi liền nhau của hai âm tiết tiếng Việt ("hôm nay" 13.629 lần, "hôm này" 100 lần), đếm trên cùng kho
/// phụ đề với `CommonWords` (nguồn và giấy phép ở đầu `CommonPairsData.swift`). Dùng khi đoán từ gõ thiếu dấu:
/// từ đứng trước là bằng chứng mạnh nhất để chọn giữa các ứng viên ("tiếng viêt" -> việt, "bài viêt" -> viết), và
/// để biết một ứng viên hiếm có hợp chỗ này không ("nhiệt dới" -> đới, còn "việc dới" thì giữ nguyên).
///
/// Bảng chỉ có cặp mà cả hai âm tiết đều nằm trong `CommonWords`, xuất hiện từ `floor` lần trở lên. Dữ liệu là một
/// khối nhị phân (base64 trong mã nguồn): với mỗi âm tiết đứng trước, theo thứ tự của `CommonWords.keys`, một số
/// lượng n rồi n mục (khoảng cách chỉ số của âm tiết đứng sau, số lần đã nén). Số nguyên viết kiểu LEB128; số lần
/// nén thành một byte q = 12 × log2(số lần), sai lệch dưới 3%.
public enum CommonPairs {
    private static let index: [String: Int] = {
        var out: [String: Int] = [:]
        out.reserveCapacity(CommonWords.keys.count)
        for (i, k) in CommonWords.keys.enumerated() { out[k] = i }
        return out
    }()

    private static let blob: [UInt8] = [UInt8](Data(base64Encoded: data, options: .ignoreUnknownCharacters) ?? Data())

    /// Vị trí bắt đầu nhóm của từng âm tiết đứng trước trong `blob`. Rỗng nếu dữ liệu không khớp bảng âm tiết.
    private static let offsets: [Int] = {
        guard syllableCount == CommonWords.keys.count else { return [] }
        var out: [Int] = []
        out.reserveCapacity(syllableCount)
        var p = 0
        for _ in 0..<syllableCount {
            guard p < blob.count else { return [] }
            out.append(p)
            let n = varint(&p)
            for _ in 0..<n {
                _ = varint(&p)
                p += 1
            }
        }
        return out
    }()

    private static func varint(_ p: inout Int) -> Int {
        var value = 0, shift = 0
        while p < blob.count {
            let b = Int(blob[p])
            p += 1
            value |= (b & 0x7f) << shift
            if b < 0x80 { break }
            shift += 7
        }
        return value
    }

    static func quantize(_ count: Int) -> UInt8 { UInt8(max(1, min(255, Int((12 * log2(Double(count))).rounded())))) }
    static func expand(_ q: UInt8) -> Int { Int(pow(2, Double(q) / 12).rounded()) }

    /// Số lần (xấp xỉ) `word` đứng ngay sau `prev` trong kho ngữ liệu; 0 nếu cặp đó không có trong bảng. Không phân
    /// biệt hoa/thường và cách đặt dấu thanh.
    static func count(_ word: String, after prev: String) -> Int {
        guard let pk = Charset.syllableKey(prev), let wk = Charset.syllableKey(word), let a = index[pk], let b = index[wk],
            a < offsets.count
        else { return 0 }
        var p = offsets[a]
        let n = varint(&p)
        var at = -1
        for _ in 0..<n {
            at += varint(&p) + 1
            guard p < blob.count else { return 0 }
            if at == b { return expand(blob[p]) }
            if at > b { return 0 }
            p += 1
        }
        return 0
    }

    // MARK: - Sinh bảng (dùng bởi `vnkey-tool pairs`)

    /// Đếm các cặp âm tiết kề nhau trong `text` (mỗi dòng một câu) và nén thành khối dữ liệu base64. Hai âm tiết là
    /// một cặp khi chỉ cách nhau khoảng trắng: dấu câu, chữ số và xuống dòng đều cắt mạch.
    public static func encode(text: String, floor: Int) -> (base64: String, pairs: Int, words: Int) {
        let size = CommonWords.keys.count
        var counts: [Int: Int] = [:]
        var cache: [String: Int] = [:]
        var word = String.UnicodeScalarView()
        var prev = -1, words = 0
        func endWord() {
            guard !word.isEmpty else { return }
            let w = String(word).lowercased()
            word.removeAll(keepingCapacity: true)
            words += 1
            let i: Int
            if let hit = cache[w] {
                i = hit
            } else {
                i = Charset.syllableKey(w).flatMap { index[$0] } ?? -1
                cache[w] = i
            }
            if i >= 0, prev >= 0 { counts[prev * size + i, default: 0] += 1 }
            prev = i
        }
        for s in text.unicodeScalars {
            if s.properties.isAlphabetic || s.properties.generalCategory == .nonspacingMark {
                word.append(s)
            } else if s == " " || s == "\t" {
                endWord()
            } else {
                endWord()
                prev = -1
            }
        }
        endWord()

        var groups = [[(Int, Int)]](repeating: [], count: size)
        var kept = 0
        for (key, n) in counts where n >= floor {
            groups[key / size].append((key % size, n))
            kept += 1
        }
        var out: [UInt8] = []
        func put(_ value: Int) {
            var v = value
            while v >= 0x80 {
                out.append(UInt8(v & 0x7f) | 0x80)
                v >>= 7
            }
            out.append(UInt8(v))
        }
        for g in groups {
            put(g.count)
            var at = -1
            for (i, n) in g.sorted(by: { $0.0 < $1.0 }) {
                put(i - at - 1)
                out.append(quantize(n))
                at = i
            }
        }
        return (Data(out).base64EncodedString(), kept, words)
    }
}
