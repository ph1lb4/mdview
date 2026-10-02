import AppKit
import WebKit

/// The viewer's web view. Replaces WebKit's Copy, which puts the selection on
/// the pasteboard as HTML with every computed style inlined (including the
/// page's colors and unresolved CSS variables). Slack, Notion, Google Docs and
/// friends often mangle that into one run-on paragraph. Instead we copy clean
/// semantic HTML, RTF made from it, and Markdown as the plain text.
final class MarkdownWebView: WKWebView {
    @objc func copy(_ sender: Any?) {
        // Injected scripts still run with page JavaScript disabled.
        evaluateJavaScript(RichCopy.selectionScript) { [weak self] result, _ in
            guard let self else { return }
            guard let dict = result as? [String: String],
                  let html = dict["html"], let markdown = dict["markdown"] else {
                self.webKitCopy(sender)
                return
            }
            RichCopy.write(html: html, markdown: markdown, to: .general)
        }
    }

    /// Route the context menu's Copy through our implementation too; WebKit's
    /// own item would bypass `copy(_:)`.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items where item.identifier?.rawValue == "WKMenuItemIdentifierCopy" {
            item.target = self
            item.action = #selector(copy(_:))
        }
    }

    /// Fall back to WebKit's built-in Copy (e.g. if the script fails).
    private func webKitCopy(_ sender: Any?) {
        typealias CopyIMP = @convention(c) (AnyObject, Selector, Any?) -> Void
        let selector = #selector(copy(_:))
        guard let imp = class_getMethodImplementation(WKWebView.self, selector) else { return }
        unsafeBitCast(imp, to: CopyIMP.self)(self, selector, sender)
    }
}

enum RichCopy {
    /// Writes one pasteboard item: HTML for web apps, RTF for native apps,
    /// Markdown for anything that only takes plain text.
    static func write(html: String, markdown: String, to pasteboard: NSPasteboard) {
        let document = "<html><head><meta charset=\"utf-8\"></head><body>\(html)</body></html>"

        pasteboard.clearContents()
        pasteboard.setString(document, forType: .html)
        if let rtf = rtf(fromHTML: html) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        pasteboard.setString(markdown, forType: .string)
    }

    /// RTF needs fonts spelled out, otherwise everything arrives as Times.
    private static func rtf(fromHTML html: String) -> Data? {
        let styled = """
        <html><head><meta charset="utf-8"><style>
        body { font: 14px "Helvetica Neue", Helvetica, sans-serif; }
        code, pre { font-family: Menlo, monospace; font-size: 12px; }
        </style></head><body>\(html)</body></html>
        """
        guard let string = try? NSAttributedString(
            data: Data(styled.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else { return nil }
        return try? string.data(
            from: NSRange(location: 0, length: string.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// Serializes the current selection as `{html, markdown}`, or returns null
    /// when nothing is selected. The selection is re-wrapped in its ancestors
    /// up to `<article>`, so half a code block or list item keeps its shape.
    static let selectionScript = #"""
    (() => {
        const sel = getSelection();
        if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return null;
        const range = sel.getRangeAt(0);
        const article = document.querySelector('article');

        let root = range.cloneContents();
        let node = range.commonAncestorContainer;
        if (node.nodeType !== Node.ELEMENT_NODE) node = node.parentNode;
        for (let n = node; n && n !== article && n !== document.body; n = n.parentNode) {
            const wrap = n.cloneNode(false);
            wrap.appendChild(root);
            root = wrap;
        }
        const box = document.createElement('div');
        box.appendChild(root);
        box.querySelectorAll('[style]').forEach(e => e.removeAttribute('style'));

        const inline = n => Array.from(n.childNodes).map(convert).join('');
        const block = s => s.trim() ? s.trim() + '\n\n' : '';
        const indent = (s, pad) => s.replace(/\n(?=.)/g, '\n' + pad);

        function convert(n) {
            if (n.nodeType === Node.TEXT_NODE) {
                return n.parentNode.closest && n.parentNode.closest('pre')
                    ? n.textContent : n.textContent.replace(/\s+/g, ' ');
            }
            if (n.nodeType !== Node.ELEMENT_NODE) return '';
            const tag = n.nodeName;
            switch (tag) {
            case 'H1': case 'H2': case 'H3': case 'H4': case 'H5': case 'H6':
                return block('#'.repeat(+tag[1]) + ' ' + inline(n).trim());
            case 'P': return block(inline(n));
            case 'PRE': {
                const code = n.querySelector('code');
                const lang = ((code && code.className) || '').replace(/^language-/, '');
                return '```' + lang + '\n' + n.textContent.replace(/\n$/, '') + '\n```\n\n';
            }
            case 'BLOCKQUOTE':
                return inline(n).trim().split('\n').map(l => ('> ' + l).trimEnd()).join('\n') + '\n\n';
            case 'UL': case 'OL': {
                let i = +(n.getAttribute('start') || 1);
                const items = Array.from(n.children).filter(c => c.nodeName === 'LI').map(li => {
                    const marker = tag === 'OL' ? (i++) + '. ' : '- ';
                    const body = inline(li).trim().replace(/\n{3,}/g, '\n\n');
                    return marker + indent(body, ' '.repeat(marker.length));
                });
                // A nested list starts on its own line under the parent item.
                const lead = n.parentNode.nodeName === 'LI' ? '\n' : '';
                return lead + items.join('\n') + '\n\n';
            }
            case 'TABLE': {
                const rows = Array.from(n.querySelectorAll('tr')).map(tr =>
                    '| ' + Array.from(tr.children).map(c => inline(c).trim().replace(/\|/g, '\\|')).join(' | ') + ' |');
                if (rows.length === 0) return '';
                const cols = n.querySelector('tr').children.length;
                rows.splice(1, 0, '|' + ' --- |'.repeat(cols));
                return rows.join('\n') + '\n\n';
            }
            case 'HR': return '---\n\n';
            case 'BR': return '\n';
            case 'STRONG': case 'B': return '**' + inline(n) + '**';
            case 'EM': case 'I': return '*' + inline(n) + '*';
            case 'DEL': case 'S': return '~~' + inline(n) + '~~';
            case 'CODE': return '`' + n.textContent + '`';
            case 'A': {
                const href = n.getAttribute('href');
                return href ? '[' + inline(n) + '](' + href + ')' : inline(n);
            }
            case 'IMG': return '![' + (n.getAttribute('alt') || '') + '](' + (n.getAttribute('src') || '') + ')';
            default: return inline(n);
            }
        }

        const markdown = inline(box).replace(/\n{3,}/g, '\n\n').trim();
        return { html: box.innerHTML, markdown: markdown };
    })()
    """#
}
