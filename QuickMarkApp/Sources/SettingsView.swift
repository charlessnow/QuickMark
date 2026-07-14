import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            ScratchpadSettingsView()
                .tabItem { Label("Scratchpad", systemImage: "square.and.pencil") }
            PreviewSettingsView()
                .tabItem { Label("Preview", systemImage: "doc.richtext") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 320)
        .padding()
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section("Quick Look Extension") {
                Text("Build and sign PeekMark, then select a .md file in Finder and press Space to preview.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
#if OFFICIAL_EXTENSIONS
            OfficialOptionalFeaturesSettingsView()
#else
            Section("Optional Features") {
                Text("Custom themes, workspace search, and additional export formats are available in official editions.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Button("Learn More…") {
                    NSWorkspace.shared.open(URL(string: "https://peekmark.app")!)
                }
            }
#endif
        }
        .formStyle(.grouped)
    }
}

private struct ScratchpadSettingsView: View {
    @AppStorage(QuickMarkSettings.scratchpadHotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(QuickMarkSettings.scratchpadHotKey) private var selectedHotKey = ScratchpadHotKeyOption.commandShiftM.rawValue
    @AppStorage("ScratchpadHotKeyRegistrationStatus") private var registrationStatus = "registered"

    var body: some View {
        Form {
            Section("Global Hotkey") {
                Toggle("Enable Scratchpad hotkey", isOn: $hotKeyEnabled)
                Picker("Shortcut", selection: $selectedHotKey) {
                    ForEach(ScratchpadHotKeyOption.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .disabled(!hotKeyEnabled)

                Text("The shortcut opens the existing Scratchpad window, or creates it if needed.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(statusText)
                    .foregroundStyle(registrationStatus == "unavailable" ? .red : .secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        if !hotKeyEnabled { return "Status: Off" }
        if registrationStatus == "unavailable" { return "Status: Unavailable. Choose another shortcut." }
        return "Status: Registered"
    }
}

private struct PreviewSettingsView: View {
    @AppStorage(QuickMarkSettings.openPreviewLinksExternally) private var openLinksExternally = true

    var body: some View {
        Form {
            Section("Links") {
                Toggle("Open clicked preview links in the default browser", isOn: $openLinksExternally)
                Text("Quick Look previews still block clicked links. This setting only affects document windows in the app.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("PeekMark")
                .font(.title2.bold())
            Text("Version 0.1.0 (Community)")
                .foregroundStyle(.secondary)
            Text("AGPL-3.0 Open Source")
                .foregroundStyle(.secondary)
                .font(.caption)
            Link("github.com/QuartzInkStudio/PeekMark",
                 destination: URL(string: "https://github.com/QuartzInkStudio/PeekMark")!)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
