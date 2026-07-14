import Foundation

/// Builds the self-contained HTML document that wraps rendered Markdown.
///
/// Loads `template.html`, `highlight.min.js`, `mermaid.min.js`, MathJax, and
/// the light/dark highlight.js CSS themes from the package bundle, then
/// substitutes placeholders.
/// The resulting string is suitable for `WKWebView.loadHTMLString(_:baseURL:)`
/// with no remote requests required.
public enum HTMLTemplate {

    // MARK: - Placeholders

    private enum Placeholder {
        static let title              = "{{TITLE}}"
        static let content            = "{{CONTENT}}"
        static let highlightJS        = "{{HIGHLIGHT_JS}}"
        static let mermaidJS          = "{{MERMAID_JS}}"
        static let mathJaxJS          = "{{MATHJAX_JS}}"
        static let highlightLightCSS  = "{{HIGHLIGHT_LIGHT_CSS}}"
        static let highlightDarkCSS   = "{{HIGHLIGHT_DARK_CSS}}"
        static let scriptNonce        = "{{SCRIPT_NONCE}}"
        static let customCSS           = "{{CUSTOM_CSS}}"
        static let articleClasses      = "{{ARTICLE_CLASSES}}"
    }

    // MARK: - Resource names

    private enum Resource {
        static let template       = (name: "template",        ext: "html")
        static let highlightJS    = (name: "highlight.min",   ext: "js")
        static let mermaidJS      = (name: "mermaid.min",     ext: "js")
        static let mathJaxJS      = (name: "mathjax-tex-svg", ext: "js")
        static let highlightLight = (name: "highlight-light.min", ext: "css")
        static let highlightDark  = (name: "highlight-dark.min",  ext: "css")
    }

    // MARK: - Public API

    /// Build a complete HTML document from rendered Markdown body HTML.
    /// - Parameters:
    ///   - bodyHTML: HTML already produced from the Markdown AST.
    ///   - title:    Document `<title>`.
    /// - Returns: A fully self-contained HTML string.
    public static func build(
        bodyHTML: String,
        title: String,
        customization: RenderCustomization = .none
    ) -> String {
        var html = templateString()
        let scriptNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        html = html.replacingOccurrences(of: Placeholder.title,             with: htmlEscape(title))
        html = html.replacingOccurrences(of: Placeholder.scriptNonce,       with: scriptNonce)
        html = html.replacingOccurrences(of: Placeholder.customCSS,         with: safeInlineCSS(customization.additionalCSS))
        html = html.replacingOccurrences(of: Placeholder.articleClasses,    with: safeArticleClasses(customization.articleClassNames))
        html = html.replacingOccurrences(of: Placeholder.highlightLightCSS, with: loadResource(Resource.highlightLight))
        html = html.replacingOccurrences(of: Placeholder.highlightDarkCSS,  with: loadResource(Resource.highlightDark))
        html = html.replacingOccurrences(of: Placeholder.highlightJS,       with: loadResource(Resource.highlightJS))
        html = html.replacingOccurrences(of: Placeholder.mermaidJS,         with: loadResource(Resource.mermaidJS))
        html = html.replacingOccurrences(of: Placeholder.mathJaxJS,         with: loadResource(Resource.mathJaxJS))
        // CONTENT replacement is done LAST so any literal "{{...}}" sequences
        // inside the rendered Markdown cannot collide with placeholders.
        html = html.replacingOccurrences(of: Placeholder.content,           with: bodyHTML)
        return html
    }

    // MARK: - Resource loading

    private static func templateString() -> String {
        if let s = loadOptionalResource(Resource.template) { return s }
        // Fallback minimal template — used only if the bundled resource is missing
        // (e.g. when the library is consumed in an unusual build configuration).
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file: data:; media-src file: data:; font-src file: data:; style-src 'unsafe-inline'; script-src 'nonce-\(Placeholder.scriptNonce)'; connect-src 'none'; object-src 'none'; frame-src 'none'; worker-src 'none'; base-uri 'none'; form-action 'none'">
        <title>\(Placeholder.title)</title>
        <style>\(Placeholder.highlightLightCSS)\n@media (prefers-color-scheme: dark){\(Placeholder.highlightDarkCSS)}\n\(Placeholder.customCSS)</style>
        </head>
        <body><article class="markdown-body \(Placeholder.articleClasses)">\(Placeholder.content)</article>
        <script nonce="\(Placeholder.scriptNonce)">\(Placeholder.highlightJS)</script>
        <script nonce="\(Placeholder.scriptNonce)">if(typeof hljs!=='undefined'){hljs.highlightAll();}</script>
        <script nonce="\(Placeholder.scriptNonce)">\(Placeholder.mermaidJS)</script>
        <script nonce="\(Placeholder.scriptNonce)">if(typeof mermaid!=='undefined'){mermaid.initialize({startOnLoad:true,securityLevel:'strict'});}</script>
        <script nonce="\(Placeholder.scriptNonce)">window.MathJax={tex:{inlineMath:[['$','$'],['\\\\(','\\\\)']],displayMath:[['$$','$$'],['\\\\[','\\\\]']],processEscapes:true},options:{skipHtmlTags:['script','noscript','style','textarea','pre','code']},svg:{fontCache:'none'}};</script>
        <script nonce="\(Placeholder.scriptNonce)">\(Placeholder.mathJaxJS)</script>
        <script nonce="\(Placeholder.scriptNonce)">window.__quickMarkRenderState={status:'ready',errors:[]};document.documentElement.setAttribute('data-quickmark-render-status','ready');window.dispatchEvent(new CustomEvent('quickmark-render-ready',{detail:window.__quickMarkRenderState}));</script>
        </body></html>
        """
    }

    private static func loadResource(_ res: (name: String, ext: String)) -> String {
        loadOptionalResource(res) ?? ""
    }

    private static func loadOptionalResource(_ res: (name: String, ext: String)) -> String? {
        guard let url = Bundle.module.url(forResource: res.name, withExtension: res.ext),
              let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    // MARK: - Utilities

    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func safeInlineCSS(_ css: String) -> String {
        css.replacingOccurrences(of: "</style", with: "<\\/style", options: .caseInsensitive)
    }

    private static func safeArticleClasses(_ classes: [String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return classes.compactMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.unicodeScalars.allSatisfy(allowed.contains) else {
                return nil
            }
            return trimmed
        }.joined(separator: " ")
    }
}
