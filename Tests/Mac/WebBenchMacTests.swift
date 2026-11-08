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
  func testInteractionsPickApplyUndoReopenAndRemove() throws {
    let original = "<html><head></head><body><button>Test</button><p>Standby</p></body></html>"
    let model = session(original)
    let button = try XCTUnwrap(model.nodes.first { $0.tag == "button" })
    let target = try XCTUnwrap(model.nodes.first { $0.tag == "p" })
    model.select(button.id)
    model.openInteractions()
    let draft = try XCTUnwrap(model.workflow)
    XCTAssertEqual(draft.trigger, button.id)
    draft.pick(target.id, for: .target(draft.steps[0].id))
    draft.steps[0].value = "Acquired"
    XCTAssertEqual(model.currentText, original)
    model.finishInteraction(draft)
    XCTAssertNil(model.workflow)
    let edited = model.currentText
    XCTAssertTrue(edited.contains("Acquired"))
    model.undo()
    XCTAssertEqual(model.currentText, original)
    model.redo()
    XCTAssertEqual(model.currentText, edited)
    model.select(button.id)
    model.openInteractions()
    let reopened = try XCTUnwrap(model.workflow)
    XCTAssertTrue(reopened.existing)
    XCTAssertEqual(reopened.steps[0].target, target.id)
    XCTAssertFalse(reopened.dirty)
    model.finishInteraction(reopened, remove: true)
    XCTAssertFalse(model.currentText.contains("data-webbench-workflow"))
    model.undo()
    XCTAssertEqual(model.currentText, edited)
  }

  func testDeviceCameraWorkflowCanBePickedEditedAndUndone() throws {
    let source = "<html><body><button>Start</button><video></video><img alt='still'></body></html>"
    let model = session(source)
    let button = try XCTUnwrap(model.nodes.first { $0.tag == "button" })
    let video = try XCTUnwrap(model.nodes.first { $0.tag == "video" })
    let image = try XCTUnwrap(model.nodes.first { $0.tag == "img" })
    model.select(button.id)
    model.openInteractions()
    let draft = try XCTUnwrap(model.workflow)
    draft.steps = [InteractionStep(.cameraStart)]
    let role = InteractionPick.target(draft.steps[0].id)
    XCTAssertNil(draft.pick(image.id, for: role))
    XCTAssertEqual(draft.pick(video.id, for: role), video.id)
    model.finishInteraction(draft)
    let saved = model.currentText
    XCTAssertTrue(saved.contains("data-webbench-devices"))
    model.undo()
    XCTAssertEqual(model.currentText, source)
    model.redo()
    XCTAssertEqual(model.currentText, saved)
    model.select(button.id)
    model.openInteractions()
    let edit = try XCTUnwrap(model.workflow)
    XCTAssertEqual(edit.steps.first?.kind, .cameraStart)
    XCTAssertEqual(edit.steps.first?.target, video.id)
    model.finishInteraction(edit, remove: true)
    XCTAssertFalse(model.currentText.contains("data-webbench-devices"))
  }

  func testSnippetInsertReopenEditAndUndo() throws {
    let original = "<html><body><section><!-- keep --></section></body></html>"
    let model = session(original)
    let parent = try XCTUnwrap(model.nodes.first { $0.tag == "section" })
    model.openSnippet(at: parent.id, adding: .iframe)
    let draft = try XCTUnwrap(model.snippetEditor)
    draft.fields = false
    draft.text = "<iframe src='child.html' title='Meter' loading='lazy'></iframe>"
    XCTAssertEqual(model.currentText, original)
    model.history.groupsByEvent = false
    model.history.beginUndoGrouping()
    model.applySnippet(draft)
    model.history.endUndoGrouping()
    let inserted = model.currentText
    XCTAssertEqual(inserted, original.replacingOccurrences(of: "</section>", with: draft.text + "</section>"))
    let frame = try XCTUnwrap(model.nodes.first { $0.tag == "iframe" })
    model.openSnippet(at: frame.id)
    let reopened = try XCTUnwrap(model.snippetEditor)
    XCTAssertEqual(reopened.text, draft.text)
    reopened.url = "next.html"
    model.history.beginUndoGrouping()
    model.applySnippet(reopened)
    model.history.endUndoGrouping()
    XCTAssertEqual(model.currentText, inserted.replacingOccurrences(of: "child.html", with: "next.html"))
    model.undo()
    XCTAssertEqual(model.currentText, inserted)
    model.undo()
    XCTAssertEqual(model.currentText, original)
    model.redo()
    XCTAssertEqual(model.currentText, inserted)
  }

  func testLayoutShapeCatalogAndSourceUndo() throws {
    let original = "<html><body><section><!-- keep --></section></body></html>"
    let model = session(original)
    let shapes = model.elements.filter { $0.group == "Layout" && $0.shape != nil }
    let star = try XCTUnwrap(shapes.first { $0.title == "Star" })
    XCTAssertEqual(star.shape?.points?.count, 10)
    XCTAssertEqual(shapes.count, 24)
    let parent = try XCTUnwrap(model.nodes.first { $0.tag == "section" })
    model.history.groupsByEvent = false
    model.history.beginUndoGrouping()
    model.mutate(["kind": "insert", "item": star.id], id: parent.id, name: "Insert star")
    model.history.endUndoGrouping()
    let inserted = model.currentText
    XCTAssertTrue(inserted.contains("clip-path: polygon("))
    XCTAssertTrue(model.nodes.contains { $0.name == "Star" && $0.parent == parent.id })
    model.undo()
    XCTAssertEqual(model.currentText, original)
    model.redo()
    XCTAssertEqual(model.currentText, inserted)
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
