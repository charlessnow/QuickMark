import Foundation
import Markdown

/// Public entry point for QuickMarkCore.
///
/// Converts a Markdown source string into a self-contained HTML document
/// suitable for `WKWebView.loadHTMLString(_:baseURL:)`.
///
/// The output document:
/// - Begins with `<!DOCTYPE html>` (required — prevents WKWebView quirks mode).
/// - Declares `<meta name="color-scheme" content="light dark">`.
/// - Inlines every CSS rule plus highlight.js, Mermaid, and MathJax runtimes — zero remote requests.
/// - Wraps rendered Markdown in `<article class="markdown-body">…</article>`.
public struct MarkdownRenderer {

    public init() {}

    /// Render Markdown source to a complete HTML document.
    /// - Parameters:
    ///   - markdown: Markdown source text.
    ///   - title:    Value used for the document `<title>`. Defaults to `"Preview"`.
    /// - Returns: A self-contained HTML string.
    public static func render(
        markdown: String,
        title: String = "Preview",
        customization: RenderCustomization = .none
    ) -> String {
        let intelligence = PreviewIntelligence(markdown: markdown)
        let document = Document(parsing: intelligence.markdownBody)
        let bodyHTML = intelligence.enhance(bodyHTML: HTMLFormatter.format(document))
        return HTMLTemplate.build(bodyHTML: bodyHTML, title: title, customization: customization)
    }

    /// Instance variant of ``render(markdown:title:)`` for callers that prefer
    /// to hold a renderer value.
    public func render(
        _ markdown: String,
        title: String = "Preview",
        customization: RenderCustomization = .none
    ) -> String {
        Self.render(markdown: markdown, title: title, customization: customization)
    }
}
