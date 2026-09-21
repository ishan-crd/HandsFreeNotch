import XCTest
@testable import HandsFreeNotchCore

final class FuzzyTests: XCTestCase {
    func testScores() {
        XCTAssertEqual(Fuzzy.score("spotify", "Spotify"), 1)
        XCTAssertGreaterThanOrEqual(Fuzzy.score("spot if i", "Spotify"), 0.95)
        XCTAssertGreaterThan(Fuzzy.score("visual code", "Visual Studio Code"), 0.85)
        XCTAssertGreaterThan(Fuzzy.score("chrom", "Google Chrome"), 0.6)
        XCTAssertLessThan(Fuzzy.score("banana", "Spotify"), 0.4)
    }

    func testLLMPayloadMapsToIntents() throws {
        let apps = AppIndex()
        apps.setEntriesForTesting([AppEntry(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: nil)])
        let json = #"{"action":"open_app","app":"Safari"}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(RoutePayload.self, from: json)
        XCTAssertEqual(try payload.intent(apps: apps), .openApp(apps.entries[0]))

        let bad = #"{"action":"open_app","app":"Nonexistent"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(RoutePayload.self, from: bad).intent(apps: apps))
    }
}
