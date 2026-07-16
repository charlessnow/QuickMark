import SwiftUI
import AppKit
import QuickMarkCore

struct MenuBarView: View {
#if !APP_STORE
    let updater: UpdaterController
#endif
    @AppStorage(QuickMarkSettings.scratchpadHotKey) private var selectedHotKey = ScratchpadHotKeyOption.commandShiftM.rawValue
    @AppStorage(QuickMarkSettings.scratchpadHotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage("ScratchpadHotKeyRegistrationStatus") private var registrationStatus = "registered"

    var body: some View {
        Button("New Document") {
            MarkdownPreviewWindowController.shared.showNewDocument()
        }
        .keyboardShortcut("n")

        Button("Open Scratchpad") {
            MarkdownPreviewWindowController.shared.showScratchpad()
        }

        Text(hotKeyStatusText)
            .foregroundStyle(.secondary)

        Divider()

        Button("Open Markdown…") {
            openFilePicker()
        }
        .keyboardShortcut("o")

        Divider()

        Button("Settings…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Button("About PeekMark") {
            NSApp.orderFrontStandardAboutPanel(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

#if !APP_STORE
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
#endif

        Divider()

        Button("Quit PeekMark") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openFilePicker() {
        MarkdownPreviewWindowController.shared.openMarkdownDocument()
    }

    private var hotKeyLabel: String {
        (ScratchpadHotKeyOption(rawValue: selectedHotKey) ?? .commandShiftM).label
    }

    private var hotKeyStatusText: String {
        if !hotKeyEnabled { return "Scratchpad Hotkey: Off" }
        if registrationStatus == "unavailable" { return "Scratchpad Hotkey: Unavailable" }
        return "Scratchpad Hotkey: \(hotKeyLabel)"
    }
}
