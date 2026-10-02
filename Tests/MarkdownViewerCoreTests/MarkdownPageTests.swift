import Foundation
import Testing
@testable import MarkdownViewerCore

@Test func rendersHeadingAsH1() {
    let html = MarkdownPage.html(from: "# Hello")
    #expect(html.contains("<h1>Hello</h1>"))
}

@Test func rendersFencedCodeBlock() {
    let html = MarkdownPage.html(from: "```\nlet x = 1\n```")
    #expect(html.contains("<pre>"))
    #expect(html.contains("let x = 1"))
}

@Test func outputIsCompleteStyledDocument() {
    let html = MarkdownPage.html(from: "plain text")
    #expect(html.contains("<!DOCTYPE html>"))
    #expect(html.contains("<style>"))
    #expect(html.contains("prefers-color-scheme: dark"))
}

@Test func includesPrintStylesForPDFAndPrinting() {
    let html = MarkdownPage.html(from: "plain text")
    // Print/PDF output must force a light, full-width layout regardless of the
    // system appearance, so the document isn't centred in a narrow column or
    // rendered on a dark background on paper.
    #expect(html.contains("@media print"))
}

@Test func includesLockedDownContentSecurityPolicy() {
    // Untrusted .md files can embed raw HTML (Ink passes it through), so the
    // page must ship a CSP that blocks script execution and remote resource
    // loads while still allowing our own inline styles and inline images.
    let html = MarkdownPage.html(from: "# anything")
    #expect(html.contains("Content-Security-Policy"))
    #expect(html.contains("default-src 'none'"))
    #expect(html.contains("style-src 'unsafe-inline'"))
    #expect(html.contains("img-src data:"))
}

@Test func blocksRemoteImagesByDefault() {
    // Default (and Quick Look) must never permit remote image loads.
    let html = MarkdownPage.html(from: "# anything")
    #expect(html.contains("img-src data:;"))
    #expect(!html.contains("https:"))
}

@Test func allowsRemoteImagesWhenOptedIn() {
    // When the user opts in, remote http/https images are permitted, but
    // scripts and other resource types stay blocked.
    let html = MarkdownPage.html(from: "# anything", allowRemoteImages: true)
    #expect(html.contains("img-src data: https: http:;"))
    #expect(html.contains("default-src 'none'"))
}

@Test func rendersEmphasisAndLists() {
    let html = MarkdownPage.html(from: "- one\n- **two**")
    #expect(html.contains("<ul>"))
    #expect(html.contains("<strong>two</strong>"))
}

@Test func rendersFileContents() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MarkdownPageTests-\(UUID().uuidString).md")
    try Data("# From a file".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let html = try MarkdownPage.html(contentsOf: url)
    #expect(html.contains("<h1>From a file</h1>"))
}

@Test func rendersNonUTF8FileWithoutThrowing() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MarkdownPageTests-\(UUID().uuidString).md")
    let latin1 = "# Caf\u{e9}".data(using: .isoLatin1)!
    try latin1.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let html = try MarkdownPage.html(contentsOf: url)
    #expect(html.contains("Caf"))
}

// Files written for Slack or by AI tools put one item per line without blank
// lines in between. Strict Markdown joins those into one paragraph, so the
// viewer keeps every line break instead.

@Test func keepsSingleLineBreaksInParagraphs() {
    let html = MarkdownPage.html(from: "first line\nsecond line")
    #expect(html.contains("first line<br>second line"))
}

@Test func leavesBlockquotesAlone() {
    // Ink garbles hard breaks inside quotes ("first<br>&gt; second"), so
    // quoted lines are not touched.
    let html = MarkdownPage.html(from: "> first\n> second")
    #expect(html.contains("<blockquote><p>first second</p></blockquote>"))
}

@Test func rendersBulletCharacterLinesAsList() {
    let html = MarkdownPage.html(from: "*Status*\n• one\n• two")
    #expect(html.contains("<p><em>Status</em></p>"))
    #expect(html.contains("<ul><li>one</li><li>two</li></ul>"))
}

@Test func listItemsDoNotGetStrayBreaks() {
    let html = MarkdownPage.html(from: "- one\n- two\n\n1. three\n2. four")
    #expect(html.contains("<ul><li>one</li><li>two</li></ul>"))
    #expect(html.contains("<ol><li>three</li><li>four</li></ol>"))
}

@Test func leavesCodeBlocksAndTablesUntouched() {
    let html = MarkdownPage.html(from: "```\n• a\nb\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |")
    #expect(html.contains("• a\nb"))
    #expect(!html.contains("<br>"))
    #expect(html.contains("<td>1</td><td>2</td>"))
}

@Test func headingFollowedByTextStaysClean() {
    let html = MarkdownPage.html(from: "# Title\ntext")
    #expect(html.contains("<h1>Title</h1>"))
    #expect(!html.contains("<br>"))
}
