import SwiftUI
import Foundation
import AppKit
import Carbon
import QuickMarkCore

@main
struct QuickMarkApp: App {
    @NSApplicationDelegateAdaptor(QuickMarkAppDelegate.self) private var appDelegate
#if !APP_STORE
    @StateObject private var updater = UpdaterController()
#endif

    init() {
        QuickMarkSettings.registerDefaults()
        QuickMarkExtensionLoader.loadConfiguredModule()
        ScratchpadHotKeyManager.shared.start()
    }

    var body: some Scene {
        // Main window (shown on first launch or from menu bar "Open PeekMark")
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 300)
        .commands {
            QuickMarkFileCommands()
#if OFFICIAL_EXTENSIONS
            OfficialOptionalCommands()
#endif
            QuickMarkSaveCommands()
            CommandGroup(after: .pasteboard) {
                Button("Copy Rendered HTML") {
                    activeSplitPreviewViewController()?.copyHTML(nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Find in Source…") {
                    activeSplitPreviewViewController()?.findInSource(nil)
                }
                .keyboardShortcut("f")
            }
        }

        // Menu bar extra
        MenuBarExtra("PeekMark", systemImage: "doc.text.magnifyingglass") {
#if APP_STORE
            MenuBarView()
#else
            MenuBarView(updater: updater)
#endif
        }
        .menuBarExtraStyle(.menu)

        // Settings window (Cmd+,)
        Settings {
            SettingsView()
        }
    }
}

struct QuickMarkSaveCommands: Commands {
    @ObservedObject private var runtimeState = QuickMarkExtensionRegistry.runtimeState

    private var exporters: [any DocumentExporting] {
        _ = runtimeState.revision
        return QuickMarkExtensionRegistry.exporters
    }

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                activeSplitPreviewViewController()?.saveCurrentFile(nil)
            }
            .keyboardShortcut("s")

            if !exporters.isEmpty {
                Divider()
                Menu("Export") {
                    ForEach(exporters.indices, id: \.self) { index in
                        let exporter = exporters[index]
                        Button("Export as \(exporter.format.displayName)…") {
                            activeSplitPreviewViewController()?.exportDocument(using: exporter)
                        }
                    }
                }
            }
        }
    }
}

final class QuickMarkAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where QuickMarkMarkdownFiles.isMarkdown(url) {
            MarkdownPreviewWindowController.shared.show(url: url)
        }
    }
}

enum QuickMarkMarkdownFiles {
    static let extensions = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]

    static func isMarkdown(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

enum QuickMarkSettings {
    static let scratchpadHotKeyEnabled = "ScratchpadHotKeyEnabled"
    static let scratchpadHotKey = "ScratchpadHotKey"
    static let openPreviewLinksExternally = "OpenPreviewLinksExternally"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            scratchpadHotKeyEnabled: true,
            scratchpadHotKey: ScratchpadHotKeyOption.commandShiftM.rawValue,
            openPreviewLinksExternally: true
        ])
    }
}

enum ScratchpadHotKeyOption: String, CaseIterable, Identifiable {
    case commandShiftM = "commandShiftM"
    case commandOptionM = "commandOptionM"
    case controlOptionM = "controlOptionM"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .commandShiftM: return "⌘⇧M"
        case .commandOptionM: return "⌘⌥M"
        case .controlOptionM: return "⌃⌥M"
        }
    }

    var keyCode: UInt32 { UInt32(kVK_ANSI_M) }

    var modifierFlags: UInt32 {
        switch self {
        case .commandShiftM: return UInt32(cmdKey | shiftKey)
        case .commandOptionM: return UInt32(cmdKey | optionKey)
        case .controlOptionM: return UInt32(controlKey | optionKey)
        }
    }
}

final class ScratchpadHotKeyManager {
    static let shared = ScratchpadHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var defaultsObserver: NSObjectProtocol?
    private let statusKey = "ScratchpadHotKeyRegistrationStatus"
    private var registeredEnabled: Bool?
    private var registeredHotKey: String?
    private var eventHandlerInstallFailed = false

    private init() {}

