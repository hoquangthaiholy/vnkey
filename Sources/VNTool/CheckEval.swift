import Foundation
import VNEngine

// Đo bộ soát lỗi theo TỪ (`Proofreader.check`, thứ ứng dụng gạch chân) trên bộ câu `Eval/`: từ sai nào được gạch,
// từ đúng nào bị gạch nhầm, đề nghị đứng đầu có đúng không. Khác `eval` (đo việc sửa cả câu).

enum CheckEval {
    /// Loại của một từ sai trong câu gõ.
    enum Miss: String, CaseIterable {
        /// Chỉ thiếu dấu, viết không dấu hoàn toàn ("toi" cho "tôi"): bộ soát CỐ Ý không gạch riêng lẻ.
        case unmarked = "viết không dấu"
        /// Không phải tiếng Việt cũng không phải tiếng Anh ("viêt", "dới", "duojc").
        case nonWord = "chữ không có thật"
        /// Trùng một từ có thật ("sẽ" cho "sẻ", "hop" là từ tiếng Anh).
        case realWord = "trùng từ có thật"
    }

    struct Tally {
        var words = 0, wrong = 0, caught = 0, falseFlags = 0, top1 = 0, top3 = 0
        var sentences = 0, cleanSentences = 0, cleanUntouched = 0
    }

    static func run(cases: [EvalCase], lexicon: Lexicon?, english: Bool, examples: Int) {
        let reader = Proofreader()
        reader.lexicon = lexicon
        reader.checkEnglish = english

        var byKind: [String: Tally] = [:]
        var byMiss: [Miss: Tally] = [:]
        var byIssue: [String: (right: Int, wrong: Int)] = [:]
        var skipped = 0
        var times: [Double] = []
        var falseList: [String: Int] = [:]
        var missedList: [String: Int] = [:]
        var badTop: [String: Int] = [:]

        for c in cases {
            let typed = EvalSet.pieces(c.typed), want = EvalSet.pieces(c.want)
            let tw = typed.filter(\.word), ww = want.filter(\.word)
            guard tw.count == ww.count else { skipped += 1; continue }
            // Vị trí UTF-16 của từng từ trong câu gõ.
            var ranges: [Range<Int>] = []
            var at = 0
            for p in typed {
                let n = p.text.utf16.count
                if p.word { ranges.append(at..<(at + n)) }
                at += n
            }
            let start = DispatchTime.now().uptimeNanoseconds
            let issues = reader.check(c.typed)
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)

            var t = byKind[c.kind, default: Tally()]
            t.sentences += 1
            let clean = c.typed == c.want
            if clean {
                t.cleanSentences += 1
                if issues.isEmpty { t.cleanUntouched += 1 }
            }
            /// Câu gõ sau khi thay chỗ `issue` bằng đề nghị thứ `n`: các từ trong vùng đó có ra đúng không.
            func fixes(_ issue: ProofIssue, _ n: Int, _ covered: [Int]) -> Bool {
                guard n < issue.suggestions.count else { return false }
                let got = EvalSet.pieces(issue.suggestions[n]).filter(\.word).map { $0.text.lowercased() }
                return got == covered.map { ww[$0].text.lowercased() }
            }
            for i in tw.indices {
                let wrong = tw[i].text.lowercased() != ww[i].text.lowercased()
                let issue = issues.first { $0.range.overlaps(ranges[i]) }
                t.words += 1
                if wrong {
                    let lower = tw[i].text.lowercased()
                    let kind: Miss =
                        lower.allSatisfy(\.isASCII) && Charset.stripMarks(ww[i].text.lowercased()) == lower
                        ? .unmarked
                        : reader.isKnownWord(lower) || (lexicon?.isEnglish(lower) ?? false) ? .realWord : .nonWord
                    var m = byMiss[kind, default: Tally()]
                    t.wrong += 1
                    m.wrong += 1
                    if let issue {
                        let covered = tw.indices.filter { issue.range.overlaps(ranges[$0]) }
                        let first = fixes(issue, 0, covered)
                        let any = first || fixes(issue, 1, covered) || fixes(issue, 2, covered)
                        t.caught += 1
                        m.caught += 1
                        if first { t.top1 += 1; m.top1 += 1 }
                        if any { t.top3 += 1; m.top3 += 1 }
                        byIssue[issue.kind.rawValue, default: (0, 0)].right += 1
                        if !first, kind == .nonWord {
                            badTop["\(tw[i].text) → \(issue.suggestions.first ?? "?") (đúng: \(ww[i].text))", default: 0] += 1
                        }
                    } else if kind == .nonWord {
                        missedList["\(tw[i].text) (đúng: \(ww[i].text))", default: 0] += 1
                    }
                    byMiss[kind] = m
                } else if let issue {
                    // Từ đúng bị gạch. Cụm hai từ có một từ sai thật thì từ đúng đi kèm không tính là gạch nhầm.
                    let covered = tw.indices.filter { issue.range.overlaps(ranges[$0]) }
                    if covered.contains(where: { tw[$0].text.lowercased() != ww[$0].text.lowercased() }) { continue }
                    t.falseFlags += 1
                    byIssue[issue.kind.rawValue, default: (0, 0)].wrong += 1
                    falseList["\(tw[i].text) → \(issue.suggestions.first ?? "?") [\(issue.kind.rawValue)]", default: 0] += 1
                }
            }
            byKind[c.kind] = t
        }

