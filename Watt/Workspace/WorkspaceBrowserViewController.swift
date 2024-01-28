//
//  WorkspaceBrowserViewController.swift
//  Watt
//
//  Created by David Albert on 1/9/24.
//

import Cocoa

class WorkspaceBrowserViewController: NSViewController {
    let workspace: Workspace

    @ViewLoading var outlineView: NSOutlineView
    @ViewLoading var dataSource: OutlineViewDiffableDataSource<[Dirent]>

    var task: Task<(), Never>?

    let filePromiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "NSFilePromiseProvider queue"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
        workspace.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func makeTableCellView(for column: NSTableColumn, isEditable: Bool) -> NSTableCellView {
        let view: NSTableCellView
        if let v = outlineView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView {
            view = v
        } else {
            view = NSTableCellView()
            view.identifier = column.identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false

            let textField = DirentTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.isEditable = isEditable
            textField.focusRingType = .none
            textField.lineBreakMode = .byTruncatingMiddle
            textField.cell?.sendsActionOnEndEditing = true

            textField.delegate = self

            textField.target = self
            textField.action = #selector(WorkspaceBrowserViewController.onSubmit(_:))

            view.addSubview(imageView)
            view.addSubview(textField)
            view.imageView = imageView
            view.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        }
        
        return view
    }

    override func loadView() {
        let outlineView = NSOutlineView()
        outlineView.headerView = nil

        let column = NSTableColumn(identifier: .init("Name"))
        column.title = "Name"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.autoresizesOutlineColumn = false

        let dataSource = OutlineViewDiffableDataSource<[Dirent]>(outlineView) { [weak self] outlineView, column, dirent in
            guard let self else {
                return NSView()
            }

            let view = makeTableCellView(for: column, isEditable: true)
            view.imageView!.image = dirent.icon
            view.textField!.stringValue = dirent.name

            return view
        }

        let workspace = workspace
        dataSource.loadChildren = { dirent in
            if dirent.isLoaded {
                return nil
            }

            do {
                try workspace.loadDirectory(url: dirent.url)
            } catch {
                print("dataSource.loadChildren: error while loading \(dirent.url): \(error)")
            }
            return OutlineViewSnapshot(workspace.children, children: \.children)
        }

        outlineView.setDraggingSourceOperationMask([.move, .copy, .generic], forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

        dataSource.onDrag = { dirent in
            WorkspacePasteboardWriter(dirent: dirent, delegate: self)
        }

        dataSource.onDrop(of: NSFilePromiseReceiver.self, operation: .copy, source: .remote) { [weak self] filePromiseReceiver, destination in
            Task {
                do {
                    let targetDirectoryURL = (destination.parent ?? workspace.root).url
                    try await workspace.receive(filesFrom: filePromiseReceiver, atDestination: targetDirectoryURL)
                } catch {
                    self?.presentErrorAsSheetWithFallback(error)
                }
            }
        } validator: { _, destination in
            destination.index != NSOutlineViewDropOnItemIndex
        }

        dataSource.onDrop(of: URL.self, operation: .copy, source: .remote, searchOptions: [.urlReadingFileURLsOnly: true]) { [weak self] url, destination in
            Task {
                do {
                    let srcURL = url
                    let targetDirectoryURL = (destination.parent ?? workspace.root).url
                    let dstURL = targetDirectoryURL.appendingPathComponent(srcURL.lastPathComponent)
                    try await workspace.copy(fileAt: srcURL, intoWorkspaceAt: dstURL)
                } catch {
                    self?.presentErrorAsSheetWithFallback(error)
                }
            }
        } validator: { _, destination in
            destination.index != NSOutlineViewDropOnItemIndex
        } preview: { [weak self] url in
            guard let self, let dirent = try? Dirent(for: url) else {
                return nil
            }

            // drag previews don't show text unless they're not editable
            let view = makeTableCellView(for: column, isEditable: false)
            view.imageView!.image = dirent.icon
            view.textField!.stringValue = dirent.name

            view.frame.size = NSSize(width: view.fittingSize.width, height: outlineView.rowHeight)
            view.layoutSubtreeIfNeeded()

            return DragPreview(frame: view.frame) {
                return view.draggingImageComponents
            }
        }

        dataSource.onDrop(of: ReferenceDirent.self, operations: [.move, .generic], source: .self) { [weak self] ref, destination in
            Task {
                do {
                    let oldURL = ref.url
                    let newURL = (destination.parent ?? workspace.root).url.appending(path: oldURL.lastPathComponent)
                    try await workspace.move(fileAt: oldURL, to: newURL)
                } catch {
                    self?.presentErrorAsSheetWithFallback(error)
                }
            }
        } validator: { _, destination in
            destination.index != NSOutlineViewDropOnItemIndex
        }

        dataSource.onDrop(of: ReferenceDirent.self, operation: .copy, source: .self) { [weak self] ref, destination in
            Task {
                do {
                    let srcURL = ref.url
                    let dstURL = (destination.parent ?? workspace.root).url.appending(path: srcURL.lastPathComponent)
                    try await workspace.copy(fileAt: srcURL, intoWorkspaceAt: dstURL)
                } catch {
                    self?.presentErrorAsSheetWithFallback(error)
                }
            }
        } validator: { _, destination in
            destination.index != NSOutlineViewDropOnItemIndex
        }

        self.outlineView = outlineView
        self.dataSource = dataSource

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = outlineView

        view = scrollView
    }

    override func viewDidLoad() {
        updateView()
    }

    override func viewWillAppear() {
        task = Task.detached(priority: .medium) { [weak self] in
            await self?.workspace.listen()
        }
    }

    override func viewWillDisappear() {
        task?.cancel()
    }

    func updateView() {
        let snapshot = OutlineViewSnapshot(workspace.children, children: \.children)
        dataSource.apply(snapshot, animatingDifferences: UserDefaults.standard.workspaceBrowserAnimationsEnabled && !dataSource.isEmpty)
    }

    @objc func onSubmit(_ sender: DirentTextField) {
        guard let dirent = dirent(for: sender) else {
            return
        }

        if dirent.nameWithExtension == sender.stringValue {
            sender.stringValue = dirent.name
            return
        }

        Task {
            do {
                let oldURL = dirent.url
                let newURL = dirent.url.deletingLastPathComponent().appending(path: sender.stringValue, directoryHint: dirent.directoryHint)

                // skip delegate notifications and call updateView() manually so we can eliminate a flicker when
                // updating the file name and image. This doesn't always work (I don't know why) but it works
                // most of the time.
                let newDirent = try await workspace.move(fileAt: oldURL, to: newURL, notifyDelegate: false)
                // newDirent should always be present because we're editing a row that already exists.
                sender.stringValue = newDirent!.name
                (sender.superview as! NSTableCellView).imageView!.image = newDirent!.icon
                updateView()

            } catch {
                sender.stringValue = dirent.name
                presentErrorAsSheetWithFallback(error)
            }
        }
    }

    @objc func onCancel(_ sender: DirentTextField) {
        guard let dirent = dirent(for: sender) else {
            return
        }

        sender.stringValue = dirent.name
    }

    func dirent(for textField: DirentTextField) -> Dirent? {
        dataSource[(textField.superview as? NSTableCellView)?.objectValue as! Dirent.ID]
    }
}

extension WorkspaceBrowserViewController: WorkspaceDelegate {
    func workspaceDidChange(_ workspace: Workspace) {
        updateView()
    }
}

extension WorkspaceBrowserViewController: DirentTextFieldDelegate {
    func textFieldDidBecomeFirstResponder(_ textField: DirentTextField) {
        guard let dirent = dirent(for: textField) else {
            return
        }

        let s = dirent.nameWithExtension
        textField.stringValue = s
        let range = s.startIndex..<(s.firstIndex(of: ".") ?? s.endIndex)
        textField.currentEditor()?.selectedRange = NSRange(range, in: s)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let textField = control as? DirentTextField else {
            return false
        }

        switch commandSelector {
        case #selector(cancelOperation):
            onCancel(textField)
        case #selector(insertTab):
            view.window?.makeFirstResponder(outlineView)
            return true
        case #selector(deleteWordBackward):
            return deleteFileExtensionOrWordBackward(textView)
        default:
            break
        }

        return false
    }

