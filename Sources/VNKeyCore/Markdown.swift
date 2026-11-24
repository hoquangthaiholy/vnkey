import Foundation

/// Dịch HTML trên clipboard (trình duyệt, Claude, Google Docs, Notion…) ngược về Markdown: đậm, nghiêng, gạch,
/// mã, liên kết, ảnh, tiêu đề, danh sách lồng nhau, trích dẫn, khối mã, bảng. Bộ đọc HTML ở đây dễ dãi có chủ ý:
/// HTML trên clipboard hiếm khi chuẩn, nên thẻ lạ thì chỉ lấy phần chữ bên trong.
public enum HTMLMarkdown {
    public static func convert(_ html: String) -> String {
        tidy(render(parse(html), Context()))
    }

    // MARK: - Đọc HTML thành cây

    final class Node {
        let tag: String  // "" = đoạn chữ
        var attrs: [String: String] = [:]
        var text = ""
        var children: [Node] = []
        init(tag: String) { self.tag = tag }

        var plainText: String { tag.isEmpty ? text : children.map(\.plainText).joined() }

        func style(_ name: String) -> String? {
            guard let style = attrs["style"]?.lowercased() else { return nil }
            for part in style.split(separator: ";") {
                let kv = part.split(separator: ":", maxSplits: 1)
                if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == name {
                    return kv[1].trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }
    }

    private static let void: Set<String> = ["br", "hr", "img", "meta", "link", "input", "col", "wbr", "source"]
    private static let skipped: Set<String> = ["script", "style", "head", "title", "template", "noscript"]

    static func parse(_ html: String) -> Node {
        let root = Node(tag: "root")
        var stack = [root]
        let s = Array(html)
        var i = 0
        func find(_ needle: String, from: Int) -> Int? {
            let n = Array(needle)
            guard !n.isEmpty, s.count >= n.count else { return nil }
            var j = from
            while j <= s.count - n.count {
                if s[j] == n[0], Array(s[j..<j + n.count]).elementsEqual(n, by: { $0.lowercased() == $1.lowercased() }) { return j }
                j += 1
            }
            return nil
        }
        func addText(_ raw: String) {
            guard !raw.isEmpty else { return }
            let node = Node(tag: "")
            node.text = decodeEntities(raw)
            stack[stack.count - 1].children.append(node)
        }
        while i < s.count {
            guard s[i] == "<" else {
                let end = s[i...].firstIndex(of: "<") ?? s.count
                addText(String(s[i..<end]))
                i = end
                continue
            }
            if s[i...].starts(with: "<!--") {
                i = (find("-->", from: i + 4) ?? s.count - 3) + 3
                continue
            }
            guard let close = s[i...].firstIndex(of: ">") else { addText(String(s[i...])); break }
            let inside = String(s[i + 1..<close])
            i = close + 1
            if inside.hasPrefix("!") || inside.hasPrefix("?") { continue }
            if inside.hasPrefix("/") {
                let name = inside.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
                if let at = stack.lastIndex(where: { $0.tag == name }), at > 0 { stack.removeSubrange(at...) }
                continue
            }
            let (name, attrs) = parseTag(inside)
            // Thẻ mở phải bắt đầu bằng chữ cái; "<" lẻ trong văn bản ("a < b") là chữ thường.
            guard let first = name.first, first.isLetter else { addText("<" + inside + ">"); continue }
            let node = Node(tag: name)
            node.attrs = attrs
            if skipped.contains(name) {
                i = (find("</" + name, from: i).flatMap { s[$0...].firstIndex(of: ">") } ?? s.count - 1) + 1
                continue
            }
            // <p> và <li> hay bị bỏ thẻ đóng: thẻ cùng loại mới mở thì đóng thẻ cũ.
            if name == "p" || name == "li", let at = stack.lastIndex(where: { $0.tag == name }), at > 0,
                !stack[at...].contains(where: { ["ul", "ol", "blockquote", "td", "th"].contains($0.tag) && $0 !== stack[at] })
            {
                stack.removeSubrange(at...)
            }
            stack[stack.count - 1].children.append(node)
            if !void.contains(name), !inside.hasSuffix("/") { stack.append(node) }
        }
        return root
    }

    private static func parseTag(_ inside: String) -> (String, [String: String]) {
        let c = Array(inside)
        var i = 0
        func skipSpace() { while i < c.count, c[i].isWhitespace { i += 1 } }
        var name = ""
        while i < c.count, !c[i].isWhitespace, c[i] != "/" { name.append(c[i]); i += 1 }
        var attrs: [String: String] = [:]
        while i < c.count {
            skipSpace()
            var key = ""
            while i < c.count, !c[i].isWhitespace, c[i] != "=", c[i] != "/" { key.append(c[i]); i += 1 }
            skipSpace()
            var value = ""
            if i < c.count, c[i] == "=" {
                i += 1
                skipSpace()
                if i < c.count, c[i] == "\"" || c[i] == "'" {
                    let quote = c[i]
                    i += 1
                    while i < c.count, c[i] != quote { value.append(c[i]); i += 1 }
                    i += 1
                } else {
                    while i < c.count, !c[i].isWhitespace { value.append(c[i]); i += 1 }
                }
            } else if key.isEmpty {
                i += 1
            }
            if !key.isEmpty { attrs[key.lowercased()] = decodeEntities(value) }
        }
        return (name.lowercased(), attrs)
    }

    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
        "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "copy": "©", "reg": "®", "trade": "™",
        "times": "×", "middot": "·", "bull": "•", "rarr": "→", "larr": "←",
    ]

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.firstIndex(of: ";"), after.distance(from: after.startIndex, to: semi) <= 10 {
                let name = after[..<semi]
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
                } else {
                    decoded = entities[String(name)]
                }
                if let decoded {
                    out += decoded
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        return out + rest
    }

