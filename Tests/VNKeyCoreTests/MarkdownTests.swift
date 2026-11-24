import Testing

@testable import VNKeyCore

@Suite struct HTMLToMarkdown {
    @Test(arguments: [
        // Đúng dạng Claude và Chromium đưa lên clipboard khi chép một đoạn có chữ đậm.
        ("<meta charset='utf-8'><strong>Ba mục cũ hơn.</strong> Chúng được chép trước.", "**Ba mục cũ hơn.** Chúng được chép trước."),
        ("chữ <b>đậm</b>, <i>nghiêng</i>, <em>nhấn</em>, <del>gạch</del>, <code>mã</code>", "chữ **đậm**, *nghiêng*, *nhấn*, ~~gạch~~, `mã`"),
        ("<b>đậm </b>rồi thường", "**đậm** rồi thường"),
        ("<strong><em>cả hai</em></strong>", "***cả hai***"),
        ("<strong>ngoài <b>trong</b></strong>", "**ngoài trong**"),
        ("<a href=\"https://example.com/a?b=1&amp;c=2\">trang</a>", "[trang](https://example.com/a?b=1&c=2)"),
        ("<a href='https://example.com'>https://example.com</a>", "<https://example.com>"),
        ("<a href=\"javascript:void(0)\">nút</a> <a>trơn</a>", "nút trơn"),
        ("<img src=\"https://example.com/a.png\" alt=\"ảnh\">", "![ảnh](https://example.com/a.png)"),
        ("a &lt; b &amp;&amp; c &gt; d&nbsp;&#8594; &#x1EA1; &khonglaentity;", "a < b && c > d → ạ &khonglaentity;"),
        ("một\n   hai\t\tba", "một hai ba"),
        ("a < b và c", "a < b và c"),
        ("<code>a `b` c</code>", "``a `b` c``"),
        ("", ""),
    ])
    func inline(html: String, markdown: String) { #expect(HTMLMarkdown.convert(html) == markdown) }

    @Test func blocks() {
        let html = """
            <h1>Tiêu đề</h1>
            <p>Đoạn <strong>một</strong>.</p>
            <p>Đoạn hai<br>xuống dòng.</p>
            <h3>Mục <b>nhỏ</b></h3>
            <hr>
            <blockquote><p>Trích dẫn</p><p>hai đoạn</p></blockquote>
            """
        #expect(HTMLMarkdown.convert(html) == """
            # Tiêu đề

            Đoạn **một**.

            Đoạn hai\("  ")
            xuống dòng.

            ### Mục nhỏ

            ---

            > Trích dẫn
            >
            > hai đoạn
            """)
    }

    @Test func lists() {
        let html = """
            <ul>
              <li><strong>Một:</strong> đầu</li>
              <li>Hai
                <ol start="3"><li>ba</li><li>bốn <code>x</code></li></ol>
              </li>
              <li><p>Năm</p></li>
            </ul>
            """
        #expect(HTMLMarkdown.convert(html) == """
            - **Một:** đầu
            - Hai
              3. ba
              4. bốn `x`
            - Năm
            """)
    }

    @Test func codeBlockKeepsItsText() {
        let html = "<p>Chạy:</p><pre><code class=\"language-swift\">let a = 1\n\n\n  if a &lt; 2 { print(\"**x**\") }\n</code></pre><p>xong</p>"
        #expect(HTMLMarkdown.convert(html) == """
            Chạy:

            ```swift
            let a = 1


              if a < 2 { print("**x**") }
            ```

            xong
            """)
    }

    @Test func table() {
        let html = "<table><thead><tr><th>Việc</th><th>Lệnh</th></tr></thead><tbody><tr><td>Test</td><td><code>a|b</code></td></tr><tr><td>Một ô</td></tr></tbody></table>"
        #expect(HTMLMarkdown.convert(html) == """
            | Việc | Lệnh |
            | --- | --- |
            | Test | `a\\|b` |
            | Một ô |  |
            """)
    }

    /// Google Docs: cả đoạn nằm trong <b style="font-weight:normal">, chữ đậm/nghiêng đánh dấu bằng style của <span>.
    @Test func styledSpans() {
        let html = "<b style=\"font-weight:normal;\" id=\"docs-internal-guid-1\"><p><span style=\"font-weight:400;\">thường </span><span style=\"font-weight: 700; color: rgb(0,0,0)\">đậm</span><span style=\"font-style:italic\"> nghiêng</span></p></b>"
        #expect(HTMLMarkdown.convert(html) == "thường **đậm** *nghiêng*")
    }

    @Test func skipsWhatIsNotContent() {
        let html = "<html><head><title>bỏ</title><style>p { color: red }</style></head><body><!-- chú thích --><script>var a = '<p>';</script><p>giữ</p><unknown>lạ</unknown></body></html>"
        #expect(HTMLMarkdown.convert(html) == "giữ\n\nlạ")
    }

    @Test func survivesBrokenHTML() {
        #expect(HTMLMarkdown.convert("<p>một<p>hai</b></p></div><strong>ba") == "một\n\nhai\n\n**ba**")
        #expect(HTMLMarkdown.convert("<ul><li>a<li>b</ul>") == "- a\n- b")
        #expect(HTMLMarkdown.convert("chữ <") == "chữ <")
    }
}
