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

private enum CandidateSearchPhase {
    case idle
    case loading
    case ready
    case failed(String)
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
    private let fileColumn = NSTableColumn(
        identifier: NSUserInterfaceItemIdentifier("file")
    )
    private let emptyStateLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(labelWithString: "↩ 选择  ·  ↑↓ 移动  ·  Esc 收起")
    private var expandedConstraints: [NSLayoutConstraint] = []

    private var dialogSession: FileDialogSession?
    private var observedDialog: ObservedDialog?
    private var interactionState = DialogInteractionState()
    private var baseRecords: [FileRecord] = []
    private var displayedRecords: [FileRecord] = []
    private var queryGeneration = UUID()
    private var queryCancellation: SpotlightQueryCancellation?
    private var lastHandledQuery = ""
    private var searchPhase: CandidateSearchPhase = .idle
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
            queryGeneration = UUID()
            queryCancellation?.cancel()
            queryCancellation = nil
            selectionOperation?.cancel()
            selectionOperation = nil
            isSuppressed = false
            isSubmitting = false
            searchField.stringValue = ""
            lastHandledQuery = ""
            searchPhase = .idle
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
        queryCancellation?.cancel()
        queryCancellation = nil
        selectionOperation?.cancel()
        selectionOperation = nil
        window?.orderOut(nil)
        setExpanded(false)
        dialogSession = nil
        observedDialog = nil
        isSuppressed = false
        isSubmitting = false
        searchField.stringValue = ""
        lastHandledQuery = ""
        searchPhase = .idle
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
        syncCandidateColumnWidth()
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
            NSLayoutConstraint.activate(expandedConstraints)
            scrollView.isHidden = false
            emptyStateLabel.isHidden = true
            statusLabel.isHidden = false
            instructionLabel.isHidden = false
            positionPanel()
        } else {
            scrollView.isHidden = true
            emptyStateLabel.isHidden = true
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
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.target = self
        searchField.action = #selector(searchFieldAction)
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
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.autoresizingMask = [.width]
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(submitSelected)
        fileColumn.minWidth = 1
        fileColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(fileColumn)
        scrollView.documentView = tableView

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.alignment = .center
        emptyStateLabel.font = .systemFont(ofSize: 13)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.isHidden = true

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

        [searchField, scrollView, emptyStateLabel, statusLabel, instructionLabel]
            .forEach(effect.addSubview)

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

            emptyStateLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 24),
            emptyStateLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -24),
            emptyStateLabel.topAnchor.constraint(equalTo: scrollView.topAnchor),
            emptyStateLabel.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: instructionLabel.leadingAnchor, constant: -10),

            instructionLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            instructionLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor)
        ]
    }

    func controlTextDidChange(_ obj: Notification) {
        handleQueryChange()
    }

    @objc private func searchFieldAction(_ sender: NSSearchField) {
        handleQueryChange()
    }

    private func handleQueryChange() {
        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != lastHandledQuery else { return }
        lastHandledQuery = query

        let hasQuery = !query.isEmpty
        searchPhase = hasQuery ? .loading : .idle
        setExpanded(hasQuery)
        applySearch()
        if hasQuery {
            scheduleSpotlightQuery()
        } else {
            queryGeneration = UUID()
            queryCancellation?.cancel()
            queryCancellation = nil
        }
    }

    private func applySearch() {
        let selectedPath = selectedRecord?.path
        displayedRecords = SearchEngine.search(
            searchField.stringValue,
            in: baseRecords,
            limit: 12
        )
        tableView.reloadData()
        tableView.noteNumberOfRowsChanged()
        syncCandidateColumnWidth()
        if let selectedPath,
           let selectedIndex = displayedRecords.firstIndex(where: { $0.path == selectedPath }) {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        } else if !displayedRecords.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        updateCandidatePresentation()
    }

    private func scheduleSpotlightQuery() {
        queryCancellation?.cancel()
        let cancellation = SpotlightQueryCancellation()
        queryCancellation = cancellation
        let generation = UUID()
        queryGeneration = generation
        let query = searchField.stringValue

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.queryGeneration == generation else { return }
            self.loadRecords(
                for: query,
                showLoadingState: true,
                generation: generation,
                cancellation: cancellation
            )
        }
    }

    private func loadRecords(
        for query: String,
        showLoadingState: Bool,
        generation: UUID? = nil,
        cancellation: SpotlightQueryCancellation? = nil
    ) {
        if showLoadingState, dialogSession != nil, isExpanded {
            searchPhase = .loading
            updateCandidatePresentation()
        }
        let provider = self.provider

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return try provider.recentFiles(cancellation: cancellation)
                }
                return try provider.matchingFiles(query, cancellation: cancellation)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let generation, self.queryGeneration != generation { return }
                if let cancellation, self.queryCancellation === cancellation {
                    self.queryCancellation = nil
                }
                switch result {
                case let .success(records):
                    if generation != nil {
                        self.searchPhase = .ready
                    }
                    self.merge(records)
                    self.applySearch()
                case let .failure(error):
                    if generation != nil {
                        self.searchPhase = .failed(error.localizedDescription)
                    }
                    self.applySearch()
                }
            }
        }
    }

    private func updateCandidatePresentation() {
        guard dialogSession != nil, isExpanded, !isSubmitting else {
            emptyStateLabel.isHidden = true
            return
        }

        if displayedRecords.isEmpty {
            scrollView.isHidden = true
            emptyStateLabel.isHidden = false
            switch searchPhase {
            case .idle:
                emptyStateLabel.stringValue = "输入文件名开始搜索"
                statusLabel.stringValue = ""
            case .loading:
                emptyStateLabel.stringValue = "正在搜索这台 Mac…"
                statusLabel.stringValue = "支持文件名片段和多关键词"
            case .ready:
                emptyStateLabel.stringValue = "没有找到匹配文件\n请尝试更短的文件名"
                statusLabel.stringValue = "Spotlight 已完成查询"
            case let .failed(message):
                emptyStateLabel.stringValue = "搜索暂时不可用\n请稍后重试"
                statusLabel.stringValue = message
            }
            return
        }

        scrollView.isHidden = false
        emptyStateLabel.isHidden = true
        switch searchPhase {
        case .loading:
            statusLabel.stringValue = "\(displayedRecords.count) 个匹配 · 正在补充结果…"
        case let .failed(message):
            statusLabel.stringValue = "\(displayedRecords.count) 个本地匹配 · \(message)"
        case .idle, .ready:
            statusLabel.stringValue = "\(displayedRecords.count) 个匹配 · 只读取文件名和路径"
        }
    }

    private func syncCandidateColumnWidth() {
        guard isExpanded, let contentView = window?.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let width = max(1, scrollView.contentSize.width)
        var tableFrame = tableView.frame
        tableFrame.size.width = width
        tableView.frame = tableFrame
        fileColumn.width = width
        tableView.sizeLastColumnToFit()
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
