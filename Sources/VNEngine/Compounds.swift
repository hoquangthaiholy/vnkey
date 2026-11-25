import Foundation

/// Từ điển từ tiếng Việt: từ ghép hai âm tiết ("bánh chưng", "giữ gìn") và từ đơn hiếm mà bảng tần suất
/// `CommonWords` không có ("quẫy"). Nguồn và giấy phép ở đầu `CompoundsData.swift`. Bộ soát lỗi dùng nó để:
/// - không gạch chân âm tiết hiếm nhưng có thật, đứng một mình hoặc trong một từ ghép với từ bên cạnh;
/// - xếp đề nghị: ứng viên tạo thành từ ghép với từ bên cạnh được cộng điểm;
/// - bắt lỗi chính tả trùng một âm tiết có thật ("bánh trưng" -> chưng).
///
/// Âm tiết được đánh số: trước hết theo thứ tự của `CommonWords.keys`, rồi tới `words` (từ đơn có trong từ điển mà
/// bảng tần suất không có), rồi `parts` (âm tiết chỉ gặp trong từ ghép). Khoá là dạng chuẩn của `Charset.syllableKey`.
/// Khối nhị phân (base64 trong mã nguồn): với mỗi âm tiết đứng trước, một số lượng n rồi n khoảng cách chỉ số của
/// âm tiết đứng sau (đã xếp tăng dần). Số nguyên viết kiểu LEB128.
public enum Compounds {
    private static let wordKeys: [String] = words.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    private static let partKeys: [String] = parts.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)

    private static let index: [String: Int] = {
        var out: [String: Int] = [:]
        out.reserveCapacity(CommonWords.keys.count + wordKeys.count + partKeys.count)
        for (i, k) in (CommonWords.keys + wordKeys + partKeys).enumerated() where out[k] == nil { out[k] = i }
        return out
    }()

    private static let blob: [UInt8] = [UInt8](Data(base64Encoded: data, options: .ignoreUnknownCharacters) ?? Data())

    /// Vị trí bắt đầu nhóm của từng âm tiết đứng trước trong `blob`. Rỗng nếu dữ liệu không khớp bảng âm tiết.
    private static let offsets: [Int] = {
        let total = CommonWords.keys.count + wordKeys.count + partKeys.count
        guard baseCount == CommonWords.keys.count else { return [] }
        var out: [Int] = []
        out.reserveCapacity(total)
        var p = 0
        for _ in 0..<total {
            guard p < blob.count else { return [] }
            out.append(p)
            let n = varint(&p)
            for _ in 0..<n { _ = varint(&p) }
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

    /// "`first` `second`" có phải một từ ghép trong từ điển không. Không phân biệt hoa/thường và cách đặt dấu thanh.
    public static func contains(_ first: String, _ second: String) -> Bool {
        guard let fk = Charset.syllableKey(first), let sk = Charset.syllableKey(second), let a = index[fk], let b = index[sk],
            a < offsets.count
        else { return false }
        var p = offsets[a]
        let n = varint(&p)
        var at = -1
        for _ in 0..<n {
            at += varint(&p) + 1
            if at == b { return true }
            if at > b { return false }
        }
        return false
    }

    /// `word` là một từ đơn có trong từ điển mà bảng tần suất không có (từ hiếm nhưng có thật).
    public static func isRareWord(_ word: String) -> Bool {
        guard let k = Charset.syllableKey(word), let i = index[k] else { return false }
        return i >= CommonWords.keys.count && i < CommonWords.keys.count + wordKeys.count
    }

    // MARK: - Sinh bảng (dùng bởi `vnkey-tool compounds`)

    /// Dựng dữ liệu từ một danh sách từ (mỗi dòng một từ hoặc cụm từ). Chỉ lấy mục một và hai âm tiết mà mọi âm tiết
    /// đều đúng chính tả tiếng Việt.
    public static func encode(list: String) -> (base: Int, words: [String], parts: [String], base64: String, compounds: Int) {
        var base: [String: Int] = [:]
        for (i, k) in CommonWords.keys.enumerated() { base[k] = i }
        var singles = Set<String>(), pairs: [(String, String)] = []
        for line in list.split(whereSeparator: \.isNewline) {
            let keys = line.split(separator: " ").map { Charset.syllableKey(String($0)) }
            if keys.count == 1, let k = keys[0] {
                if base[k] == nil { singles.insert(k) }
            } else if keys.count == 2, let a = keys[0], let b = keys[1] {
                pairs.append((a, b))
            }
        }
        let words = singles.sorted()
        var index = base
        for (i, k) in words.enumerated() { index[k] = base.count + i }
        let parts = Set(pairs.flatMap { [$0.0, $0.1] }).filter { index[$0] == nil }.sorted()
        for (i, k) in parts.enumerated() { index[k] = base.count + words.count + i }
        var groups = [Set<Int>](repeating: [], count: index.count)
        for (a, b) in pairs { groups[index[a]!].insert(index[b]!) }
        var bytes: [UInt8] = []
        func put(_ value: Int) {
            var v = value
            repeat {
                let b = UInt8(v & 0x7f)
                v >>= 7
                bytes.append(v > 0 ? b | 0x80 : b)
            } while v > 0
        }
        var count = 0
        for g in groups {
            put(g.count)
            var last = -1
            for b in g.sorted() {
                put(b - last - 1)
                last = b
                count += 1
            }
        }
        return (base.count, words, parts, Data(bytes).base64EncodedString(), count)
    }
}
