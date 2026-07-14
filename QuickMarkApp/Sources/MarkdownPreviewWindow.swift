import AppKit
import WebKit
import QuickMarkCore
import UniformTypeIdentifiers

/// A floating split-view window:
///   Left  → editable NSTextView with raw Markdown source
///   Right → WKWebView live preview (updates on every keystroke)
final class MarkdownPreviewWindowController: NSObject {
    static let shared = MarkdownPreviewWindowController()

    private var windows: [NSWindow] = []
    private weak var scratchpadWindow: NSWindow?

    func show(url: URL) {
        let resolvedURL = RecentMarkdownStore.shared.resolvedURL(for: url)
        let didStartAccessing = resolvedURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                resolvedURL.stopAccessingSecurityScopedResource()
            }
        }

        let markdown: String
        do {
            markdown = try String(contentsOf: resolvedURL, encoding: .utf8)
        } catch {
            RecentMarkdownStore.shared.remove(url)
            showOpenError(error, for: resolvedURL)
            return
        }

        let (window, splitVC) = createWindow()
        load(markdown: markdown, url: resolvedURL, in: window, splitVC: splitVC)
        window.makeKeyAndOrderFront(nil)
        positionWindowForFirstOpen(window)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showNewDocument() {
        let (window, splitVC) = createWindow()
        flashNewDocumentTitle(window)
        splitVC.loadNew()
        window.makeKeyAndOrderFront(nil)
        positionWindowForFirstOpen(window)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showScratchpad() {
        if let scratchpadWindow, scratchpadWindow.isVisible {
            scratchpadWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let (window, splitVC) = createWindow()
        let url = scratchpadURL()
        let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        window.title = "Scratchpad"
        splitVC.load(markdown: markdown, url: url)
        scratchpadWindow = window
        window.makeKeyAndOrderFront(nil)
        positionWindowForFirstOpen(window)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openMarkdownDocument(closing welcomeWindow: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Open Markdown File"
        panel.allowedContentTypes = QuickMarkMarkdownFiles.extensions.compactMap { .init(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.show(url: url)
            welcomeWindow?.close()
        }
    }

    private func createWindow() -> (NSWindow, SplitPreviewViewController) {
        let vc = SplitPreviewViewController()

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "PeekMark"
        win.contentViewController = vc
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        let toolbar = NSToolbar(identifier: "QuickMarkToolbar")
        toolbar.delegate = vc
        toolbar.displayMode = .iconAndLabel
        win.toolbar = toolbar

        windows.append(win)
        return (win, vc)
    }

    private func positionWindowForFirstOpen(_ window: NSWindow) {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else {
            window.center()
            return
        }

        let width = min(1280, visibleFrame.width * 0.82)
        let height = min(860, visibleFrame.height * 0.84)
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.midY - height / 2

        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func flashNewDocumentTitle(_ window: NSWindow) {
        window.title = "New Document"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard self?.windows.contains(where: { $0 === window }) == true else { return }
            window.title = "Untitled"
        }
    }

    private func load(markdown: String, url: URL, in window: NSWindow, splitVC: SplitPreviewViewController) {
        window.title = url.deletingPathExtension().lastPathComponent
        splitVC.load(markdown: markdown, url: url)
        RecentMarkdownStore.shared.add(url)
    }

    private func showOpenError(_ error: Error, for url: URL) {
        let alert = NSAlert(error: error)
        alert.messageText = "Unable to Open Markdown File"
        alert.informativeText = url.path
        alert.runModal()
    }

    private func scratchpadURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PeekMark", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Scratchpad.md")
    }
}

extension MarkdownPreviewWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === closingWindow }
    }
}

// MARK: - Split View Controller

final class SplitPreviewViewController: NSSplitViewController, NSToolbarDelegate {
    private let editorItem = NSSplitViewItem(viewController: EditorViewController())
    private let previewItem = NSSplitViewItem(viewController: PreviewWebViewController())

    private var editorVC: EditorViewController { editorItem.viewController as! EditorViewController }
    private var previewVC: PreviewWebViewController { previewItem.viewController as! PreviewWebViewController }

