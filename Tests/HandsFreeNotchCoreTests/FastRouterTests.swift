import XCTest
@testable import HandsFreeNotchCore

final class FastRouterTests: XCTestCase {
    private var router: FastRouter!
    private var apps: AppIndex!

    private static func fakeApps() -> AppIndex {
        let index = AppIndex()
        // A fixed list so the tests do not depend on what is installed here.
        let names = ["Safari", "Google Chrome", "Spotify", "Visual Studio Code", "System Settings", "Slack", "Finder", "Terminal", "Xcode", "Messages"]
        let entries = names.map { AppEntry(name: $0, url: URL(fileURLWithPath: "/Applications/\($0).app"), bundleID: nil) }
        index.setEntriesForTesting(entries)
        return index
    }

    override func setUp() {
        apps = Self.fakeApps()
        router = FastRouter(apps: apps)
    }

    private func route(_ text: String) -> Intent? { router.route(text)?.intent }

    func testOpensAppsByNameAndNickname() {
        XCTAssertEqual(route("open Spotify"), .openApp(apps.entries.first { $0.name == "Spotify" }!))
        XCTAssertEqual(route("Open chrome."), .openApp(apps.entries.first { $0.name == "Google Chrome" }!))
        XCTAssertEqual(route("launch vs code"), .openApp(apps.entries.first { $0.name == "Visual Studio Code" }!))
        XCTAssertEqual(route("hey can you open the settings please"), .openApp(apps.entries.first { $0.name == "System Settings" }!))
        XCTAssertEqual(route("switch to slack"), .openApp(apps.entries.first { $0.name == "Slack" }!))
    }

    func testSpeechSplitsAreForgiven() {
        XCTAssertEqual(route("open spot if I"), .openApp(apps.entries.first { $0.name == "Spotify" }!))
        XCTAssertEqual(route("open x code"), .openApp(apps.entries.first { $0.name == "Xcode" }!))
    }

    func testOpensSites() {
        XCTAssertEqual(route("open youtube"), .openURL(URL(string: "https://www.youtube.com")!))
        XCTAssertEqual(route("go to github.com"), .openURL(URL(string: "https://github.com")!))
        XCTAssertEqual(route("open github dot com slash ishan-crd"), .openURL(URL(string: "https://github.com/ishan-crd")!))
        XCTAssertEqual(route("open slack in the browser"), .openURL(URL(string: "https://app.slack.com")!))
        XCTAssertEqual(route("open this link"), .openClipboardLink)
    }

    func testAppBeatsSiteWhenInstalled() {
        XCTAssertEqual(route("open slack"), .openApp(apps.entries.first { $0.name == "Slack" }!))
    }

    func testSearch() {
        XCTAssertEqual(route("search for best ramen near me"), .search(query: "best ramen near me", engine: .google))
        XCTAssertEqual(route("youtube lofi beats"), .search(query: "lofi beats", engine: .youtube))
        XCTAssertEqual(route("search youtube for cats"), .search(query: "cats", engine: .youtube))
        XCTAssertEqual(route("look up everest on wikipedia"), .search(query: "everest", engine: .wikipedia))
        XCTAssertEqual(route("what is the capital of peru"), .search(query: "what is the capital of peru", engine: .google))
    }

    func testTypingAndKeys() {
        XCTAssertEqual(route("type hello team on my way"), .typeText("hello team on my way"))
        XCTAssertEqual(route("press enter"), .pressKey(KeyChord(.return)))
        XCTAssertEqual(route("enter"), .pressKey(KeyChord(.return)))
        XCTAssertEqual(route("press command shift t"), .pressKey(KeyChord(.t, command: true, shift: true)))
        XCTAssertEqual(route("select all"), .shortcut(.selectAll))
        XCTAssertEqual(route("new tab"), .shortcut(.newTab))
        XCTAssertEqual(route("close the tab"), .shortcut(.closeTab))
    }

    func testSystemAndMedia() {
        XCTAssertEqual(route("volume up"), .volume(.up(steps: 3)))
        XCTAssertEqual(route("set volume to 40 percent"), .volume(.set(percent: 40)))
        XCTAssertEqual(route("mute"), .volume(.mute))
        XCTAssertEqual(route("next song"), .media(.next))
        XCTAssertEqual(route("pause"), .media(.pause))
        XCTAssertEqual(route("lock screen"), .system(.lockScreen))
        XCTAssertEqual(route("take a screenshot"), .system(.screenshot))
        XCTAssertEqual(route("scroll down"), .scroll(.down(lines: 10)))
        XCTAssertEqual(route("scroll up a lot"), .scroll(.up(lines: 40)))
        XCTAssertEqual(route("brightness down"), .brightness(up: false))
    }

    func testQuitAndHide() {
        XCTAssertEqual(route("quit spotify"), .quitApp(apps.entries.first { $0.name == "Spotify" }!))
        XCTAssertEqual(route("close chrome"), .quitApp(apps.entries.first { $0.name == "Google Chrome" }!))
        XCTAssertEqual(route("hide slack"), .hideApp(apps.entries.first { $0.name == "Slack" }!))
    }

    func testScreenWorkGoesStraightToTheAgent() {
        XCTAssertEqual(route("click on the english link on this page"), .agent(goal: "click on the english link on this page"))
        XCTAssertEqual(route("reply to alex saying i am late"), .agent(goal: "reply to alex saying i am late"))
        XCTAssertEqual(route("book a table for two tonight"), .agent(goal: "book a table for two tonight"))
        XCTAssertEqual(route("select all"), .shortcut(.selectAll), "whole-utterance shortcuts still win")
    }

    func testUnknownFallsThrough() {
        XCTAssertNil(route("find me the cheapest flight to tokyo next friday"))
        XCTAssertNil(route("open the thing I was looking at yesterday"))
        XCTAssertNil(route(""))
    }

    func testEarlyFireFlags() {
        XCTAssertTrue(route("open safari")!.firesEarly)
        XCTAssertFalse(route("search for cats")!.firesEarly)
        XCTAssertFalse(route("type hello")!.firesEarly)
    }
}
