import XCTest
@testable import QuickMarkCore

final class PreviewIntelligenceTests: XCTestCase {
    func testRendersFrontmatterChipsTOCAndWikilinks() {
        let html = MarkdownRenderer.render(markdown: """
        ---
        type: Project
        status: Active
        tags: [markdown, preview]
        related_to:
          - "[[Rendering Notes]]"
        ---
        # Alpha

        See [[Rendering Notes|the renderer]].

        ## Details

        More text.
        """, title: "Alpha")

        XCTAssertTrue(html.contains("peekmark-frontmatter"))
        XCTAssertTrue(html.contains("peekmark-chip-type"))
        XCTAssertTrue(html.contains("Project"))
        XCTAssertTrue(html.contains("peekmark-toc"))
        XCTAssertTrue(html.contains("href=\"#alpha\""))
        XCTAssertTrue(html.contains("href=\"#details\""))
        XCTAssertTrue(html.contains("peekmark-wikilink://Rendering%20Notes"))
        XCTAssertFalse(html.contains("<h1>Alpha</h1>"))
    }

    func testDoesNotRenderWikilinksInsideFencedCode() {
        let html = MarkdownRenderer.render(markdown: """
        ```markdown
        [[Do Not Link]]
        ```
        """)

        XCTAssertFalse(html.contains("peekmark-wikilink://Do%20Not%20Link"))
        XCTAssertTrue(html.contains("[[Do Not Link]]"))
    }

    func testResolvesSameDirectoryWikilinkCandidates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = directory.appendingPathComponent("rendering-notes.md")
        try "# Rendering Notes".write(to: target, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            MarkdownWikilinkResolver.resolve("Rendering Notes", in: directory)?.lastPathComponent,
            "rendering-notes.md"
        )
        XCTAssertNil(MarkdownWikilinkResolver.resolve("Missing Note", in: directory))
    }

    func testExtractsWikilinkTargetFromURL() {
        let url = URL(string: "peekmark-wikilink://Rendering%20Notes")
        XCTAssertEqual(MarkdownWikilinkResolver.target(from: url), "Rendering Notes")
    }

    func testIncludesBundledMermaidRenderingForMermaidFences() {
        let html = MarkdownRenderer.render(markdown: """
        ```mermaid
        flowchart TD
          A[Markdown] --> B[Preview]
        ```
        """)

        XCTAssertTrue(html.contains("language-mermaid"))
        XCTAssertTrue(html.contains("flowchart TD"))
        XCTAssertTrue(html.contains("peekmark-mermaid"))
        XCTAssertTrue(html.contains("mermaid.initialize"))
        XCTAssertFalse(html.contains("{{MERMAID_JS}}"))
        XCTAssertFalse(html.contains("<script src="))
    }

    func testIncludesBundledMathJaxRenderingForLatexMath() {
        let html = MarkdownRenderer.render(markdown: """
        Inline math $E = mc^2$ and block math:

        $$
        \\int_0^1 x^2 \\, dx = \\frac{1}{3}
        $$
        """)

        XCTAssertTrue(html.contains("E = mc^2"))
        XCTAssertTrue(html.contains("\\int_0^1"))
        XCTAssertTrue(html.contains("window.MathJax"))
        XCTAssertTrue(html.contains("inlineMath"))
        XCTAssertTrue(html.contains("displayMath"))
        XCTAssertFalse(html.contains("{{MATHJAX_JS}}"))
        XCTAssertFalse(html.contains("<script src="))
    }

    func testPublishesRenderReadinessAfterAsyncContentSettles() {
        let html = MarkdownRenderer.render(markdown: """
        ```mermaid
        flowchart LR
          A --> B
        ```

        Math $x^2$.
        """)

        XCTAssertTrue(html.contains("window.__quickMarkRenderState"))
        XCTAssertTrue(html.contains("await Promise.all([runMermaid(), waitForMath()])"))
        XCTAssertTrue(html.contains("quickmark-render-ready"))
        XCTAssertTrue(html.contains("data-quickmark-render-status"))
    }

    func testAppliesLocalRenderCustomizationWithoutLeavingTemplatePlaceholders() {
        let html = MarkdownRenderer.render(
            markdown: "# Custom",
            customization: RenderCustomization(
                identifier: "test.theme",
                additionalCSS: ".markdown-body { --fgColor-accent: #ff0000; }",
                articleClassNames: ["theme-test", "invalid class"]
            )
        )

        XCTAssertTrue(html.contains("--fgColor-accent: #ff0000"))
        XCTAssertTrue(html.contains("class=\"markdown-body theme-test\""))
        XCTAssertFalse(html.contains("invalid class"))
        XCTAssertFalse(html.contains("{{CUSTOM_CSS}}"))
        XCTAssertFalse(html.contains("{{ARTICLE_CLASSES}}"))
    }

    func testCustomCSSCannotCloseTheTemplateStyleElement() {
        let html = MarkdownRenderer.render(
            markdown: "Text",
            customization: RenderCustomization(additionalCSS: "</STYLE><script>alert(1)</script>")
        )

        XCTAssertFalse(html.localizedCaseInsensitiveContains("</style><script>alert(1)</script>"))
        XCTAssertTrue(html.contains("<\\/style>"))
    }
}