        func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "   -  " : String(format: "%5.1f%%", 100 * Double(a) / Double(b)) }
        func pad(_ s: String, _ n: Int) -> String { s + String(repeating: " ", count: max(0, n - s.count)) }

        print("Soát lỗi theo từ (`Proofreader.check`\(english ? ", có soát tiếng Anh" : "")), \(cases.count - skipped) câu"
            + (skipped > 0 ? " (bỏ \(skipped) câu có số từ gõ khác số từ đúng)" : ""))
        print("\n\(pad("Loại câu", 16)) \(pad("câu", 5)) \(pad("từ sai", 7)) \(pad("gạch được", 10)) \(pad("đề nghị 1", 10)) \(pad("trong 3", 8)) gạch nhầm/1000 từ đúng   câu đúng không bị gạch")
        var total = Tally()
        for (kind, t) in byKind.sorted(by: { $0.key < $1.key }) {
            line(kind, t)
            total.words += t.words; total.wrong += t.wrong; total.caught += t.caught; total.falseFlags += t.falseFlags
            total.top1 += t.top1; total.top3 += t.top3; total.sentences += t.sentences
            total.cleanSentences += t.cleanSentences; total.cleanUntouched += t.cleanUntouched
        }
        line("TỔNG", total)
        func line(_ name: String, _ t: Tally) {
            let right = t.words - t.wrong
            let per = right == 0 ? "   -" : String(format: "%4.1f", 1000 * Double(t.falseFlags) / Double(right))
            print("\(pad(name, 16)) \(pad(String(t.sentences), 5)) \(pad(String(t.wrong), 7)) \(pad(pct(t.caught, t.wrong), 10)) \(pad(pct(t.top1, t.wrong), 10)) \(pad(pct(t.top3, t.wrong), 8)) \(pad("\(per) (\(t.falseFlags))", 24)) \(t.cleanSentences == 0 ? "-" : "\(pct(t.cleanUntouched, t.cleanSentences)) của \(t.cleanSentences)")")
        }

        print("\nTheo loại từ sai (\"đề nghị 1\" và \"trong 3\" tính trên TẤT CẢ từ sai của loại đó):")
        print("\(pad("Loại", 20)) \(pad("từ sai", 7)) \(pad("gạch được", 10)) \(pad("đề nghị 1", 10)) trong 3")
        for kind in Miss.allCases {
            let m = byMiss[kind, default: Tally()]
            print("\(pad(kind.rawValue, 20)) \(pad(String(m.wrong), 7)) \(pad(pct(m.caught, m.wrong), 10)) \(pad(pct(m.top1, m.wrong), 10)) \(pct(m.top3, m.wrong))")
        }

        print("\nTheo loại nét gạch: gạch trúng từ sai / gạch nhầm từ đúng")
        for (kind, n) in byIssue.sorted(by: { $0.value.right + $0.value.wrong > $1.value.right + $1.value.wrong }) {
            print("  \(pad(kind, 14)) \(n.right) / \(n.wrong)   (\(pct(n.right, n.right + n.wrong)) trúng)")
        }
        let flagged = total.caught + total.falseFlags
        print("\nTrong \(flagged) từ bị gạch, \(pct(total.caught, flagged)) là từ sai thật.")
        let sorted = times.sorted()
        if !sorted.isEmpty {
            print(String(format: "Thời gian mỗi câu: trung vị %.2f ms, p95 %.2f ms.", sorted[sorted.count / 2], sorted[min(sorted.count - 1, sorted.count * 95 / 100)]))
        }
        func show(_ title: String, _ list: [String: Int]) {
            guard examples > 0, !list.isEmpty else { return }
            print("\n\(title) (\(list.count) dạng, \(list.values.reduce(0, +)) lần):")
            for (k, n) in list.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(examples) { print("  \(n)× \(k)") }
        }
        show("Từ đúng bị gạch nhầm", falseList)
        show("Chữ không có thật bị bỏ sót", missedList)
        show("Chữ không có thật được gạch nhưng đề nghị đầu sai", badTop)
    }
}