    // MARK: - Viết cây thành Markdown

    private struct Context {
        var pre = false
        var bold = false, italic = false
    }

    private static func children(_ node: Node, _ ctx: Context) -> String {
        node.children.map { render($0, ctx) }.joined()
    }

    /// Bọc phần chữ bằng ký hiệu, đưa khoảng trắng đầu/cuối ra ngoài ("<b>chữ </b>" → "**chữ** ").
    private static func wrap(_ inner: String, _ mark: String) -> String {
        let core = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return inner }
        let lead = inner.prefix { $0.isWhitespace }, trail = inner.reversed().prefix { $0.isWhitespace }.reversed()
        return lead + mark + core + mark + String(trail)
    }

    private static func isBold(_ node: Node) -> Bool? {
        guard let w = node.style("font-weight") else { return nil }
        if let n = Int(w) { return n >= 600 }
        return w.hasPrefix("bold")
    }

    private static func render(_ node: Node, _ ctx: Context) -> String {
        var ctx = ctx
        if node.tag.isEmpty {
            if ctx.pre { return node.text }
            // Trong HTML mọi dãy khoảng trắng (kể cả xuống dòng) chỉ là một dấu cách.
            var out = "", space = false
            for ch in node.text {
                if ch.isWhitespace && ch != "\u{A0}" { space = true; continue }
                if space { out.append(" "); space = false }
                out.append(ch == "\u{A0}" ? " " : ch)
            }
            return space ? out + " " : out
        }
        switch node.tag {
        case "strong", "b", "span", "em", "i", "font":
            // Google Docs bọc cả đoạn trong <b style="font-weight:normal"> và đánh dấu đậm bằng <span style=…>.
            var bold = node.tag == "strong" || node.tag == "b"
            if let styled = isBold(node) { bold = styled }
            var italic = node.tag == "em" || node.tag == "i"
            if let fs = node.style("font-style") { italic = fs.hasPrefix("italic") || fs.hasPrefix("oblique") }
            let addBold = bold && !ctx.bold, addItalic = italic && !ctx.italic
            ctx.bold = ctx.bold || bold
            ctx.italic = ctx.italic || italic
            var inner = children(node, ctx)
            if addItalic { inner = wrap(inner, "*") }
            if addBold { inner = wrap(inner, "**") }
            return inner
        case "del", "s", "strike": return wrap(children(node, ctx), "~~")
        case "code", "kbd", "samp", "tt":
            if ctx.pre { return children(node, ctx) }
            let inner = node.plainText
            return inner.isEmpty ? "" : wrap(inner, inner.contains("`") ? "``" : "`")
        case "a":
            let inner = children(node, ctx)
            guard let href = node.attrs["href"], !href.isEmpty, !href.lowercased().hasPrefix("javascript:"),
                !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return inner }
            let label = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            let lead = inner.prefix { $0.isWhitespace }, trail = inner.reversed().prefix { $0.isWhitespace }.reversed()
            return lead + (label == href ? "<\(href)>" : "[\(label)](\(href))") + String(trail)
        case "img":
            guard let src = node.attrs["src"], !src.isEmpty, !src.hasPrefix("data:") else { return node.attrs["alt"] ?? "" }
            return "![\(node.attrs["alt"] ?? "")](\(src))"
        case "br": return ctx.pre ? "\n" : "  \n"
        case "hr": return "\n\n---\n\n"
        case "h1", "h2", "h3", "h4", "h5", "h6":
            ctx.bold = true  // tiêu đề vốn đậm: không thêm ** bên trong
            let level = Int(String(node.tag.last!)) ?? 1
            let inner = children(node, ctx).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            return inner.isEmpty ? "" : "\n\n" + String(repeating: "#", count: level) + " " + inner + "\n\n"
        case "pre":
            ctx.pre = true
            var lang = ""
            func findLang(_ n: Node) {
                if lang.isEmpty, let cls = n.attrs["class"] {
                    for c in cls.split(separator: " ") where c.hasPrefix("language-") || c.hasPrefix("lang-") {
                        lang = String(c[c.index(after: c.firstIndex(of: "-")!)...])
                    }
                }
                n.children.forEach(findLang)
            }
            findLang(node)
            var body = children(node, ctx)
            while body.hasSuffix("\n") { body.removeLast() }
            while body.hasPrefix("\n") { body.removeFirst() }
            return "\n\n```\(lang)\n\(body)\n```\n\n"
        case "blockquote":
            let inner = tidy(children(node, ctx))
            return inner.isEmpty ? "" : "\n\n" + inner.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n") + "\n\n"
        case "ul", "ol":
            var lines: [String] = []
            var number = Int(node.attrs["start"] ?? "") ?? 1
            for li in node.children where li.tag == "li" {
                let marker = node.tag == "ol" ? "\(number). " : "- "
                number += 1
                // Danh sách gọn: trong một mục không để dòng trống; dòng tiếp theo và danh sách con thụt vào.
                let body = tidy(children(li, ctx)).split(separator: "\n").map(String.init)
                let pad = String(repeating: " ", count: marker.count)
                for (k, line) in body.enumerated() { lines.append((k == 0 ? marker : pad) + line) }
                if body.isEmpty { lines.append(marker.trimmingCharacters(in: .whitespaces)) }
            }
            return lines.isEmpty ? children(node, ctx) : "\n\n" + lines.joined(separator: "\n") + "\n\n"
        case "table":
            var rows: [[String]] = []
            func collect(_ n: Node) {
                for child in n.children {
                    if child.tag == "tr" {
                        rows.append(
                            child.children.filter { $0.tag == "td" || $0.tag == "th" }.map {
                                tidy(children($0, ctx)).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|")
                            })
                    } else if child.tag != "table" {
                        collect(child)
                    }
                }
            }
            collect(node)
            rows.removeAll { $0.isEmpty }
            guard let width = rows.map(\.count).max(), width > 0 else { return children(node, ctx) }
            func line(_ cells: [String]) -> String {
                "| " + (cells + Array(repeating: "", count: width - cells.count)).joined(separator: " | ") + " |"
            }
            var out = [line(rows[0]), line(Array(repeating: "---", count: width))]
            out += rows.dropFirst().map(line)
            return "\n\n" + out.joined(separator: "\n") + "\n\n"
        case "p", "div", "section", "article", "header", "footer", "main", "aside", "figure", "figcaption", "dl", "dt", "dd", "tr", "li":
            return "\n\n" + children(node, ctx) + "\n\n"
        default:
            return children(node, ctx)
        }
    }

    /// Bỏ khoảng trắng thừa: không quá một dòng trống giữa hai khối, không dấu cách lẻ ở đầu/cuối dòng.
    /// Trong khối mã thì giữ nguyên từng dòng.
    private static func tidy(_ s: String) -> String {
        var out: [String] = []
        var fenced = false, blank = true
        for raw in s.split(separator: "\n", omittingEmptySubsequences: false) {
            if raw.hasPrefix("```") { fenced.toggle(); out.append(String(raw)); blank = false; continue }
            if fenced { out.append(String(raw)); continue }
            // Hai dấu cách cuối dòng là xuống dòng của Markdown (từ <br>): giữ lại.
            let hardBreak = raw.hasSuffix("  ") && !raw.allSatisfy(\.isWhitespace)
            var line = String(raw)
            while line.last?.isWhitespace == true { line.removeLast() }
            let indent = line.prefix { $0 == " " }
            let body = line.dropFirst(indent.count)
            // Giữ thụt đầu dòng của danh sách lồng nhau; dấu cách lẻ trước chữ thường thì bỏ.
            let listy = body.hasPrefix("- ") || body.hasPrefix("> ") || body.first?.isNumber == true || indent.count >= 2
            line = (listy ? String(indent) : "") + body
            if line.isEmpty {
                if !blank { out.append("") }
                blank = true
            } else {
                out.append(hardBreak ? line + "  " : line)
                blank = false
            }
        }
        while out.last?.isEmpty == true { out.removeLast() }
        if let last = out.last, last.hasSuffix("  ") { out[out.count - 1] = String(last.dropLast(2)) }
        return out.joined(separator: "\n")
    }
}
