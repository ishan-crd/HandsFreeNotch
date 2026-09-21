import XCTest
@testable import HandsFreeNotchCore

@MainActor
final class StreamingTests: XCTestCase {
    private var pipeline: CommandPipeline!
    private var ran: [String] = []

    override func setUp() async throws {
        let apps = AppIndex()
        let names = ["Safari", "Spotify", "Slack", "Google Chrome"]
        apps.setEntriesForTesting(names.map { AppEntry(name: $0, url: URL(fileURLWithPath: "/Applications/\($0).app"), bundleID: nil) })
        pipeline = CommandPipeline(speech: SpeechListener(), apps: apps)
        pipeline.stableAfter = 0.05
        pipeline.runner = { [weak self] intent in self?.ran.append(intent.title) }
        ran = []
    }

    /// Feeds partials the way the recognizer does: cumulative, with time for each to settle.
    private func speak(_ partials: [String], final: String? = nil) async {
        for partial in partials {
            pipeline.ingest(partial, isFinal: false, listening: true)
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        if let final {
            pipeline.ingest(final, isFinal: true, listening: false)
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    func testCommandsRunWhileTheSentenceIsStillBeingSpoken() async {
        await speak(["Open", "Open Safari"])
        XCTAssertEqual(ran, ["Open Safari"], "the app opens before anything else is said")

        await speak(["Open Safari and", "Open Safari and search", "Open Safari and search YouTube"])
        XCTAssertEqual(ran, ["Open Safari"], "a search waits: more query words may follow")

        await speak(["Open Safari and search YouTube and on", "Open Safari and search YouTube and on YouTube search"])
        XCTAssertEqual(ran, ["Open Safari", "Open www.youtube.com"], "the search settles once a command follows the 'and'")

        await speak(["Open Safari and search YouTube and on YouTube search FaZe Rug"],
                    final: "Open Safari and search YouTube and on YouTube search FaZe Rug")
        XCTAssertEqual(ran, ["Open Safari", "Open www.youtube.com", "YouTube “faze rug”"])
    }

    func testAndInsideAQueryIsNotACut() async {
        await speak(["search for rock", "search for rock and", "search for rock and roll"], final: "search for rock and roll")
        XCTAssertEqual(ran, ["Google “rock and roll”"])
    }

    func testThenSplitsEverything() async {
        await speak(["open spotify then", "open spotify then next song"], final: "open spotify then next song")
        XCTAssertEqual(ran, ["Open Spotify", "Next track"])
    }

    func testRecognizerRewritesDoNotRerunCommands() async {
        await speak(["Open S le", "Open Slack le", "Open Slack"])
        XCTAssertEqual(ran, ["Open Slack"])
        await speak(["Open Slack open", "Open Slack open Safari"], final: "Open Slack open Safari")
        XCTAssertEqual(ran, ["Open Slack", "Open Safari"], "a second command with no separator still runs")
    }

    func testTypedTextRunsEverything() async {
        pipeline.handle("open chrome and then new tab and search for cats")
        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertEqual(ran, ["Open Google Chrome", "New tab", "Google “cats”"])
    }
}