    func deleteFileExtensionOrWordBackward(_ textView: NSTextView) -> Bool {
        if textView.selectedRanges.count != 1 || textView.selectedRange.length > 0 {
            return false
        }

        let s = textView.string

        let caret = s.utf16Index(at: textView.selectedRange.location)
        let target = caret == s.startIndex ? s.startIndex : s.index(before: caret)
        let afterDot = s.range(of: ".", options: .backwards, range: s.startIndex..<target)?.upperBound ?? s.startIndex

        var i: String.Index?
        s.enumerateSubstrings(in: s.startIndex..<caret, options: [.byWords, .reverse, .substringNotRequired]) { _, range, _, stop in
            i = range.lowerBound
            stop = true
        }
        let wordStart = i ?? s.startIndex

        let range = max(wordStart, afterDot)..<caret
        let nsRange = NSRange(range, in: s)

        // don't copy textStorage
        _ = consume s

        if textView.shouldChangeText(in: nsRange, replacementString: "") {
            textView.textStorage?.replaceCharacters(in: nsRange, with: "")
            textView.didChangeText()
        }

        return true
    }
}

extension WorkspaceBrowserViewController: NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        let provider = filePromiseProvider as! WorkspacePasteboardWriter
        return provider.dirent.url.lastPathComponent
    }

    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo destinationURL: URL, completionHandler: @escaping (Error?) -> Void) {
        let provider = filePromiseProvider as! WorkspacePasteboardWriter

        do {
            let sourceURL = provider.dirent.url

            // The NSFilePromiseProviderDelegate docs are a bit unclear about whether we need
            // to coordinate writing to destinationURL, but when I tried doing that, I hit
            // what looked like a deadlock, so I assume we shouldn't.
            try NSFileCoordinator().coordinate(readingItemAt: sourceURL) { actualSourceURL in
                try FileManager.default.copyItem(at: actualSourceURL, to: destinationURL)
            }
            completionHandler(nil)
        } catch {
            Task { @MainActor in
                self.presentErrorAsSheetWithFallback(error)
            }
            completionHandler(error)
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        filePromiseQueue
    }
}
