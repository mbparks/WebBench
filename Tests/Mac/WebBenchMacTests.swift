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

  func testFreeCanvasTileArmsOverSelectionAndContainerModeInsertsInside() throws {
    let original = "<html><body data-free-page style='position:relative'><section id='panel'></section></body></html>"
    let model = session(original)
    let section = try XCTUnwrap(model.nodes.first { $0.tag == "section" })
    model.select(section.id)
    let tile = PaletteTile.Tile(title: "Button", target: nil, action: nil)
    tile.model = model
    tile.item = "Button"
    XCTAssertTrue(model.targetsPage)
    XCTAssertFalse(model.supportsDevicePlacement)
    tile.arm()
    XCTAssertEqual(model.insertTool, "Button")
    XCTAssertEqual(model.currentText, original)
    let page = try XCTUnwrap(model.nodes.first { $0.tag == "body" })
    model.history.groupsByEvent = false
    model.history.beginUndoGrouping()
    model.insertFromCanvas(["id": page.id, "item": "Button", "point": ["x": 96, "y": 72]], armed: true)
    model.history.endUndoGrouping()
    XCTAssertTrue(model.currentText.contains("left: 96px; top: 72px"))
    XCTAssertTrue(model.nodes.contains { $0.tag == "button" && $0.parent == page.id })
    let edited = model.currentText
    model.undo()
    XCTAssertEqual(model.currentText, original)
    model.redo()
    XCTAssertEqual(model.currentText, edited)
    model.select(section.id)
    model.dropOnPage = false
    model.history.beginUndoGrouping()
    tile.arm()
    model.history.endUndoGrouping()
    XCTAssertTrue(model.nodes.contains { $0.tag == "button" && $0.parent == section.id })
    model.undo()
    XCTAssertEqual(model.currentText, edited)
    XCTAssertFalse(session("<html><body><section></section></body></html>").targetsPage)
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
  func testPaletteButtonPreviewFromNativeWindow() async throws {
    let original = try Resources.string("canvas-page", "html")
    let model = session(original)
    model.snap = false
    let host = NSHostingView(rootView: WorkspaceView(m: model))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    func find<T: NSView>(_ type: T.Type, in view: NSView, where matches: (T) -> Bool) -> T? {
      if let candidate = view as? T, matches(candidate) { return candidate }
      for child in view.subviews {
        if let found = find(type, in: child, where: matches) { return found }
      }
      return nil
    }
    func waitFor(_ condition: () -> Bool) async throws {
      for _ in 0..<160 {
        if condition() { return }
        try await Task.sleep(nanoseconds: 50_000_000)
      }
    }
    try await waitFor { model.designer?.ready == true }
    let web = try XCTUnwrap(find(WKWebView.self, in: host, where: { _ in true }), model.status)
    let diagnostic = try? await web.checkValue(
      "[location.href,document.title,document.readyState,typeof WB,typeof WebBench,typeof LayoutDrop,typeof window.webBenchTools,document.body?.outerHTML.slice(0,180)].join(' | ')",
      in: .defaultClient)
    guard model.designer?.ready == true else {
      XCTFail("Design did not start. " + model.status + " " + String(describing: diagnostic))
      return
    }
    let tile = try XCTUnwrap(find(PaletteTile.Tile.self, in: host, where: { $0.item == "Button" }))
    let origin = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)
    let drop = web.convert(NSPoint(x: web.bounds.midX, y: web.bounds.midY), to: nil)
    func send(_ type: NSEvent.EventType, at point: NSPoint) throws {
      let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      window.sendEvent(event)
    }
    try send(.leftMouseDown, at: origin)
    try send(.leftMouseDragged, at: drop)
    try await Task.sleep(nanoseconds: 250_000_000)
    let ghost = try await web.checkValue("!!document.querySelector('body > button[inert]')", in: .defaultClient)
    XCTAssertEqual(ghost as? Bool, true, "Hover failed. " + model.status)
    XCTAssertEqual(model.currentText, original)
    try send(.leftMouseUp, at: drop)
    try await waitFor { model.nodes.contains { $0.tag == "button" } }
    XCTAssertTrue(model.currentText.contains("position: absolute"), model.status)
    XCTAssertEqual(model.nodes.filter { $0.tag == "button" }.count, 1, model.status)
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
