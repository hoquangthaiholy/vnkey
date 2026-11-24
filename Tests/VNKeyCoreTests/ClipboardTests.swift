import Foundation
import Testing

@testable import VNKeyCore

private func at(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + t) }
private func text(_ s: String, _ t: TimeInterval = 0, app: String? = nil) -> ClipItem {
    ClipItem(kind: ClipKind.classify(s), text: s, date: at(t), app: app)
}

@Suite struct Clipboard {
    @Test(arguments: [
        ("https://example.com/a?b=1", ClipKind.link), ("  http://example.com\n", .link),
        ("example.com", .text), ("xem https://example.com", .text), ("mailto:a@example.com", .text),
        ("https://", .text), ("", .text), ("/Users/a/b.txt", .text),
    ])
    func classify(s: String, kind: ClipKind) { #expect(ClipKind.classify(s) == kind) }

    @Test func sameContentSameID() {
        #expect(text("abc", 1).id == text("abc", 99, app: "x").id)
        #expect(text("abc").id != text("abd").id)
        #expect(ClipItem(kind: .file, text: "abc", date: at(0)).id != text("abc").id)
        #expect(text("abc").id.count == 32)
    }

    @Test func recopyMovesToTopAndKeepsPin() {
        var h = ClipHistory()
        h.add(text("một", 1)); h.add(text("hai", 2)); h.add(text("ba", 3))
        h.togglePin(text("một").id, now: at(4))
        h.add(text("một", 5))
        #expect(h.items.map(\.text) == ["một", "ba", "hai"])
        #expect(h.items[0].pinned && h.items[0].date == at(5))
    }

    @Test func limitDropsOldestButNeverPinned() {
        var h = ClipHistory(limit: 3)
        h.add(text("ghim", 0)); h.togglePin(text("ghim").id)
        for i in 1...5 { h.add(text("mục \(i)", Double(i))) }
        #expect(h.items.map(\.text) == ["mục 5", "mục 4", "mục 3", "ghim"])
        #expect(Set(h.takeRemoved()) == [text("mục 1").id, text("mục 2").id])
        #expect(h.takeRemoved().isEmpty)
    }

    @Test func removeAndClearReportSideFiles() {
        var h = ClipHistory()
        h.add(text("a", 1)); h.add(text("b", 2))
        h.remove(text("a").id)
        #expect(h.takeRemoved() == [text("a").id])
        h.clear()
        #expect(h.items.isEmpty && h.takeRemoved() == [text("b").id])
    }

    @Test func visibleShowsPinnedFirstAndFilters() {
        var h = ClipHistory()
        h.add(text("Tiếng Việt", 1)); h.add(text("hello", 2)); h.add(text("https://example.com/Đường", 3))
        h.togglePin(text("hello").id)
        #expect(h.visible().map(\.text) == ["hello", "https://example.com/Đường", "Tiếng Việt"])
        #expect(h.visible("viet").map(\.text) == ["Tiếng Việt"])
        #expect(h.visible("TIENG  viet").count == 1)
        #expect(h.visible("duong example").count == 1)
        #expect(h.visible("không có").isEmpty)
        #expect(h.visible("safari", extra: { $0.text == "hello" ? "Safari" : "" }).map(\.text) == ["hello"])
    }

    @Test func savesAndLoads() {
        var h = ClipHistory()
        h.add(text("a\nb", 1, app: "com.example")); h.add(text("https://example.com", 2))
        h.togglePin(text("a\nb").id, now: at(3))
        #expect(h.dirty)
        let back = ClipHistory(data: h.data())
        #expect(back?.items == h.items)
        #expect(back?.dirty == false)
        #expect(ClipHistory(data: Data("{}".utf8)) == nil)
    }

    @Test func titles() {
        #expect(text("  dòng một\n\n   dòng hai  ").title == "dòng một dòng hai")
        #expect(ClipItem(kind: .file, text: "/a/b/ảnh.png\n/c/d.txt", date: at(0)).title == "ảnh.png, d.txt")
        #expect(text("https://www.example.com/x").host == "example.com")
        #expect(text("abc").host == nil)
    }

    @Test func policy() {
        func ok(_ types: [String], app: String? = "com.example", secure: Bool = false) -> Bool {
            ClipPolicy.shouldCapture(types: types, app: app, excluded: ["com.secret"], secureInput: secure)
        }
        #expect(ok(["public.utf8-plain-text"]))
        #expect(ok(["public.utf8-plain-text"], app: nil))
        #expect(!ok(["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(!ok(["org.nspasteboard.TransientType"]))
        #expect(!ok(["public.utf8-plain-text", ClipPolicy.ownType]))
        #expect(!ok(["public.utf8-plain-text"], app: "com.secret"))
        #expect(!ok(["public.utf8-plain-text"], secure: true))
    }
}

/// Hai máy đồng bộ qua một "thư mục" giả: từ điển id → dữ liệu tệp.
@Suite struct ClipSyncs {
    final class Folder { var files: [String: Data] = [:] }

