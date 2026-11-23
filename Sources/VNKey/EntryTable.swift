import AppKit

/// Bảng soạn danh sách (gõ tắt, từ đã nhớ): sửa ngay trong ô, nút thêm/xoá, ô tìm kiếm. Dữ liệu là các
/// dòng chuỗi; cột "lựa chọn" lưu chỉ số của lựa chọn dưới dạng chuỗi ("0", "1"…).
final class EntryTable: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate {
    enum Column {
        /// `width` nil = chiếm phần còn lại.
        case text(title: String, placeholder: String, width: CGFloat?)
        case choice(title: String, options: [String], width: CGFloat)

        var title: String {
            switch self {
            case .text(let t, _, _), .choice(let t, _, _): return t
            }
        }
    }

    private final class Table: NSTableView {
        var onDelete: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 51 || event.keyCode == 117 { onDelete?() } else { super.keyDown(with: event) }
        }
    }

    /// Đặt vào trang Cài đặt.
    let view = NSStackView()
    private let table = Table()
    private let scroll = NSScrollView()
    private let search = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private let buttons = NSSegmentedControl(
        images: [
            NSImage(systemSymbolName: "plus", accessibilityDescription: "Thêm")!,
            NSImage(systemSymbolName: "minus", accessibilityDescription: "Xoá")!,
        ], trackingMode: .momentary, target: nil, action: nil)

    private let columns: [Column]
    private let load: () -> [[String]]
    /// Lưu toàn bộ các dòng; trả về dòng trạng thái và có cần cảnh báo không.
    private let save: ([[String]]) -> (text: String, warning: Bool)
    private var rows: [[String]] = []
    /// Chỉ số trong `rows` của các dòng đang hiện (sau khi lọc).
    private var visible: [Int] = []
    private var editing = false
    /// Bảng chỉ để xem và xoá dòng: không sửa trong ô, không có nút thêm.
    private let readOnly: Bool
    /// Vị trí của nút xoá trong cụm nút (bảng chỉ-đọc chỉ có một nút).
    private var removeSegment: Int { readOnly ? 0 : 1 }

    init(
        columns: [Column], height: CGFloat, label: String, searchable: Bool, readOnly: Bool = false,
        load: @escaping () -> [[String]],
        save: @escaping ([[String]]) -> (text: String, warning: Bool)
    ) {
        self.columns = columns
        self.readOnly = readOnly
        self.load = load
        self.save = save
        super.init()

        for (i, c) in columns.enumerated() {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(i)"))
            col.title = c.title
            switch c {
            case .text(_, _, let width):
                if let width { col.width = width; col.minWidth = 60; col.resizingMask = .userResizingMask } else {
                    col.resizingMask = [.autoresizingMask, .userResizingMask]
                }
            case .choice(_, _, let width):
                col.width = width; col.minWidth = width; col.maxWidth = width; col.resizingMask = []
            }
            table.addTableColumn(col)
        }
        table.rowHeight = 24
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.onDelete = { [unowned self] in removeSelected() }
        table.setAccessibilityLabel(label)

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true

        buttons.target = self
        buttons.action = #selector(buttonPressed(_:))
        if readOnly {
            buttons.segmentCount = 1
            buttons.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: "Xoá"), forSegment: 0)
        } else {
            buttons.setToolTip("Thêm một dòng", forSegment: 0)
        }
        buttons.setToolTip("Xoá các dòng đang chọn (phím Delete)", forSegment: removeSegment)
        buttons.setEnabled(false, forSegment: removeSegment)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [buttons, status])
        bar.orientation = .horizontal
        bar.spacing = 10

        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 6
        if searchable {
            search.placeholderString = "Tìm"
            search.controlSize = .small
            search.delegate = self
            search.sendsSearchStringImmediately = true
            view.addArrangedSubview(search)
            search.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        }
        view.addArrangedSubview(scroll)
        view.addArrangedSubview(bar)
        scroll.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        bar.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        reload()
    }

    /// Nạp lại từ nơi lưu, trừ khi người dùng đang sửa dở một ô.
    func reload() {
        guard !editing else { return }
        rows = load()
        refilter()
        show(save(rows))
    }

    private func show(_ s: (text: String, warning: Bool)) {
        status.stringValue = s.text
        status.textColor = s.warning ? .systemOrange : .secondaryLabelColor
    }

    private func commit() { show(save(rows)) }

    private func refilter() {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            visible = Array(rows.indices)
        } else {
            visible = rows.indices.filter { i in
                rows[i].enumerated().contains { j, cell in
                    if case .text = columns[j] {
                        return cell.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    }
                    return false
                }
            }
        }
        table.reloadData()
        buttons.setEnabled(!table.selectedRowIndexes.isEmpty, forSegment: removeSegment)
    }

    // MARK: - Thêm / xoá

    @objc private func buttonPressed(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == removeSegment { removeSelected() } else { add() }
    }

    private func add() {
        table.window?.makeFirstResponder(table)  // chốt ô đang sửa dở (nếu có) trước khi thêm dòng
        search.stringValue = ""
        rows.append(columns.map { if case .choice = $0 { return "0" } else { return "" } })
        refilter()
        let row = visible.count - 1
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView, let f = cell.textField {
            table.window?.makeFirstResponder(f)
        }
    }

    private func removeSelected() {
        let gone = Set(table.selectedRowIndexes.map { visible[$0] })
        guard !gone.isEmpty else { return }
        table.window?.makeFirstResponder(table)
        rows = rows.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
        refilter()
        commit()
    }

    // MARK: - Bảng

    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        buttons.setEnabled(!table.selectedRowIndexes.isEmpty, forSegment: removeSegment)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let c = table.tableColumns.firstIndex(of: tableColumn) else { return nil }
        let value = rows[visible[row]][c]
        switch columns[c] {
        case .text(_, let placeholder, _):
            let cell =
                tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView ?? {
                    let cell = NSTableCellView()
                    cell.identifier = tableColumn.identifier
                    let f = NSTextField()
                    f.isBordered = false
                    f.drawsBackground = false
                    f.isEditable = !readOnly
                    f.lineBreakMode = .byTruncatingTail
                    f.cell?.usesSingleLineMode = true
                    f.placeholderString = placeholder
                    f.delegate = self
                    f.translatesAutoresizingMaskIntoConstraints = false
                    cell.addSubview(f)
                    cell.textField = f
                    NSLayoutConstraint.activate([
                        f.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                        f.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                        f.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    ])
                    return cell
                }()
            cell.textField?.stringValue = value
            return cell
        case .choice(_, let options, _):
            let pop =
                tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSPopUpButton ?? {
                    let p = NSPopUpButton(frame: .zero, pullsDown: false)
                    p.identifier = tableColumn.identifier
                    p.controlSize = .small
                    p.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                    p.isBordered = false
                    p.addItems(withTitles: options)
                    p.target = self
                    p.action = #selector(choiceChanged(_:))
                    return p
                }()
            pop.selectItem(at: Int(value) ?? 0)
            return pop
        }
    }

    @objc private func choiceChanged(_ sender: NSPopUpButton) {
        let row = table.row(for: sender), col = table.column(for: sender)
        guard row >= 0, col >= 0 else { return }
        rows[visible[row]][col] = String(sender.indexOfSelectedItem)
        commit()
    }

    // MARK: - Sửa trong ô

    func controlTextDidBeginEditing(_ obj: Notification) {
        if obj.object as? NSSearchField == nil { editing = true }
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === search { refilter() }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field !== search else { return }
        editing = false
        let row = table.row(for: field), col = table.column(for: field)
        guard row >= 0, col >= 0, row < visible.count else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        field.stringValue = text
        if rows[visible[row]][col] != text {
            rows[visible[row]][col] = text
            commit()
        }
    }
}
