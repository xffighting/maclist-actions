import AppKit
import MacListCore

private final class AttachedSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CommandSearchField: NSSearchField {
    var commandHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if commandHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

final class SearchPanelController: NSWindowController,
    NSSearchFieldDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate {

    private let provider: SpotlightProvider
    private let dialogBridge: FileDialogBridge

    private let searchField = CommandSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(labelWithString: "↩ 选择  ·  ↑↓ 移动  ·  Esc 收起")
    private var expandedConstraints: [NSLayoutConstraint] = []

    private var dialogSession: FileDialogSession?
    private var observedDialog: ObservedDialog?
    private var interactionState = DialogInteractionState()
    private var baseRecords: [FileRecord] = []
    private var displayedRecords: [FileRecord] = []
    private var queryGeneration = UUID()
    private var isExpanded = false
    private var isSuppressed = false
    private var isSubmitting = false
    private var selectionOperation: FileDialogSelectionOperation?

    init(provider: SpotlightProvider, dialogBridge: FileDialogBridge) {
        self.provider = provider
        self.dialogBridge = dialogBridge

        let panel = AttachedSearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 62),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "MacList"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear

        super.init(window: panel)
        buildInterface()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func preloadRecentFiles() {
        loadRecords(for: "", showLoadingState: false)
    }

    func attach(to session: FileDialogSession, dialog: ObservedDialog) {
        let isNewDialog = interactionState.attach(dialogID: dialog.id)
        dialogSession = session
        observedDialog = dialog

        if isNewDialog {
            selectionOperation?.cancel()
            selectionOperation = nil
            isSuppressed = false
            isSubmitting = false
            searchField.stringValue = ""
            searchField.placeholderString = "在 \(session.hostApplicationName) 的上传窗口中搜索文件"
            applySearch()
            setExpanded(false)
        }

        guard !isSuppressed else { return }
        positionPanel()
        showAttachedPanel()
    }

    func updateAttachment(to session: FileDialogSession, dialog: ObservedDialog) {
        guard observedDialog?.id == dialog.id else {
            attach(to: session, dialog: dialog)
            return
        }
        dialogSession = session
        observedDialog = dialog
        guard !isSuppressed else { return }
        positionPanel()
    }

    func detach() {
        interactionState.detach()
        queryGeneration = UUID()
        selectionOperation?.cancel()
        selectionOperation = nil
        window?.orderOut(nil)
        setExpanded(false)
        dialogSession = nil
        observedDialog = nil
        isSuppressed = false
        isSubmitting = false
        searchField.stringValue = ""
    }

    var isPanelKeyAndVisible: Bool {
        window?.isKeyWindow == true && window?.isVisible == true
    }

    private func showAttachedPanel() {
        guard let window,
              let session = dialogSession,
              isCurrentDialogContext(session, window: window) else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    private func isCurrentDialogContext(
        _ session: FileDialogSession,
        window: NSWindow
    ) -> Bool {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?
            .processIdentifier else {
            return false
        }
        return frontmostPID == session.hostPID
            || frontmostPID == session.dialogOwnerPID
            || (frontmostPID == ProcessInfo.processInfo.processIdentifier && window.isVisible)
    }

    private func positionPanel() {
        guard let window, let dialog = observedDialog else { return }
        let screen = bestScreen(for: dialog.frame) ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let frame = AttachedPanelLayout.frame(
            dialogFrame: dialog.frame,
            visibleScreenFrame: visibleFrame,
            expanded: isExpanded
        )
        window.setFrame(frame, display: true, animate: false)
    }

    private func bestScreen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, frame) < intersectionArea(rhs.frame, frame)
        }
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        if expanded {
            isExpanded = true
            positionPanel()
            NSLayoutConstraint.activate(expandedConstraints)
            scrollView.isHidden = false
            statusLabel.isHidden = false
            instructionLabel.isHidden = false
        } else {
            scrollView.isHidden = true
            statusLabel.isHidden = true
            instructionLabel.isHidden = true
            NSLayoutConstraint.deactivate(expandedConstraints)
            isExpanded = false
            positionPanel()
        }
    }

    private func suppressForCurrentDialog() {
        isSuppressed = true
        window?.orderOut(nil)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let effect = NSVisualEffectView()
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        contentView.addSubview(effect)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索要上传的文件"
        searchField.controlSize = .large
        searchField.delegate = self
        searchField.commandHandler = { [weak self] event in
            self?.handleSearchKey(event) ?? false
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.isHidden = true

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 52
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(submitSelected)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isHidden = true

        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.textColor = .tertiaryLabelColor
        instructionLabel.font = .systemFont(ofSize: 11)
        instructionLabel.alignment = .right
        instructionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        instructionLabel.isHidden = true

        [searchField, scrollView, statusLabel, instructionLabel].forEach(effect.addSubview)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            effect.topAnchor.constraint(equalTo: contentView.topAnchor),
            effect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            searchField.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: effect.topAnchor, constant: 11),
            searchField.heightAnchor.constraint(equalToConstant: 40)
        ])

        expandedConstraints = [
            scrollView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: instructionLabel.leadingAnchor, constant: -10),

            instructionLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            instructionLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor)
        ]
    }

    func controlTextDidChange(_ obj: Notification) {
        let hasQuery = !searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        setExpanded(hasQuery)
        applySearch()
        if hasQuery {
            scheduleSpotlightQuery()
        }
    }

    private func applySearch() {
        displayedRecords = SearchEngine.search(
            searchField.stringValue,
            in: baseRecords,
            limit: 12
        )
        tableView.reloadData()
        if !displayedRecords.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        guard dialogSession != nil, isExpanded, !isSubmitting else { return }
        statusLabel.stringValue = displayedRecords.isEmpty
            ? "没有匹配文件，正在继续查询 Spotlight…"
            : "\(displayedRecords.count) 个匹配 · 只读取文件名、路径和时间"
    }

    private func scheduleSpotlightQuery() {
        let generation = UUID()
        queryGeneration = generation
        let query = searchField.stringValue

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.queryGeneration == generation else { return }
            self.loadRecords(for: query, showLoadingState: true, generation: generation)
        }
    }

    private func loadRecords(
        for query: String,
        showLoadingState: Bool,
        generation: UUID? = nil
    ) {
        if showLoadingState, dialogSession != nil, isExpanded {
            statusLabel.stringValue = "正在查询 Spotlight…"
        }
        let provider = self.provider

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return try provider.recentFiles()
                }
                return try provider.matchingFiles(query)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let generation, self.queryGeneration != generation { return }
                switch result {
                case let .success(records):
                    self.merge(records)
                    self.applySearch()
                case let .failure(error):
                    if self.dialogSession != nil, self.isExpanded {
                        self.statusLabel.stringValue = error.localizedDescription
                    }
                }
            }
        }
    }

    private func merge(_ records: [FileRecord]) {
        var byPath = Dictionary(uniqueKeysWithValues: baseRecords.map { ($0.path, $0) })
        for record in records {
            if let current = byPath[record.path], current.lastUsedAt >= record.lastUsedAt {
                continue
            }
            byPath[record.path] = record
        }
        baseRecords = Array(byPath.values)
    }

    private func handleSearchKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125:
            moveSelection(by: 1)
            return true
        case 126:
            moveSelection(by: -1)
            return true
        case 36, 76:
            submitSelected()
            return true
        case 53:
            suppressForCurrentDialog()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by offset: Int) {
        guard !displayedRecords.isEmpty else { return }
        let current = max(tableView.selectedRow, 0)
        let next = min(max(current + offset, 0), displayedRecords.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private var selectedRecord: FileRecord? {
        guard tableView.selectedRow >= 0,
              tableView.selectedRow < displayedRecords.count else {
            return nil
        }
        return displayedRecords[tableView.selectedRow]
    }

    @objc private func submitSelected() {
        guard !isSubmitting,
              let session = dialogSession,
              let interactionToken = interactionState.token,
              let record = selectedRecord else {
            NSSound.beep()
            return
        }

        isSubmitting = true
        statusLabel.stringValue = "正在交给当前上传窗口…"
        window?.orderOut(nil)

        selectionOperation?.cancel()
        selectionOperation = dialogBridge.selectFile(
            record.url,
            in: session,
            mode: .selectOnly
        ) { [weak self] result in
            guard let self else { return }
            guard self.interactionState.isCurrent(interactionToken),
                  self.observedDialog?.id == interactionToken.dialogID,
                  self.dialogSession?.dialogOwnerPID == session.dialogOwnerPID else {
                return
            }
            self.isSubmitting = false
            switch result {
            case .success:
                self.searchField.stringValue = ""
            case let .failure(error):
                self.statusLabel.stringValue = error.localizedDescription
                self.setExpanded(true)
                if !self.isSuppressed {
                    self.showAttachedPanel()
                }
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedRecords.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("FileCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? FileCellView)
            ?? FileCellView(frame: .zero)
        cell.identifier = identifier
        cell.configure(with: displayedRecords[row])
        return cell
    }
}