    struct Mac {
        let name: String
        let folder: Folder
        var history = ClipHistory()
        var known: Set<String> = []

        mutating func sync() {
            let remote = folder.files.values.compactMap { ClipSync.decode($0, device: name) }
            let plan = ClipSync.reconcile(local: history.items, remote: remote, known: known)
            for item in plan.upload { folder.files[item.id] = ClipSync.encode(item, device: name) }
            for id in plan.deleteRemote { folder.files[id] = nil }
            for item in plan.adopt { history.adopt(item) }
            for id in plan.deleteLocal { history.remove(id) }
            known = plan.known
        }
    }

    @Test func copiesTravelBothWays() {
        let f = Folder()
        var a = Mac(name: "A", folder: f), b = Mac(name: "B", folder: f)
        a.history.add(text("từ A", 1)); b.history.add(text("từ B", 2))
        a.sync(); b.sync(); a.sync()
        #expect(a.history.items.map(\.text) == ["từ B", "từ A"])
        #expect(b.history.items.map(\.text) == ["từ B", "từ A"])
        #expect(a.history.items.map(\.device) == ["B", nil])
        #expect(b.history.items.map(\.device) == [nil, "A"])
        // Lần sau không còn gì để làm.
        let again = ClipSync.reconcile(local: a.history.items, remote: f.files.values.compactMap { ClipSync.decode($0, device: "A") }, known: a.known)
        #expect(again.isEmpty)
    }

    @Test func deleteTravels() {
        let f = Folder()
        var a = Mac(name: "A", folder: f), b = Mac(name: "B", folder: f)
        a.history.add(text("xoá tôi", 1)); a.history.add(text("giữ tôi", 2))
        a.sync(); b.sync()
        b.history.remove(text("xoá tôi").id)
        b.sync(); a.sync()
        #expect(a.history.items.map(\.text) == ["giữ tôi"])
        #expect(f.files.count == 1)
    }

    @Test func pinTravelsAndNewerWins() {
        let f = Folder()
        var a = Mac(name: "A", folder: f), b = Mac(name: "B", folder: f)
        a.history.add(text("mục", 1))
        a.sync(); b.sync()
        b.history.togglePin(text("mục").id, now: at(5))
        b.sync(); a.sync()
        #expect(a.history.items[0].pinned)
        a.history.togglePin(text("mục").id, now: at(9))
        a.sync(); b.sync()
        #expect(!b.history.items[0].pinned)
    }

    @Test func sameTextOnBothMacsIsOneItem() {
        let f = Folder()
        var a = Mac(name: "A", folder: f), b = Mac(name: "B", folder: f)
        a.history.add(text("chung", 1)); b.history.add(text("chung", 7))
        a.sync(); b.sync(); a.sync()
        #expect(f.files.count == 1)
        #expect(a.history.items.count == 1 && a.history.items[0].date == at(7))
    }

    @Test func recopyAfterDeleteComesBack() {
        let f = Folder()
        var a = Mac(name: "A", folder: f), b = Mac(name: "B", folder: f)
        a.history.add(text("mục", 1)); a.sync(); b.sync()
        a.history.remove(text("mục").id); a.sync(); b.sync()
        #expect(b.history.items.isEmpty)
        a.history.add(text("mục", 9)); a.sync(); b.sync()
        #expect(b.history.items.map(\.text) == ["mục"])
    }

    @Test func itemsPushedOutByTheLimitLeaveTheFolder() {
        let f = Folder()
        var a = Mac(name: "A", folder: f, history: ClipHistory(limit: 2))
        for i in 1...2 { a.history.add(text("mục \(i)", Double(i))) }
        a.sync()
        a.history.add(text("mục 3", 3))
        a.sync()
        #expect(f.files.count == 2 && f.files[text("mục 1").id] == nil)
    }

    @Test func imagesFilesAndHugeTextStayLocal() {
        let f = Folder()
        var a = Mac(name: "A", folder: f)
        a.history.add(ClipItem(kind: .image, text: "", date: at(1), imageData: Data([1, 2, 3])))
        a.history.add(ClipItem(kind: .file, text: "/a/b.txt", date: at(2)))
        a.history.add(text(String(repeating: "x", count: ClipSync.maxBytes + 1), 3))
        a.history.add(text("nhỏ", 4))
        a.sync(); a.sync()
        #expect(f.files.count == 1)
        #expect(a.history.items.count == 4)
    }

    @Test func conflictCopiesAndBrokenFilesAreHarmless() {
        var old = text("mục", 1), new = text("mục", 1)
        old.modified = at(1); new.modified = at(5); new.pinned = true
        let plan = ClipSync.reconcile(local: [], remote: [old, new, old], known: [])
        #expect(plan.adopt == [new])
        #expect(ClipSync.decode(Data("rác".utf8), device: "A") == nil)
        // Tệp bị sửa tay cho id không khớp nội dung thì bỏ qua.
        var forged = text("thật"); forged.text = "giả"
        #expect(ClipSync.decode(ClipSync.encode(forged, device: "B"), device: "A") == nil)
    }
}
