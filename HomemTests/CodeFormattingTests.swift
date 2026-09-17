import XCTest
@testable import Homem

final class CodeFormattingTests: XCTestCase {
    func testFencesPreserveIndentationAndExcludeLanguage() {
        let parts = MarkdownSegment.parse("Before `inline`\n```swift\n    let name = \"猫\"\n    print(name)\n```\nAfter")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[1], MarkdownSegment(text: "    let name = \"猫\"\n    print(name)", language: "swift", isCode: true))
        XCTAssertEqual(parts[2].text, "After")
        XCTAssertFalse(MarkdownSegment.parse("Use ``` inside a sentence")[0].isCode)
    }
    func testStreamingAndNestedFences() {
        let streaming = MarkdownSegment.parse("~~~python\n  print('hello')\n")
        XCTAssertEqual(streaming, [MarkdownSegment(text: "  print('hello')\n", language: "python", isCode: true)])
        let nested = MarkdownSegment.parse("````markdown\n```swift\nlet a = 1\n```\n````")
        XCTAssertEqual(nested.first?.text, "```swift\nlet a = 1\n```")
        XCTAssertEqual(nested.count, 1)
    }
    func testToolPayloadFormatsStructuredDataAndPreservesText() {
        let json = ToolCodeContent(.string("{\"ok\":true,\"count\":2}"))
        XCTAssertEqual(json.language, "json")
        XCTAssertTrue(json.text.contains("\n"))
        XCTAssertEqual(try JSONValue.parse(json.text), ["ok": true, "count": 2])
        let output = ToolCodeContent("  first line\n    second line\n")
        XCTAssertEqual(output.text, "  first line\n    second line\n")
        XCTAssertEqual(output.language, "plaintext")
    }
    func testHighlightPreservesUnicodeAndWhitespaceInBothThemes() async {
        let source = "\n    let name = \"猫 🌱\"\n    print(name)\n\n"
        for dark in [false, true] {
            let highlighted = await CodeHighlighting.render(source, language: "swift", dark: dark)
            XCTAssertEqual(String(highlighted.characters), source)
            XCTAssertGreaterThan(highlighted.runs.count, 1, "Expected syntax colors")
        }
        let unsupported = await CodeHighlighting.render(source, language: "not-a-language", dark: false)
        XCTAssertEqual(String(unsupported.characters), source)
        let empty = await CodeHighlighting.render(" \n", language: "swift", dark: false)
        XCTAssertEqual(String(empty.characters), " \n")
    }
}
