import XCTest
@testable import PROJECT_Tracking

final class ArtifactLinkTests: XCTestCase {
    func testMarkdownPasteDomainAndCustomScheme() throws {
        let markdown = try ArtifactLink(title: "", url: "[Макет](https://example.com/file)")
        XCTAssertEqual(markdown.title, "Макет")
        XCTAssertEqual(markdown.url, "https://example.com/file")
        XCTAssertEqual(try ArtifactLink(title: "", url: "example.com").url, "https://example.com")
        XCTAssertEqual(try ArtifactLink(title: "", url: "obsidian://open?vault=test").url, "obsidian://open?vault=test")
    }
    func testInvalidAndMultilineURLsFailAndParenthesesAreEncoded() throws {
        XCTAssertThrowsError(try ArtifactLink(title: "", url: "мусор"))
        XCTAssertThrowsError(try ArtifactLink(title: "", url: "https://"))
        XCTAssertThrowsError(try ArtifactLink(title: "", url: "https://example.com\ntext"))
        XCTAssertTrue(try ArtifactLink(title: "", url: "https://example.com/a(b)").url.contains("%28b%29"))
    }
}