    private enum ViewMode {
        case both, editorOnly, previewOnly
        mutating func toggle() {
            switch self {
            case .both:        self = .editorOnly
            case .editorOnly:  self = .previewOnly
            case .previewOnly: self = .both
            }
        }
        var label: String {
            switch self {
            case .both:        return "Split"
            case .editorOnly:  return "Source"
            case .previewOnly: return "Preview"
            }
        }
        var icon: String {
            switch self {
            case .both:        return "rectangle.split.2x1"
            case .editorOnly:  return "doc.text"
            case .previewOnly: return "eye"
            }
        }
    }

    private var viewMode: ViewMode = .both
    private weak var toggleButtonRef: NSButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        splitView.wantsLayer = true
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        addSplitViewItem(editorItem)
        addSplitViewItem(previewItem)

        editorVC.onTextChange = { [weak self] markdown in
            self?.previewVC.render(markdown: markdown)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let w = self.splitView.bounds.width
            if w > 0 {
                self.splitView.setPosition(w * 0.40, ofDividerAt: 0)
            }
        }
    }

    func load(markdown: String, url: URL) {
        editorVC.setText(markdown)
        previewVC.sourceURL = url
        previewVC.baseURL = url.deletingLastPathComponent()
        previewVC.render(markdown: markdown, baseURL: url.deletingLastPathComponent())
        editorVC.setCurrentURL(url)
    }

    func loadNew() {
        editorVC.setText("")
        editorVC.setCurrentURL(nil)
        previewVC.sourceURL = nil
        previewVC.baseURL = nil
        previewVC.render(markdown: "")
        viewMode = .both
        editorItem.isCollapsed = false
        previewItem.isCollapsed = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let w = self.splitView.bounds.width
            if w > 0 { self.splitView.setPosition(w * 0.40, ofDividerAt: 0) }
        }
    }

    private var window: NSWindow? { view.window }

    @objc func saveCurrentFile(_ sender: Any?) {
        editorVC.saveFile()
    }

    @objc func copyHTML(_ sender: Any?) {
        let html = MarkdownRenderer.render(markdown: editorVC.markdownText, title: window?.title ?? "PeekMark")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .html)
        NSPasteboard.general.setString(html, forType: .string)
        flashTitle("✓ HTML Copied")
    }

    func exportDocument(using exporter: any DocumentExporting) {
        let panel = NSSavePanel()
        panel.title = exporter.format.displayName
        panel.nameFieldStringValue = "\(window?.title ?? "Untitled").\(exporter.format.filenameExtension)"
        if let contentType = UTType(filenameExtension: exporter.format.filenameExtension) {
            panel.allowedContentTypes = [contentType]
        }

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let destinationURL = panel.url, let self else { return }
            let sourceURL = editorVC.documentURL
            let purpose: RenderPurpose
            switch exporter.format.filenameExtension.lowercased() {
            case "pdf": purpose = .pdfExport
            case "docx": purpose = .docxExport
            default: purpose = .htmlExport
            }
            let context = RenderContext(
                sourceURL: sourceURL,
                title: window?.title ?? "PeekMark",
                purpose: purpose
            )
            let provider = QuickMarkExtensionRegistry.customizationProviders.first
            let markdown = editorVC.markdownText

            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let customization = try await provider?.customization(for: context) ?? .none
                    let html = MarkdownRenderer.render(
                        markdown: markdown,
                        title: context.title,
                        customization: customization
                    )
                    try await exporter.export(ExportRequest(
                        html: html,
                        context: context,
                        destinationURL: destinationURL
                    ))
                    flashTitle("✓ Exported")
                    NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                } catch {
                    let alert = NSAlert(error: error)
                    alert.messageText = "Unable to Export Document"
                    if let hostWindow = window ?? NSApp.keyWindow {
                        alert.beginSheetModal(for: hostWindow) { _ in }
                    } else {
                        alert.runModal()
                    }
                }
            }
        }
        if let hostWindow = window ?? NSApp.keyWindow {
            panel.beginSheetModal(for: hostWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    @objc func findInSource(_ sender: Any?) {
        editorVC.showFindPanel()
    }

    @objc func newDocument(_ sender: Any?) {
        MarkdownPreviewWindowController.shared.showNewDocument()
    }

    private func flashTitle(_ title: String) {
        guard let window else { return }
        let original = window.title
        window.title = title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak window] in
            window?.title = original
        }
    }

    @objc func toggleViewMode(_ sender: Any?) {
        viewMode.toggle()
        let w = splitView.bounds.width

        editorItem.isCollapsed  = false
        previewItem.isCollapsed = false
        splitView.layoutSubtreeIfNeeded()

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.3
        NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        switch viewMode {
        case .both:        splitView.animator().setPosition(w * 0.40, ofDividerAt: 0)
        case .editorOnly:  splitView.animator().setPosition(w - 2,    ofDividerAt: 0)
        case .previewOnly: splitView.animator().setPosition(2,         ofDividerAt: 0)
        }
        NSAnimationContext.endGrouping()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) { [weak self] in
            guard let self else { return }
            switch self.viewMode {
            case .both:       break
            case .editorOnly: self.previewItem.isCollapsed = true
            case .previewOnly: self.editorItem.isCollapsed  = true
            }
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            self.toggleButtonRef?.image = NSImage(
                systemSymbolName: self.viewMode.icon,
                accessibilityDescription: self.viewMode.label
            )?.withSymbolConfiguration(cfg)
        }
    }

    // MARK: NSToolbarDelegate

    private static let toolbarButtonSize = NSSize(width: 72, height: 28)

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("new"), NSToolbarItem.Identifier("save"), NSToolbarItem.Identifier("copyHTML"), NSToolbarItem.Identifier("toggle")]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("new"), NSToolbarItem.Identifier("save"), NSToolbarItem.Identifier("copyHTML"), NSToolbarItem.Identifier("toggle"), .space]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier.rawValue {
        case "new":
            return toolbarButton(
                identifier: itemIdentifier,
                label: "New",
                toolTip: "New document (⌘N)",
                systemImageName: "doc.badge.plus",
                action: #selector(newDocument(_:))
            )
        case "save":
            return toolbarButton(
                identifier: itemIdentifier,
                label: "Save",
                toolTip: "Save file (⌘S)",
                systemImageName: "square.and.arrow.down",
                action: #selector(saveCurrentFile(_:))
            )
        case "copyHTML":
            return toolbarButton(
                identifier: itemIdentifier,
                label: "Copy HTML",
                toolTip: "Copy rendered HTML",
                systemImageName: "doc.on.doc",
                action: #selector(copyHTML(_:))
            )
        case "toggle":
            let item = toolbarButton(
                identifier: itemIdentifier,
                label: "View",
                toolTip: "Toggle view (Split / Source / Preview)",
                systemImageName: viewMode.icon,
                action: #selector(toggleViewMode(_:))
            )
            toggleButtonRef = item.view as? NSButton
            return item
        default:
            return nil
        }
    }

    private func toolbarButton(
        identifier: NSToolbarItem.Identifier,
        label: String,
        toolTip: String,
        systemImageName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = toolTip

        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: label)?
            .withSymbolConfiguration(cfg) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.frame = NSRect(origin: .zero, size: Self.toolbarButtonSize)
        button.imagePosition = .imageOnly
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.toolbarButtonSize.width),
            button.heightAnchor.constraint(equalToConstant: Self.toolbarButtonSize.height)
        ])

        item.view = button
        return item
    }
}

