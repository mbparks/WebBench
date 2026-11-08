import AppKit
import Vision
import XCTest

final class PaletteUITests: XCTestCase {
  @MainActor func testFirstButtonFromPackagedApp() throws {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = XCUIApplication(url: repo.appendingPathComponent("WebBench.app"))
    app.launch()
    defer { app.terminate() }
    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 15))
    let userHome = URL(fileURLWithPath: String(cString: getpwuid(getuid()).pointee.pw_dir))
    let drafts = userHome.appendingPathComponent("Library/Application Support/Green Shoe Garage/WebBench/Drafts")
    func entries() -> Set<String> {
      Set((try? FileManager.default.contentsOfDirectory(atPath: drafts.path)) ?? [])
    }
    let before = entries()
    app.typeKey("n", modifierFlags: [.command])
    let canvas = window.webViews.firstMatch
    XCTAssertTrue(canvas.waitForExistence(timeout: 15), app.debugDescription)
    let tile = window.buttons["insert-Button"]
    XCTAssertTrue(tile.waitForExistence(timeout: 10), window.debugDescription)
    func readGuide() throws -> String {
      let image = canvas.screenshot().image
      let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
      let request = VNRecognizeTextRequest()
      try VNImageRequestHandler(cgImage: cg).perform([request])
      return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
    func seesGuide(_ text: String) -> Bool {
      text.localizedCaseInsensitiveContains("first element") ||
        (text.localizedCaseInsensitiveContains("element") && text.localizedCaseInsensitiveContains("placed text"))
    }
    var guide = ""
    for _ in 0..<5 {
      guide = try readGuide()
      if seesGuide(guide) { break }
      Thread.sleep(forTimeInterval: 0.3)
    }
    print("Canvas image text: " + guide)
    let name = try XCTUnwrap(entries().subtracting(before).first, "New draft missing at " + drafts.path + "\n" + app.debugDescription)
    let page = drafts.appendingPathComponent(name).appendingPathComponent("index.html")
    let original = try Data(contentsOf: page)
    let shot = XCTAttachment(screenshot: canvas.screenshot())
    shot.name = "Blank Design canvas"
    add(shot)
    XCTAssertTrue(seesGuide(guide), "Blank canvas text: " + guide)
    let start = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.click(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
    app.typeKey("s", modifierFlags: [.command])
    let saved = NSPredicate { _, _ in
      (try? String(contentsOf: page, encoding: .utf8).contains("<button")) == true
    }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: saved, object: nil)],
                                  timeout: 12), .completed, window.debugDescription)
    let changed = try String(contentsOf: page, encoding: .utf8)
    let tag = try XCTUnwrap(changed.range(of: #"<button\b[^>]*>Button</button>"#, options: .regularExpression))
    XCTAssertTrue(changed[tag].contains("position: absolute"))
    XCTAssertEqual(Data(changed.replacingCharacters(in: tag, with: "").utf8), original)
  }
}
