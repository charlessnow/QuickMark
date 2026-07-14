import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text("PeekMark")
                .font(.title.bold())
            Text("Quick Look preview is ready.\nSelect a Markdown file in Finder, then press Space to preview.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 16) {
                Button("New") {
                    newDocument()
                }
                Button("Open Markdown…") {
                    openFilePicker()
                }
                Button("Settings…") {
                    openSettings()
                }
            }
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 300)
    }

    private func newDocument() {
        let welcomeWindow = NSApp.keyWindow
        MarkdownPreviewWindowController.shared.showNewDocument()
        welcomeWindow?.close()
    }

    private func openFilePicker() {
        MarkdownPreviewWindowController.shared.openMarkdownDocument(closing: NSApp.keyWindow)
    }
}