    func start() {
        guard defaultsObserver == nil else { return }
        installEventHandlerIfNeeded()
        registerFromDefaults()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerFromDefaultsIfNeeded()
        }
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if status == noErr, hotKeyID.signature == ScratchpadHotKeyManager.signature, hotKeyID.id == ScratchpadHotKeyManager.hotKeyID {
                DispatchQueue.main.async {
                    MarkdownPreviewWindowController.shared.showScratchpad()
                }
                return noErr
            }
            return noErr
        }

        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &eventHandler)
        eventHandlerInstallFailed = status != noErr
    }

    private func registerFromDefaults() {
        unregister()

        let isEnabled = UserDefaults.standard.bool(forKey: QuickMarkSettings.scratchpadHotKeyEnabled)
        let rawValue = UserDefaults.standard.string(forKey: QuickMarkSettings.scratchpadHotKey) ?? ScratchpadHotKeyOption.commandShiftM.rawValue
        registeredEnabled = isEnabled
        registeredHotKey = rawValue

        guard isEnabled else {
            setRegistrationStatus("off")
            return
        }

        guard !eventHandlerInstallFailed else {
            setRegistrationStatus("unavailable")
            return
        }

        let option = ScratchpadHotKeyOption(rawValue: rawValue) ?? .commandShiftM
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.signature
        hotKeyID.id = Self.hotKeyID
        let status = RegisterEventHotKey(option.keyCode, option.modifierFlags, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        setRegistrationStatus(status == noErr ? "registered" : "unavailable")
    }

    private func registerFromDefaultsIfNeeded() {
        let isEnabled = UserDefaults.standard.bool(forKey: QuickMarkSettings.scratchpadHotKeyEnabled)
        let rawValue = UserDefaults.standard.string(forKey: QuickMarkSettings.scratchpadHotKey) ?? ScratchpadHotKeyOption.commandShiftM.rawValue
        guard registeredEnabled != isEnabled || registeredHotKey != rawValue else { return }
        registerFromDefaults()
    }

    private func setRegistrationStatus(_ status: String) {
        guard UserDefaults.standard.string(forKey: statusKey) != status else { return }
        UserDefaults.standard.set(status, forKey: statusKey)
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private static let signature: OSType = 0x514d484b
    private static let hotKeyID: UInt32 = 1
}

private func activeSplitPreviewViewController() -> SplitPreviewViewController? {
    NSApp.keyWindow?.contentViewController as? SplitPreviewViewController
}

struct QuickMarkFileCommands: Commands {
    @ObservedObject private var recents = RecentMarkdownStore.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") {
                let welcomeWindow = NSApp.keyWindow
                MarkdownPreviewWindowController.shared.showNewDocument()
                if welcomeWindow?.title == "PeekMark" {
                    welcomeWindow?.close()
                }
            }
            .keyboardShortcut("n")

            Divider()

            Button("Open Markdown…") {
                let welcomeWindow = NSApp.keyWindow
                MarkdownPreviewWindowController.shared.openMarkdownDocument(
                    closing: welcomeWindow?.title == "PeekMark" ? welcomeWindow : nil
                )
            }
            .keyboardShortcut("o")

            Menu("Open Recent") {
                if recents.urls.isEmpty {
                    Text("No Recent Documents")
                } else {
                    ForEach(recents.urls, id: \.path) { url in
                        Button(url.lastPathComponent) {
                            MarkdownPreviewWindowController.shared.show(url: url)
                        }
                    }

                    Divider()

                    Button("Clear Menu") {
                        recents.clear()
                    }
                }
            }
        }
    }
}

final class RecentMarkdownStore: ObservableObject {
    static let shared = RecentMarkdownStore()

    @Published private(set) var urls: [URL]

    private struct Entry {
        let url: URL
        let bookmark: Data?
    }

    private let defaultsKey = "RecentMarkdownEntries"
    private let legacyDefaultsKey = "RecentMarkdownPaths"
    private let maxCount = 10
    private let defaults: UserDefaults
    private var entries: [Entry]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.loadEntries(from: defaults, key: defaultsKey, legacyKey: legacyDefaultsKey)
        urls = entries.map(\.url)
    }

    func add(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        entries.removeAll { $0.url.path == standardizedURL.path }
        entries.insert(Entry(url: standardizedURL, bookmark: makeBookmark(for: standardizedURL)), at: 0)
        if entries.count > maxCount {
            entries.removeLast(entries.count - maxCount)
        }
        save()
    }

    func remove(_ url: URL) {
        entries.removeAll { $0.url.path == url.standardizedFileURL.path }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func resolvedURL(for url: URL) -> URL {
        guard let entry = entries.first(where: { $0.url.path == url.path }), let bookmark = entry.bookmark else {
            return url
        }

        var isStale = false
        do {
            let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                add(resolved)
            }
            return resolved
        } catch {
            return url
        }
    }

    private func save() {
        urls = entries.map(\.url)
        let storedEntries = entries.map { entry -> [String: Any] in
            var stored: [String: Any] = ["path": entry.url.path]
            if let bookmark = entry.bookmark {
                stored["bookmark"] = bookmark
            }
            return stored
        }
        defaults.set(storedEntries, forKey: defaultsKey)
        defaults.removeObject(forKey: legacyDefaultsKey)
    }

    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func loadEntries(from defaults: UserDefaults, key: String, legacyKey: String) -> [Entry] {
        if let storedEntries = defaults.array(forKey: key) as? [[String: Any]] {
            return storedEntries.compactMap { stored in
                guard let path = stored["path"] as? String else { return nil }
                return Entry(url: URL(fileURLWithPath: path), bookmark: stored["bookmark"] as? Data)
            }
        }

        let legacyPaths = defaults.stringArray(forKey: legacyKey) ?? []
        return legacyPaths.map { Entry(url: URL(fileURLWithPath: $0), bookmark: nil) }
    }
}