// MARK: - Editor (left pane)

final class EditorViewController: NSViewController {
    var onTextChange: ((String) -> Void)?
    var markdownText: String { textView.string }
    var documentURL: URL? { currentURL }

    private var currentURL: URL?
    private var securityScopedURL: URL?
    private var scrollView: NSScrollView!
    private var textView: NSTextView!

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    override func loadView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.delegate = self
        textView.allowsUndo = true

        // Set colors for both light and dark mode
        textView.drawsBackground = true

        scrollView.documentView = textView
        view = scrollView
        view.frame = .zero
    }

    func setText(_ markdown: String) {
        textView.string = markdown
    }

    func setCurrentURL(_ url: URL?) {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        currentURL = url

        guard let url else { return }
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }
    }

    func showFindPanel() {
        let alert = NSAlert()
        alert.messageText = "Find in Source"
        alert.informativeText = "Enter text to find in the Markdown source."
        alert.addButton(withTitle: "Find")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        find(field.stringValue)
    }

    private func find(_ query: String) {
        let nsString = textView.string as NSString
        let selectedEnd = textView.selectedRange().upperBound
        var range = nsString.range(of: query, options: [.caseInsensitive], range: NSRange(location: selectedEnd, length: nsString.length - selectedEnd))
        if range.location == NSNotFound {
            range = nsString.range(of: query, options: [.caseInsensitive])
        }
        guard range.location != NSNotFound else { NSSound.beep(); return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        view.window?.makeFirstResponder(textView)
    }

    @objc func saveFile() {
        guard let url = currentURL else {
            saveAs()
            return
        }
        do {
            try textView.string.write(to: url, atomically: true, encoding: .utf8)
            if let win = view.window {
                let original = win.title
                win.title = "✓ Saved"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    win.title = original
                }
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "Untitled.md"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.setCurrentURL(url)
            do {
                try self.textView.string.write(to: url, atomically: true, encoding: .utf8)
                RecentMarkdownStore.shared.add(url)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}

extension EditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        onTextChange?(textView.string)
    }
}

// MARK: - Preview (right pane)

final class PreviewWebViewController: NSViewController, WKNavigationDelegate {
    var baseURL: URL?
    var sourceURL: URL?
    private var webView: WKWebView!
    private var renderTask: Task<Void, Never>?

    override func loadView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        view = webView
        view.frame = .zero
    }

    func render(markdown: String, baseURL: URL? = nil) {
        let resolvedBase = baseURL ?? self.baseURL
        let context = RenderContext(sourceURL: sourceURL, title: "Preview", purpose: .appPreview)
        let provider = QuickMarkExtensionRegistry.customizationProviders.first

        renderTask?.cancel()
        renderTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let customization: RenderCustomization
            if let provider {
                do {
                    customization = try await provider.customization(for: context)
                } catch {
                    customization = .none
                }
            } else {
                customization = .none
            }
            guard !Task.isCancelled, let self else { return }

            let html = MarkdownRenderer.render(
                markdown: markdown,
                title: context.title,
                customization: customization
            )
            webView.loadHTMLString(html, baseURL: resolvedBase)
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if Self.isLocalAnchor(navigationAction.request.url) {
                decisionHandler(.allow)
                return
            }
            if openLocalWikilink(navigationAction.request.url) {
                decisionHandler(.cancel)
                return
            }
            if UserDefaults.standard.bool(forKey: QuickMarkSettings.openPreviewLinksExternally),
               let url = navigationAction.request.url,
               Self.canOpenExternally(url) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        } else if Self.isAllowedPreviewURL(navigationAction.request.url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    private func openLocalWikilink(_ url: URL?) -> Bool {
        guard let target = MarkdownWikilinkResolver.target(from: url) else { return false }
        guard let directory = baseURL,
              let linkedURL = MarkdownWikilinkResolver.resolve(target, in: directory) else {
            NSSound.beep()
            return true
        }
        MarkdownPreviewWindowController.shared.show(url: linkedURL)
        return true
    }

    private static func isAllowedPreviewURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        guard let scheme = url.scheme?.lowercased() else { return true }
        return scheme == "file" || scheme == "about"
    }

    private static func isLocalAnchor(_ url: URL?) -> Bool {
        guard let url, url.fragment?.isEmpty == false else { return false }
        guard let scheme = url.scheme?.lowercased() else { return true }
        return scheme == "file" || scheme == "about"
    }

    private static func canOpenExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }
}
