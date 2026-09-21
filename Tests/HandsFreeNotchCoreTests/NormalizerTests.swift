import XCTest
@testable import HandsFreeNotchCore

final class NormalizerTests: XCTestCase {
    func testStripsFillersAndPunctuation() {
        XCTAssertEqual(Normalizer.normalize("Hey, can you open Safari please?"), "open safari")
        XCTAssertEqual(Normalizer.normalize("  Open   YouTube.  "), "open youtube")
        XCTAssertEqual(Normalizer.normalize("go to github.com"), "go to github.com")
        XCTAssertEqual(Normalizer.normalize("please"), "")
    }

    func testSplitsSequences() {
        XCTAssertEqual(Normalizer.splitSequence("open spotify then play"), ["open spotify", "play"])
        XCTAssertEqual(Normalizer.splitSequence("open chrome and then new tab"), ["open chrome", "new tab"])
        XCTAssertEqual(Normalizer.splitSequence("search for rock and roll"), ["search for rock and roll"])
    }

    func testNumbers() {
        XCTAssertEqual(Normalizer.firstNumber(in: "set volume to 40"), 40)
        XCTAssertEqual(Normalizer.firstNumber(in: "volume to fifty percent"), 50)
        XCTAssertNil(Normalizer.firstNumber(in: "volume to the max"))
    }
}
