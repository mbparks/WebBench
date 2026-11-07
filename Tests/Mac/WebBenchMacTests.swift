import AppKit
import SwiftUI
import WebKit
import XCTest

@testable import WebBench

// Hosted tests exercise the real JavaScriptCore bridge, UndoManager and WKWebView configurations.
@MainActor
final class WebBenchMacTests: XCTestCase {
  private func session(_ source: String) -> Session {
    let model = Session()
    model.writing = false
    let path = "index.html"
    model.site = Site(
      root: FileManager.default.temporaryDirectory, standalone: true,
      files: [path: SourceFile(path: path, data: Data(source.utf8))])
    model.choosePage(path)
    return model
  }
  func testVisualAndCodeChangesShareNativeHistory() throws {
    let original = "<html><head></head><body><main><p>Readout</p></main></body></html>"
    let m = session(original)
    m.history.groupsByEvent = false
    let parent = try XCTUnwrap(m.nodes.first { $0.tag == "main" })
    m.history.beginUndoGrouping()
    m.mutate(["kind": "insert", "item": "Button"], id: parent.id, name: "Insert button")
    m.history.endUndoGrouping()
    let inserted = m.currentText
    XCTAssertEqual(
      inserted,
      original.replacingOccurrences(
        of: "</main>", with: "<button type=\"button\">Button</button></main>"))
    m.history.beginUndoGrouping()
    m.editSource(inserted.replacingOccurrences(of: "Readout", with: "Voltage"))
    m.history.endUndoGrouping()
    let edited = m.currentText
    m.undo()
    XCTAssertEqual(m.currentText, inserted)
    m.undo()
    XCTAssertEqual(m.currentText, original)
    m.redo()
    m.redo()
    XCTAssertEqual(m.currentText, edited)
  }
  func testIncompleteTypingStaysInSourceAndRecovers() {
    let m = session("<main><p>A</p></main>")
    let partial = "<main><button title='"
    m.editSource(partial)
    m.render()
    XCTAssertEqual(m.currentText, partial)
    XCTAssertNil(m.preview)
    m.editSource("<main><button>Ready</button></main>")
    m.render()
    XCTAssertNotNil(m.preview)
    XCTAssertTrue(m.sourceIssue.isEmpty)
  }
  func testEditIsInertAndRunCannotSeeDesignChannel() async throws {
    let html = """
      <!doctype html><html><head></head><body><button id="go">Test</button><output>idle</output>
      <script>document.querySelector('output').textContent='ran';
      console.log('design bridge = '+Boolean(window.webkit?.messageHandlers?.design));</script></body></html>
      """
    let m = session(html)
    let host = NSHostingView(rootView: WorkspaceView(m: m))
    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled],
      backing: .buffered, defer: false)
    win.contentView = host
    win.orderFront(nil)
    defer { win.orderOut(nil) }
    func web(_ view: NSView) -> WKWebView? {
      if let v = view as? WKWebView { return v }
      for child in view.subviews { if let v = web(child) { return v } }
      return nil
    }
    let button = try XCTUnwrap(m.nodes.first { $0.tag == "button" })
    m.select(button.id)
    for _ in 0..<100 {
      if m.inspection?.id == button.id { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertEqual(m.inspection?.label, "button#go")
    let editWeb = try XCTUnwrap(web(host))
    let result = try await editWeb.checkValue(
      "document.querySelector('output').textContent", in: .defaultClient)
    XCTAssertEqual(result as? String, "idle")
    m.setRun(true)
    for _ in 0..<100 {
      if m.logs.contains(where: { $0.contains("design bridge = false") }) { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    XCTAssertTrue(m.logs.contains(where: { $0.contains("design bridge = false") }))
    let runWeb = try XCTUnwrap(web(host))
    XCTAssertFalse(runWeb === editWeb)
    let active = try await runWeb.checkValue(
      "document.querySelector('output').textContent", in: .page)
    XCTAssertEqual(active as? String, "ran")
    XCTAssertEqual(m.currentText, html)
  }
  func testPackagedSampleWorkflowChecks() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let checks = SampleChecks(directory: dir)
    let host = NSHostingView(rootView: WorkspaceView(m: checks.editor))
    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled],
      backing: .buffered, defer: false)
    win.contentView = host
    win.orderFront(nil)
    checks.host = host
    defer { win.orderOut(nil) }
    await checks.run()
    XCTAssertEqual(checks.results.count, 13, checks.report)
    XCTAssertTrue(checks.results.allSatisfy { $0.hasPrefix("PASS ·") }, checks.report)
    XCTAssertEqual(try String(contentsOf: checks.reportURL, encoding: .utf8), checks.report)
    XCTAssertNotNil(checks.instrument)
    XCTAssertFalse(checks.safariOpened)
  }

  func testAcceptingExternalPageDeletionClearsCanvasAndRetainsOtherDrafts() throws {
    let m = session("<main>Draft</main>")
    let base = Data("p {}".utf8)
    m.site?.files["site.css"] = SourceFile(path: "site.css", data: base)
    m.chooseFile("site.css")
    m.editSource("p {color: green}")
    let c = Conflict(
      path: "index.html", recovery: FileManager.default.temporaryDirectory, disk: nil)
    m.useExternal(c)
    XCTAssertNil(m.preview)
    XCTAssertNil(m.selected)
    XCTAssertTrue(m.page.isEmpty)
    XCTAssertEqual(m.currentText, "p {color: green}")
    XCTAssertEqual(m.site?.dirtyPaths, ["site.css"])
    m.setRun(true)
    XCTAssertFalse(m.running)
  }
}
