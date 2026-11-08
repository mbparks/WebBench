import AppKit
import CryptoKit
import ImageIO
import SwiftUI
@preconcurrency import WebKit

extension WKWebView {
  @MainActor func checkValue(_ source: String, in world: WKContentWorld) async throws -> Any {
    try await withCheckedThrowingContinuation { continuation in
      evaluateJavaScript(source, in: nil, in: world) { result in
        continuation.resume(with: result)
      }
    }
  }
}

// The checks drive a separate editor session. Only files made for this run are opened.
@MainActor
final class SampleChecks: ObservableObject {
  let editor = Session()
  weak var host: NSView?
  let directory: URL
  @Published private(set) var activity = "Preparing disposable projects"
  @Published private(set) var results: [String] = []
  @Published private(set) var finished = false
  @Published private(set) var instrument: URL?
  @Published private(set) var safariOpened = false
  @Published private(set) var safariResult = "Pending manual Safari check"
  @Published private(set) var reportError = ""
  private let started = ISO8601DateFormatter().string(from: Date())

  init(
    directory: URL = Session.supportDirectory.appendingPathComponent("Checks")
      .appendingPathComponent(UUID().uuidString)
  ) {
    self.directory = directory
  }
  var reportURL: URL { directory.appendingPathComponent("WebBench-checks.txt") }
  var report: String {
    #if arch(arm64)
      let arch = "arm64"
    #else
      let arch = "x86_64"
    #endif
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    let lines =
      [
        "WebBench " + version + " · sample workflow checks", started,
        ProcessInfo.processInfo.operatingSystemVersionString + " · process " + arch,
        activity, "",
      ] + results + [
        "", safariResult, "",
        "Inputs are bundled fixtures. The layout, workbench and writing checks dispatch synthetic events into a real WKWebView. Finder dragging, physical input, and the conflict dialog are separate manual checks.",
      ]
    return lines.joined(separator: "\n")
  }
  func saveReport() {
    do {
      try Data(report.utf8).write(to: reportURL, options: .atomic)
      reportError = ""
    } catch { reportError = "Could not write the report. " + error.localizedDescription }
  }
  func openSafari() {
    guard let instrument else { return }
    guard
      let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
    else {
      safariResult = "Safari was unavailable."
      saveReport()
      return
    }
    NSWorkspace.shared.open(
      [instrument], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration()
    ) { app, error in
      DispatchQueue.main.async {
        self.safariOpened = app != nil && error == nil
        self.safariResult =
          error.map { "Safari launch failed. " + $0.localizedDescription }
          ?? "Safari opened. Calculation awaits user observation."
        self.saveReport()
      }
    }
  }
  func recordSafari(returned77: Bool) {
    guard safariOpened else { return }
    safariResult =
      returned77
      ? "USER VERIFIED in Safari · 25 °C returned 77."
      : "USER REPORTED in Safari · expected 77, observed another result."
    saveReport()
  }

  func run() async {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      activity = error.localizedDescription
      finished = true
      return
    }
    await check("1. Open, save and reopen", noOp)
    await check("2. Flex insertion, mobile spacing and Undo/Redo", responsiveEdit)
    await check("3. Single-file instrument in Run", fieldInstrument)
    await check("4. Positioned workbench, link and ODIN", workbench)
    await check("5. External stylesheet recovery", conflict)
    await check("6. Write, format and insert at the caret", documentWriting)
    await check("7. Place, drag and resize a design layer", designCanvas)
    await check("8. Drag from the native palette and reorder in flow", dragFromPalette)
    await check("9. Arrange selected layers together", multipleLayers)
    await check("10. Free canvas, styling, device previews and export", freeCanvasStudio)
    await check("11. Page and element backgrounds, favicon painting and export", pageAppearance)
    await check("12. Resize and edit a photo, undo and reopen", photoEditing)
    await check("13. Insert inside a section and rearrange Layers", nestedLayers)
    await check("14. Edit and run a conditional power calculation", calculatedInteraction)
    let passed = results.filter { $0.hasPrefix("PASS ·") }.count
    activity =
      Task.isCancelled ? "Checks stopped" : "\(passed) of \(results.count) automated checks passed"
    finished = true
    saveReport()
  }
  private func check(_ name: String, _ perform: () async throws -> String) async {
    guard !Task.isCancelled else { return }
    activity = name
    saveReport()
    do {
      let detail = try await perform()
      try Task.checkCancellation()
      results.append("PASS · " + name + "\n" + detail)
    } catch is CancellationError {
      results.append("STOPPED · " + name)
    } catch {
      results.append("FAIL · " + name + "\n" + error.localizedDescription)
    }
    saveReport()
  }
  private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw BenchError(message) }
  }
  private func sample() throws -> Site {
    try Site.copySample(from: Session.sampleSource(), into: directory)
  }
  private func enter(_ site: Site) {
    editor.writing = false
    editor.zoom = "100%"
    editor.mode = .split
    editor.width = 900
    editor.property = "margin-top"
    editor.freePlacement = false
    editor.sidebarTab = "Tree"
    editor.use(site)
  }
  private func save() throws {
    guard var site = editor.site else { throw BenchError("Missing check project.") }
    defer { editor.site = site }
    try site.save(recovery: directory.appendingPathComponent("Recovery"))
  }
  private func currentSite() throws -> Site {
    guard let site = editor.site else { throw BenchError("The editor has no project.") }
    return site
  }
  private func node(_ label: String) throws -> Int {
    guard let id = editor.nodes.first(where: { $0.label == label })?.id else {
      throw BenchError("Missing source element " + label)
    }
    return id
  }
  private func wait(_ message: String, until condition: () -> Bool) async throws {
    for _ in 0..<200 {
      try Task.checkCancellation()
      if condition() { return }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    throw BenchError(message + " Editor status: " + editor.status)
  }
  private func sourceView(in root: NSView?) -> NSTextView? {
    guard let root else { return nil }
    if let text = root as? NSTextView, text.accessibilityLabel() == "Source code" { return text }
    for child in root.subviews { if let text = sourceView(in: child) { return text } }
    return nil
  }
  private func findWeb(_ root: NSView?) -> WKWebView? {
    guard let root else { return nil }
    if let web = root as? WKWebView, let c = web.navigationDelegate as? Canvas.Coordinator,
      c.state.token == editor.preview?.token, web.url != nil, !web.isLoading, c.state.run || c.ready
    {
      return web
    }
    for view in root.subviews { if let web = findWeb(view) { return web } }
    return nil
  }
  private func web() async throws -> WKWebView {
    try await wait("The current WebKit canvas did not finish loading.") {
      self.findWeb(self.host) != nil
    }
    guard let result = findWeb(host) else { throw BenchError("The WebKit canvas changed.") }
    return result
  }
  @discardableResult private func js(_ source: String) async throws -> Any? {
    let current = try await web()
    return try await current.checkValue(source, in: editor.running ? .page : .defaultClient)
  }
  private func viewport(_ width: Int) async throws {
    editor.width = Double(width)
    let canvas = try await web()
    for _ in 0..<120 {
      try Task.checkCancellation()
      let current = try await canvas.checkValue("innerWidth", in: .defaultClient)
      if current as? Int == width { return }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    throw BenchError("WebKit did not reach a \(width) px viewport.")
  }
  private func inspect(_ sourceLabel: String) async throws {
    let id = try node(sourceLabel)
    editor.select(id)
    _ = try await web()
    try await wait("The inspector did not identify " + sourceLabel + ".") {
      self.editor.inspection?.id == id
    }
  }
  private func noOp() async throws -> String {
    let s = try sample()
    let instrument = directory.appendingPathComponent("Original-instrument.html")
    try Data(Resources.string("instrument", "html").utf8).write(
      to: instrument, options: .withoutOverwriting)
    var count = 0
    for target in [s.root, instrument] {
      let opened = try Site.open(target)
      let before = opened.files.mapValues { Data(SHA256.hash(data: $0.bytes)) }
      enter(opened)
      try save()
      let after = try Site.open(target).files.mapValues { Data(SHA256.hash(data: $0.bytes)) }
      try require(before == after, "File hashes changed across save and reopen.")
      count += before.count
    }
    enter(s)
    try await js("document.querySelector('h1').click(); true")
    try await wait("Heading click was not mapped.") { self.editor.inspection?.label == "h1" }
    let original = editor.currentText
    editor.mutate(["kind": "text", "value": "Instrument bench"], name: "Check heading edit")
    try save()
    let result = try Site.open(s.root)
    try require(
      result.files["index.html"]?.text
        == original.replacingOccurrences(
          of: "<h1>Workbench fixture</h1>", with: "<h1>Instrument bench</h1>"),
      "Heading diff was larger than expected.")
    for path in s.files.keys where path != "index.html" {
      try require(
        s.files[path]?.bytes == result.files[path]?.bytes, "Unrelated file changed: " + path)
    }
    return
      "\(count) SHA-256 hashes matched. A canvas click mapped the heading and only its text changed on disk."
  }
  private func documentWriting() async throws -> String {
    let url = directory.appendingPathComponent("Writing.html")
    let before =
      "<!doctype html>\r\n<html><body><!-- keep -->\r\n  <p data-ink='original'>One &amp; two.</p>\r\n</body></html>"
    try Data(before.utf8).write(to: url, options: .withoutOverwriting)
    enter(try Site.open(url))
    editor.setWriting(true)
    let canvas = try await web()
    let editable = try await js("document.querySelector('p').isContentEditable")
    try require(editable as? Bool == true, "The paragraph has no writing caret.")
    try await js(
      """
      (() => {const p=document.querySelector('p'), r=document.createRange();
        p.focus(); r.setStart(p.firstChild,6); r.setEnd(p.firstChild,9);
        const s=getSelection(); s.removeAllRanges(); s.addRange(r); return true;})()
      """)
    editor.writeCommand("bold")
    let bold = before.replacingOccurrences(of: "two.", with: "<strong>two</strong>.")
    try await wait("Formatting did not reach the source.") { self.editor.currentText == bold }
    try await js(
      """
      (() => {const p=document.querySelector('p');
        p.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,cancelable:true,inputType:'insertText',data:'Ω'}));
        const r=document.createRange(); r.selectNodeContents(p); r.collapse(false);
        const s=getSelection(); s.removeAllRanges(); s.addRange(r);
        p.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,cancelable:true,inputType:'insertParagraph'}));
        for(const c of 'Ready ') document.activeElement.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,cancelable:true,inputType:'insertText',data:c}));
        return true;})()
      """)
    let typed = bold.replacingOccurrences(of: "two</strong>", with: "Ω</strong>")
      .replacingOccurrences(of: ".</p>", with: ".</p>\r\n  <p>Ready </p>")
    try await wait("Rapid input or Return produced an unexpected patch.") {
      self.editor.currentText == typed
    }
    try require(findWeb(host) === canvas, "Typing replaced the active WKWebView.")
    editor.writeCommand("element", "button")
    let expected = typed.replacingOccurrences(
      of: "Ready </p>", with: "Ready <button type=\"button\">Button</button></p>")
    try await wait("The button missed its caret position.") { self.editor.currentText == expected }
    editor.undo()
    try require(editor.currentText == typed, "Undo did not remove the button as one edit.")
    editor.redo()
    try require(editor.currentText == expected, "Redo did not restore the button.")
    try save()
    let reopened = try Site.open(url)
    try require(
      reopened.files[url.lastPathComponent]?.bytes == Data(expected.utf8),
      "The reopened bytes differ from the expected edited source.")
    return
      "Formatted an existing word, typed Ω, split the paragraph, typed rapidly and inserted a button at the caret. Undo, Redo and the reopened CRLF file matched."
  }
  private func designCanvas() async throws -> String {
    let file = directory.appendingPathComponent("Design-board.html")
    let original = try Resources.string("board", "html")
    try Data(original.utf8).write(to: file, options: .withoutOverwriting)
    enter(try Site.open(file))
    editor.mode = .design
    editor.snap = true
    let view = try await web()
    editor.arm("Box")
    (view.navigationDelegate as? Canvas.Coordinator)?.sync()
    try await js(
      """
      (()=>{const p=document.querySelector('main'), r=p.getBoundingClientRect();
        p.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true,clientX:r.left+141,clientY:r.top+248}));
        return true;})()
      """)
    let box =
      "<div style=\"width: 160px; height: 96px; background-color: #d8e6dc; position: absolute; left: 144px; top: 248px;\"></div>"
    let placed = original.replacingOccurrences(of: "</main>", with: box + "</main>")
    try await wait("The armed box did not land at the snapped coordinates.") {
      self.editor.currentText == placed
    }
    try await wait("The inserted layer was not selected in Arrange.") {
      self.editor.inspection?.canMove == true
    }
    try await js(
      """
      (()=>{const e=document.querySelector('main > div:last-child'), r=e.getBoundingClientRect();
        const send=(type,x,y)=>e.dispatchEvent(new PointerEvent(type,{bubbles:true,cancelable:true,button:0,pointerId:74,
          altKey:true,clientX:r.x+x,clientY:r.y+y}));
        send('pointerdown',4,4);send('pointermove',25,17);send('pointerup',25,17);return true;})()
      """)
    let movedBox = box.replacingOccurrences(of: "144px", with: "165px").replacingOccurrences(
      of: "248px", with: "261px")
    let moved = original.replacingOccurrences(of: "</main>", with: movedBox + "</main>")
    try await wait("Direct dragging did not produce the expected two-value patch.") {
      self.editor.currentText == moved
    }
    try await wait("The moved layer was not ready for a size change.") {
      self.editor.inspection?.canResize == true
    }
    editor.requestFrame(["width": 200, "height": 100])
    let resized = moved.replacingOccurrences(
      of: movedBox,
      with: movedBox.replacingOccurrences(of: "160px", with: "200px").replacingOccurrences(
        of: "96px", with: "100px"))
    try await wait("Arrange did not resize the selected layer.") {
      self.editor.currentText == resized
    }
    editor.undo()
    try require(editor.currentText == moved, "One Undo did not restore both original dimensions.")
    editor.redo()
    try require(editor.currentText == resized, "Redo did not restore the resized frame.")
    try await viewport(390)
    try require(editor.currentText == resized, "Device preview edited the page source.")
    try save()
    try require(
      try Data(contentsOf: file) == Data(resized.utf8),
      "Saved HTML diverged from the expected board.")
    let reopened = try Site.open(file)
    try require(reopened.files[file.lastPathComponent]?.text == resized, "Reopened board differs.")
    return
      "Placed and moved a box with synthetic WebKit events, resized it through Arrange, exercised native Undo/Redo and a phone viewport, and compared the saved and reopened HTML."
  }
  private func paletteTile(in view: NSView?, item: String) -> PaletteTile.Tile? {
    guard let view else { return nil }
    if let tile = view as? PaletteTile.Tile, tile.item == item { return tile }
    for child in view.subviews {
      if let tile = paletteTile(in: child, item: item) { return tile }
    }
    return nil
  }

  private func dragFromPalette() async throws -> String {
    let file = directory.appendingPathComponent("Palette.html")
    let original = """
      <!doctype html><html><head><style>body{margin:0}main{padding:16px;min-height:220px}section{display:flex;gap:14px;padding:20px;min-height:45px}</style></head><body>
      <main><section id="tools"><p id="one">Meter</p><p id="two">Scope</p></section><!-- keep --></main></body></html>
      """
    try Data(original.utf8).write(to: file, options: .withoutOverwriting)
    enter(try Site.open(file))
    editor.mode = .design
    editor.sidebarTab = "Insert"
    editor.width = 700
    let canvas = try await web()
    guard let window = canvas.window, let tile = paletteTile(in: host, item: "Button") else {
      throw BenchError("The visible Button tile was unavailable.")
    }
    let rect = try await js(
      "(()=>{const r=document.querySelector('#two').getBoundingClientRect();return [(r.left+1)/innerWidth,(r.top+r.height/2)/innerHeight]})()"
    )
    guard let xy = rect as? [Double], xy.count == 2 else {
      throw BenchError("Could not locate the flex slot.")
    }
    let dest = canvas.convert(
      NSPoint(
        x: xy[0] * canvas.bounds.width,
        y: (canvas.isFlipped ? xy[1] : 1 - xy[1]) * canvas.bounds.height), to: nil)
    guard let designer = editor.designer else { throw BenchError("Design canvas is not ready.") }
    let screen = window.convertPoint(toScreen: dest)
    designer.palette(tile.item, phase: "hover", screen: screen, snap: editor.snap)
    let ghost = try await js("!!document.querySelector('#tools > button[inert]')")
    try require(
      ghost as? Bool == true && editor.currentText == original,
      "The native drag failed to preview a button inside the flex row.")
    designer.palette(tile.item, phase: "drop", screen: screen, snap: editor.snap)
    let button = "<button type=\"button\">Button</button>"
    let withButton = original.replacingOccurrences(
      of: "<p id=\"two\">", with: button + "<p id=\"two\">")
    try await wait("Dropping the native Button tile did not insert before Scope.") {
      self.editor.currentText == withButton
    }
    try await js(
      """
      (()=>{const b=document.querySelector('button'),t=document.querySelector('#one'),a=b.getBoundingClientRect(),r=t.getBoundingClientRect();
      const send=(s,x,y)=>b.dispatchEvent(new PointerEvent(s,{bubbles:true,cancelable:true,button:0,pointerId:1,clientX:x,clientY:y}));
      send('pointerdown',a.x+a.width/2,a.y+a.height/2);
      send('pointermove',r.x+1,r.y+r.height/2);send('pointerup',r.x+1,r.y+r.height/2);return true;})()
      """)
    let moved = original.replacingOccurrences(of: "<p id=\"one\">", with: button + "<p id=\"one\">")
    try await wait("Moving the button directly on the page did not change the flex order.") {
      self.editor.currentText == moved
    }
    editor.undo()
    try require(
      editor.currentText == withButton, "Undo failed to return the button to its original slot.")
    editor.redo()
    try save()
    try require(
      try Data(contentsOf: file) == Data(moved.utf8),
      "The saved flex markup differs from its expected bytes.")
    return
      "Checked the visible Button tile and its destination, then verified the rendered hover and drop in WebKit. Reordered by synthetic page drag, used native undo/redo, and compared saved bytes."
  }

  private func multipleLayers() async throws -> String {
    let file = directory.appendingPathComponent("Three-layers.html")
    let original = """
      <!doctype html><html><head><style>main{position:relative;min-height:250px}p{position:absolute;margin:0;width:20px}</style></head><body><main>
      <p id="a" style="left:10px;top:20px">A</p><!-- leave me -->
      <p id="b" style="left:30px;top:40px">B</p><p id="c" style="left:110px;top:60px">C</p></main></body></html>
      """
    try Data(original.utf8).write(to: file, options: .withoutOverwriting)
    enter(try Site.open(file))
    editor.mode = .design
    try await js(
      """
      (()=>{for(const [i,id] of ['a','b','c'].entries())document.getElementById(id).dispatchEvent(new MouseEvent('click',{bubbles:true,metaKey:i!==0}));return true;})()
      """)
    try await wait("Command-click did not select three siblings.") {
      self.editor.groupIDs.count == 3
    }
    let ids = editor.groupIDs
    editor.arrangeGroup("top")
    let aligned = original.replacingOccurrences(of: "top:40px", with: "top:20px")
      .replacingOccurrences(of: "top:60px", with: "top:20px")
    try await wait("Align Top did not keep the reference layer fixed.") {
      self.editor.currentText == aligned
    }
    _ = try await web()
    editor.arrangeGroup("spaceX")
    let spaced = aligned.replacingOccurrences(of: "left:30px", with: "left:60px")
    try await wait("Equal spacing did not keep both endpoints fixed.") {
      self.editor.currentText == spaced
    }
    _ = try await web()
    editor.nudge(0, 10)
    let moved = spaced.replacingOccurrences(of: "top:20px", with: "top:30px")
    try await wait("The group nudge failed.") { self.editor.currentText == moved }
    editor.undo()
    try require(
      editor.currentText == spaced && editor.groupIDs == ids,
      "One Undo failed to restore all selected layers.")
    editor.redo()
    try require(
      editor.currentText == moved && editor.groupIDs == ids, "Redo lost an edit or the selection.")
    try save()
    let reopened = try Site.open(file)
    try require(
      reopened.files[file.lastPathComponent]?.bytes == Data(moved.utf8),
      "Reopened group layout differs.")
    return
      "Aligned three layers, distributed equal gaps, moved together, checked one-step Undo/Redo and byte-compared the reopened HTML."
  }
  private func nestedLayers() async throws -> String {
    let url = directory.appendingPathComponent("Nested-layers.html")
    let html =
      "<html><body data-free-page data-design-canvas style='position:relative'><section id='panel'><div id='row' style='display:flex;padding:20px'><p>First</p></div><div id='empty'></div></section><!-- keep --><a href='#panel'>Jump</a></body></html>"
    try Data(html.utf8).write(to: url, options: .withoutOverwriting)
    enter(try Site.open(url))
    editor.dropOnPage = false
    try await inspect("div#row")
    _ = try await js(
      "(()=>{const r=document.getElementById('row').getBoundingClientRect();webBenchPaletteDrag('Button','drop',(r.right-15)/innerWidth,(r.top+r.height/2)/innerHeight,false,false);return true})()"
    )
    try await wait("The button did not land in the flex row.") {
      self.editor.inspection?.label == "button"
    }
    try require(
      try await js("document.querySelector('#row > button') !== null") as? Bool == true,
      "The button has the wrong parent.")
    let before = editor.currentText
    let button = try node("button")
    let empty = try node("div#empty")
    guard let slot = editor.slot(for: button, at: empty, zone: .inside) else {
      throw BenchError("Layers rejected the empty container.")
    }
    editor.moveLayer(button, to: slot)
    let moved = before.replacingOccurrences(of: "<button type=\"button\">Button</button>", with: "")
      .replacingOccurrences(
        of: "id='empty'>", with: "id='empty'><button type=\"button\">Button</button>")
    try require(editor.currentText == moved, "Moving the layer changed unrelated source.")
    editor.undo()
    try require(editor.currentText == before, "Undo did not restore the original tree.")
    editor.redo()
    try require(editor.currentText == moved, "Redo did not restore the new tree.")
    guard let details = editor.elements.first(where: { $0.id == "Details" }) else {
      throw BenchError("Disclosure is missing from Insert.")
    }
    editor.insertChild(details, in: try node("div#empty"))
    let final = editor.currentText
    try require(final.contains("<details open>"), "Add inside did not append the disclosure.")
    try save()
    try require(
      try Site.open(url).files[url.lastPathComponent]?.text == final,
      "The hierarchy changed on reopen.")
    return
      "Inserted a button into nested flex, moved its source subtree to an empty container, undid and redid the move, added a disclosure and reopened the saved HTML."
  }

  private func photoEditing() async throws -> String {
    let path = directory.appendingPathComponent("Photo-page.html")
    let oldURL = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
    let original =
      "<!-- keep this comment -->\r\n<img id='portrait' alt='Field instrument' src='" + oldURL
      + "'>\r\n"
    try Data(original.utf8).write(to: path, options: .withoutOverwriting)
    let photo = directory.appendingPathComponent("Instrument.tiff")
    let studio = try Resources.string("studio", "html")
    guard let start = studio.range(of: "data:image/jpeg;base64,"),
      let end = studio[start.upperBound...].firstIndex(of: "\""),
      let data = Data(base64Encoded: String(studio[start.upperBound..<end])),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let writer = CGImageDestinationCreateWithURL(
        photo as CFURL, "public.tiff" as CFString, 1, nil)
    else { throw BenchError("Cannot prepare a disposable large photograph.") }
    let options: [CFString: Any] = [
      kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1]
    ]
    CGImageDestinationAddImage(writer, image, options as CFDictionary)
    try require(CGImageDestinationFinalize(writer), "Cannot write the TIFF fixture.")
    let originalPhoto = try Data(contentsOf: photo)
    try require(
      originalPhoto.count > 2 * 1024 * 1024, "The TIFF did not exceed the single-file budget.")
    enter(try Site.open(path))
    try await inspect("img#portrait")
    guard let id = editor.selected, let token = editor.preview?.token else {
      throw BenchError("Missing photo target.")
    }
    let target = PhotoTarget(token: token, id: id, before: NSNull(), point: NSNull(), replace: true)
    editor.importPhotoFile(photo, target: target)
    guard editor.photoEditor?.resizeOffer == true else {
      throw BenchError("The large photo did not offer resizing.")
    }
    editor.photoEditor = nil
    try require(editor.currentText == original, "Cancelling the import changed the page.")
    editor.importPhotoFile(photo, target: target)
    guard let job = editor.photoEditor else { throw BenchError("Photo import did not reopen.") }
    defer { editor.photoEditor = nil }
    var recipe = PhotoRecipe()
    recipe.crop = .centered(ratio: 1, imageWidth: image.width, imageHeight: image.height)
    recipe.edge = 128
    recipe.turns = 1
    recipe.filter = .mono
    recipe.border = .print
    recipe.borderRGB = 0x285544
    let result = try PhotoRender.render(job, recipe: recipe, codec: .png, quality: 0.84)
    let bitmap = try IconBitmap.load(result.bytes, preferred: 128, preserveSize: true)
    try require(
      bitmap.pixels[0] == 0x2855_44ff && result.image.width == 128 && result.image.height == 128,
      "The crop or frame differs from the requested output.")
    let center = bitmap.pixels[64 * 128 + 64]
    try require(
      center >> 24 == (center >> 16) & 255 && center >> 24 == (center >> 8) & 255,
      "The center of the photo is not monochrome.")
    try require(editor.applyPhoto(result, to: job), "The photo could not be applied.")
    editor.photoEditor = nil
    let expected = original.replacingOccurrences(
      of: oldURL, with: "data:image/png;base64," + result.bytes.base64EncodedString())
    try require(editor.currentText == expected, "The photo patch changed surrounding HTML.")
    editor.undo()
    try require(editor.currentText == original, "Undo did not restore the exact source.")
    editor.redo()
    try save()
    let reopened = try Site.open(path)
    let photoAfterSave = try Data(contentsOf: photo)
    try require(
      reopened.files[path.lastPathComponent]?.text == expected && photoAfterSave == originalPhoto,
      "The saved page or original image changed unexpectedly.")
    enter(reopened)
    try await inspect("img#portrait")
    editor.editSelectedPhoto()
    try require(
      editor.photoEditor?.input.byteCount == result.bytes.count,
      "The embedded photo could not be reopened for editing.")
    return
      "Resized a local TIFF into an embedded PNG, cropped, rotated, filtered and framed it. Verified image pixels, unchanged surrounding HTML, cancel, undo, redo, save and reopen."
  }

  private func pageAppearance() async throws -> String {
    let site = try sample()
    enter(site)
    try await inspect("h1")
    editor.paintBackground(pageWide: true, color: "#173F35", keepImage: false)
    try await wait("Page color was not committed.") { self.editor.currentText.contains("#173F35") }
    _ = try await web()
    try require(
      try await js("getComputedStyle(document.documentElement).backgroundColor") as? String
        == "rgb(23, 63, 53)", "Wrong document background.")
    try await inspect("h1")
    editor.paintBackground(pageWide: false, color: "#FFCC22", keepImage: false)
    try await wait("Element color was not committed.") {
      self.editor.currentText.contains("#FFCC22")
    }
    _ = try await web()
    try require(
      try await js("getComputedStyle(document.querySelector('h1')).backgroundColor") as? String
        == "rgb(255, 204, 34)", "Wrong element background.")
    let colored = editor.currentText
    let mark = try IconBitmap.initials("GS", size: 32, color: 0x2553_40FF)
    let empty = IconLinks(base: "", links: [])
    try editor.setFavicon(mark, link: -1, edit: FaviconEdit(page: editor.page, metadata: empty))
    let exported = directory.appendingPathComponent("Published-Appearance")
    try currentSite().exportWebsite(to: exported, entry: editor.page)
    guard let engine = editor.engine else { throw BenchError("Missing source engine.") }
    let meta = try engine.call("icons", [editor.currentText], as: IconLinks.self)
    guard let link = meta.links.first, let bytes = try editor.existingIcon(link, metadata: meta)
    else { throw BenchError("Missing exported icon link.") }
    try require(
      try IconBitmap.load(bytes, preferred: 32, preserveSize: true) == mark,
      "Imported PNG changed opaque pixels or orientation.")
    var revised = mark
    revised.pixels[0] = 0xF055_22FF
    try editor.setFavicon(
      revised, link: link.id, edit: FaviconEdit(page: editor.page, metadata: meta))
    editor.undo()
    editor.undo()
    try require(editor.currentText == colored, "Undo did not restore the original page head.")
    editor.redo()
    editor.redo()
    let reopened = try Site.open(exported)
    try require(
      reopened.files[link.href]?.bytes == bytes,
      "Folder snapshot does not contain its linked favicon.")
    return
      "Set page and element colors in WebKit, drew and decoded an icon, edited it, exercised undo/redo and reopened a folder snapshot."
  }

  private func freeCanvasStudio() async throws -> String {
    let url = directory.appendingPathComponent("Free-canvas.html")
    let original = try Resources.string("canvas-page", "html")
    try Data(original.utf8).write(to: url, options: .withoutOverwriting)
    enter(try Site.open(url))
    editor.mode = .design
    editor.useDevice("Custom", 720, 480)
    editor.snap = false
    editor.zoom = "100%"
    let canvas = try await web()
    _ = try await canvas.checkValue(
      "window.webBenchPaletteDrag('Button','drop',80/innerWidth,60/innerHeight,false,false)",
      in: .defaultClient)
    try await wait("The blank paper did not accept a part.") {
      self.editor.inspection?.label == "button"
    }
    let id = try node("button")
    let beforeResize = editor.currentText
    let view = try await web()
    guard let window = view.window else { throw BenchError("The canvas has no window.") }
    let location = try await js(
      "(()=>{let r=document.querySelector('button').getBoundingClientRect();return [r.right/innerWidth,r.bottom/innerHeight,r.width,r.height]})()"
    )
    guard let xy = location as? [Double], xy.count == 4 else {
      throw BenchError("Missing resize grip coordinates.")
    }
    let start = view.convert(
      NSPoint(
        x: xy[0] * view.bounds.width, y: (view.isFlipped ? xy[1] : 1 - xy[1]) * view.bounds.height),
      to: nil)
    let end = NSPoint(x: start.x + 40, y: start.y - 24)
    func mouse(_ type: NSEvent.EventType, at p: NSPoint) throws {
      guard
        let event = NSEvent.mouseEvent(
          with: type, location: p, modifierFlags: [.option],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
      else { throw BenchError("Could not create a test pointer.") }
      window.sendEvent(event)
    }
    try mouse(.leftMouseDown, at: start)
    try mouse(.leftMouseDragged, at: end)
    var grew = false
    for _ in 0..<80 {
      let width =
        try await js("document.querySelector('button').getBoundingClientRect().width") as? Double
        ?? 0
      if abs(width - xy[2] - 40) < 2 {
        grew = true
        break
      }
      try await Task.sleep(nanoseconds: 25_000_000)
    }
    try mouse(.leftMouseUp, at: end)
    try require(grew, "The rendered object did not resize while the mouse button was down.")
    try await wait("Release failed to write the resize.") {
      self.editor.currentText != beforeResize && self.editor.inspection?.id == id
    }
    let resized = editor.currentText
    editor.undo()
    try require(editor.currentText == beforeResize, "One Undo did not restore the pre-drag source.")
    editor.redo()
    try require(editor.currentText == resized, "Redo failed to reapply both dimensions.")
    try await inspect("button")
    editor.styleSelection("font-family", "Georgia, serif")
    try await wait("The typeface did not reach WebKit.") {
      self.editor.inspection?.fontFamily?.contains("Georgia") == true
    }
    editor.styleSelection("color", "#a43529")
    try await wait("The text color did not reach WebKit.") {
      self.editor.inspection?.ink == "rgb(164, 53, 41)"
    }
    let styled = editor.currentText
    for (name, w, h) in [("Phone", 390, 844), ("Tablet", 820, 1180), ("Desktop", 1280, 800)] {
      editor.useDevice(name, Double(w), Double(h))
      var ok = false
      for _ in 0..<80 {
        if let size = try await js("[innerWidth,innerHeight]") as? [Int], size == [w, h] {
          ok = true
          break
        }
        try await Task.sleep(nanoseconds: 30_000_000)
      }
      try require(ok, "The actual CSS viewport differs from the chosen " + name + " size.")
    }
    try require(editor.currentText == styled, "Device preview changed the source.")
    editor.useDevice("Phone", 390, 844)
    try await viewport(390)
    editor.devicePlacement = true
    editor.designer?.sync()
    editor.requestFrame(["left": 24])
    try await wait("The phone arrangement did not produce a media rule.") {
      self.editor.currentText.contains("left: 24px !important")
    }
    _ = try await web()
    let phone = try await js("getComputedStyle(document.querySelector('button')).left") as? String
    try require(phone == "24px", "Phone placement did not win in WebKit.")
    editor.useDevice("Desktop", 1280, 800)
    try await viewport(1280)
    let desktop = try await js("getComputedStyle(document.querySelector('button')).left") as? String
    try require(desktop == "80px", "The phone edit leaked into the desktop layout.")
    let folder = directory.appendingPathComponent("Published-Studio")
    try currentSite().exportWebsite(to: folder, entry: editor.page)
    let published = try Site.open(folder)
    try require(
      published.files["index.html"]?.bytes == Data(editor.currentText.utf8),
      "Exported HTML differs from the draft.")
    try require(
      try Data(contentsOf: url) == Data(original.utf8), "Snapshot export modified the working file."
    )
    return
      "Placed and visibly resized a button, exercised undo/redo, changed its typeface and color, measured three device viewports, applied a phone-only position and reopened the exported snapshot."
  }

  private func responsiveEdit() async throws -> String {
    let s = try sample()
    enter(s)
    let html = editor.currentText
    let css = s.files["css/bench.css"]?.text ?? ""
    let expected = html.replacingOccurrences(
      of: "</button></div>", with: "</button><button type=\"button\">Button</button></div>")
    try await js(
      """
      (()=>{const el=document.querySelector('.actions'), rect=el.getBoundingClientRect(), transfer=new DataTransfer();
      transfer.setData('text/plain','WebBench:Button');
      for(const type of ['dragover','drop']) el.dispatchEvent(new DragEvent(type,{bubbles:true,cancelable:true,
        clientX:rect.right-3,clientY:rect.top+rect.height/2,dataTransfer:transfer})); return true;})()
      """)
    try await wait("The flex drop did not create the expected insertion.") {
      self.editor.currentText == expected
    }
    try await inspect("button")
    let query = "getComputedStyle(document.querySelector('.actions button:last-child')).marginTop"
    try await viewport(900)
    guard let desktopBefore = try await js(query) as? String, !desktopBefore.isEmpty,
      desktopBefore != "19px"
    else {
      throw BenchError("No distinct desktop spacing baseline.")
    }
    editor.applyStyle(
      value: "19px", target: "Element", scope: "Breakpoint", breakpoint: 600,
      external: "css/bench.css")
    let styled = try currentSite()
    let expectedCSS =
      css + "\n@media (max-width: 600px) {\n  #wb-button-1 { margin-top: 19px; }\n}\n"
    try require(styled.files["css/bench.css"]?.text == expectedCSS, "Unexpected mobile CSS diff.")
    let styledHTML = expected.replacingOccurrences(
      of: "<button type=\"button\">Button",
      with: "<button id=\"wb-button-1\" type=\"button\">Button")
    try require(styled.files["index.html"]?.text == styledHTML, "Unexpected element ID diff.")
    try await viewport(380)
    try require(try await js(query) as? String == "19px", "380 px spacing did not equal 19px.")
    try await viewport(900)
    try require(
      try await js(query) as? String == desktopBefore, "Mobile spacing affected the desktop layout."
    )
    editor.undo()
    try require(
      editor.currentText == expected && editor.site?.files["css/bench.css"]?.text == css,
      "Undo did not restore both buffers.")
    editor.undo()
    try require(editor.currentText == html, "Second Undo did not remove the button.")
    try require(
      try await js("document.querySelectorAll('.actions button').length") as? Int == 2,
      "Undo did not update the canvas.")
    try await wait("Undo did not restore the displayed code.") {
      self.sourceView(in: self.host)?.string == html
    }
    editor.redo()
    editor.redo()
    try await wait("Redo did not restore the displayed code.") {
      self.sourceView(in: self.host)?.string == styledHTML
    }
    try require(
      editor.currentText == styledHTML && editor.site?.files["css/bench.css"]?.text == expectedCSS,
      "Redo did not restore both buffers.")
    try save()
    enter(try Site.open(s.root))
    try await viewport(380)
    try require(
      try await js(query) as? String == "19px", "Saved mobile spacing failed after reopen.")
    try await js("document.querySelector('.control').click(); true")
    try await wait("The shared control rule did not appear.") {
      self.editor.inspection?.label == "button.control"
    }
    guard let i = editor.inspection, i.rules.indices.contains(i.winner) else {
      throw BenchError("The mobile winner could not be identified.")
    }
    let r = i.rules[i.winner]
    try require(
      r.selector == ".control" && r.count == 2 && r.media.contains("600px")
        && editor.localPath(r.source) == "css/bench.css",
      "Incorrect mobile rule attribution or affected count.")
    return
      "A synthetic WebKit drop inserted a button. Computed margins, two-buffer native Undo/Redo, save and reopen matched."
  }
  private func calculatedInteraction() async throws -> String {
    let url = directory.appendingPathComponent("DC Power Meter.html")
    let original = try Resources.string("Power-meter", "html", in: "Fixtures")
    try Data(original.utf8).write(to: url, options: .withoutOverwriting)
    enter(try Site.open(url))
    editor.select(try node("button#test"))
    editor.openInteractions()
    defer { editor.workflow = nil; editor.setRun(false) }
    guard let draft = editor.workflow, draft.existing, draft.conditional,
      draft.steps.first?.kind == .calculate, draft.otherwise.first?.kind == .text
    else { throw BenchError("The calculation and its two branches did not reopen.") }
    let form = try node("form#meter")
    let picked = draft.pick(try node("button#test"), for: .condition)
    try require(picked == form, "The condition picker did not resolve the surrounding form.")
    draft.steps[0].digits = 3
    editor.finishInteraction(draft)
    try require(editor.workflow == nil, draft.issue)
    let edited = editor.currentText
    try require(edited != original, "The precision change did not reach source.")
    editor.undo()
    try require(editor.currentText == original, "Undo changed unrelated markup.")
    editor.redo()
    try require(editor.currentText == edited, "Redo did not restore the workflow.")
    try save()
    enter(try Site.open(url))
    try require(editor.currentText == edited, "The reopened HTML differs from the working page.")
    editor.setRun(true)
    let ready = try await js("document.getElementById('test').click(); document.getElementById('power').value")
    try require(ready as? String == "3.000 W", "The valid branch did not display 3.000 W.")
    let invalid = try await js("document.getElementById('amps').value=''; document.getElementById('test').click(); document.getElementById('power').value")
    try require(invalid as? String == "Enter a voltage and a current.", "The invalid branch did not run.")
    try require(editor.site?.dirtyPaths.isEmpty == true, "Runtime calculation dirtied the page.")
    return "Edited decimal precision, undid/redid the source edit, saved, reopened, and ran the valid and invalid branches in WebKit."
  }

  private func fieldInstrument() async throws -> String {
    let output = directory.appendingPathComponent("Temperature.html")
    try Data(Resources.string("blank", "html").utf8).write(to: output, options: .withoutOverwriting)
    enter(try Site.open(output))
    for (item, tag, id) in [
      ("Number input", "input", "reading"), ("Button", "button", "convert"),
      ("Output", "output", "result"),
    ] {
      editor.mutate(["kind": "insert", "item": item], id: try node("section.layout"))
      editor.mutate(["kind": "attr", "key": "id", "value": id], id: try node(tag))
    }
    editor.mutate(["kind": "text", "value": "Convert"], id: try node("button#convert"))
    try await inspect("button#convert")
    editor.handler()
    let placeholder = "// Write the click action here."
    try require(
      editor.currentText.contains(placeholder), "Handler creation did not provide a source range.")
    editor.editSource(
      editor.currentText.replacingOccurrences(
        of: placeholder,
        with:
          "document.getElementById('result').textContent = String(document.getElementById('reading').valueAsNumber * 9 / 5 + 32);"
      ))
    try save()
    enter(try Site.open(output))
    editor.setRun(true)
    try require(
      try await js("Boolean(window.webkit?.messageHandlers?.design)") as? Bool == false,
      "Run exposed the design message handler.")
    let result = try await js(
      "document.querySelector('#reading').value='25'; document.querySelector('#convert').click(); document.querySelector('#result').textContent"
    )
    try require(result as? String == "77", "Saved conversion did not return 77.")
    try require(editor.site?.dirtyPaths.isEmpty == true, "Runtime activity dirtied source.")
    self.instrument = output
    return
      "Created and wired input, button and output. Reopened Temperature.html returned 77 for 25 °C in isolated Run. Safari is recorded separately."
  }
  private func workbench() async throws -> String {
    let s = try sample()
    enter(s)
    let original = editor.currentText
    try await inspect("div#meter")
    try require(editor.inspection?.canMove == true, "The positioned object was not movable.")
    editor.nudge(35, 18)
    try save()
    let opened = try Site.open(s.root)
    let expected = original.replacingOccurrences(
      of: "left: 24px; top: 32px", with: "left: 59px; top: 50px")
    try require(
      opened.files["index.html"]?.text == expected, "Moving the meter changed unrelated HTML.")
    try require(
      opened.files["js/bench.js"]?.bytes == s.files["js/bench.js"]?.bytes,
      "The original script changed.")
    enter(opened)
    editor.setRun(true)
    try require(
      try await js("getComputedStyle(document.querySelector('#meter')).left") as? String == "59px",
      "Saved meter coordinate failed.")
    let moved = try await js(
      """
      (()=>{const el=document.querySelector('#meter');el.dispatchEvent(new PointerEvent('pointerdown',{button:0,clientX:1,clientY:2}));
      window.dispatchEvent(new PointerEvent('pointermove',{buttons:1,clientX:11,clientY:13}));
      window.dispatchEvent(new PointerEvent('pointerup'));
      for(const key of 'ODIN')window.dispatchEvent(new KeyboardEvent('keydown',{key}));
      return el.style.left==='69px' && el.style.top==='61px' && document.querySelector('#signal strong')?.textContent.includes('⚡');})()
      """)
    try require(moved as? Bool == true, "Original pointer or ODIN handler failed.")
    let current = try await web()
    // A new pointer press clears the fixture's drag suppression, just as a second click does.
    try await js(
      "document.querySelector('#meter').dispatchEvent(new PointerEvent('pointerdown',{button:0})); document.querySelector('#meter a').click(); true"
    )
    try await wait("The meter link did not navigate to notes.html.") {
      current.url?.lastPathComponent == "notes.html" && !current.isLoading
    }
    let heading = try await js("document.querySelector('h1').textContent")
    try require(heading as? String == "Meter notes", "Meter link opened the wrong page.")
    editor.setRun(false)
    try require(
      editor.currentText == expected && !editor.changed, "The runtime move or badge entered source."
    )
    return
      "The editor moved the meter by (+35,+18). The original drag handler, notes link and ODIN badge worked in WKWebView."
  }
  private func conflict() async throws -> String {
    let s = try sample()
    enter(s)
    let path = "css/bench.css"
    let url = s.root.appendingPathComponent(path)
    let old = try Data(contentsOf: url)
    let draft = old + Data("\n/* WebBench */".utf8)
    let external = old + Data("\n/* external */".utf8)
    let html = editor.currentText
    editor.editSource(html + "\n<!-- pending -->")
    editor.chooseFile(path)
    editor.editSource(String(decoding: draft, as: UTF8.self))
    try external.write(to: url, options: .atomic)
    do {
      try save()
      throw BenchError("Save failed to surface the external edit.")
    } catch let c as Conflict {
      try require(c.path == path && c.disk == external, "The conflict identified the wrong file.")
      for (prefix, bytes) in [("External", external), ("Baseline", old), ("WebBench", draft)] {
        let recovered = try Data(
          contentsOf: c.recovery.appendingPathComponent(prefix + "-bench.css"))
        try require(recovered == bytes, "Incorrect " + prefix + " recovery bytes.")
      }
      try require(
        try Data(contentsOf: s.root.appendingPathComponent("index.html")) == Data(html.utf8),
        "Preflight allowed a partial overwrite.")
      editor.useExternal(c)
      try save()
      let result = try Site.open(s.root)
      try require(
        result.files[path]?.bytes == external
          && result.files["index.html"]?.text == html + "\n<!-- pending -->",
        "Save after conflict resolution lost an edit.")
    }
    return
      "All three recovery copies matched. Accepting the disk stylesheet retained the pending HTML change and retry succeeded."
  }
}

@MainActor
final class SampleCheckWindow: NSObject, NSWindowDelegate {
  private let checks = SampleChecks()
  private var window: NSWindow?
  private var task: Task<Void, Never>?
  var isRunning: Bool { window?.isVisible == true && !checks.finished }
  func bringForward() { window?.makeKeyAndOrderFront(nil) }
  func start() {
    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    w.title = "WebBench · Sample checks"
    w.isReleasedWhenClosed = false
    w.minSize = NSSize(width: 850, height: 500)
    let host = NSHostingView(rootView: CheckView(checks: checks))
    w.contentView = host
    w.delegate = self
    window = w
    checks.host = host
    w.center()
    bringForward()
    task = Task { await checks.run() }
  }
  func close() { window?.close() }
  func windowWillClose(_ notification: Notification) { task?.cancel() }
}
private struct CheckView: View {
  @ObservedObject var checks: SampleChecks
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        if !checks.finished { ProgressView().controlSize(.small) }
        Text(checks.activity).font(.headline)
        Spacer()
        if checks.finished {
          Button("Show report in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([checks.reportURL])
          }.disabled(!FileManager.default.fileExists(atPath: checks.reportURL.path))
        }
      }
      if checks.finished {
        ScrollView {
          Text(checks.report).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if checks.instrument != nil {
          Divider()
          Text("Safari check").font(.headline)
          Text("Open the saved instrument, enter 25, and click Convert. The expected result is 77.")
          HStack {
            Button("Open instrument in Safari") { checks.openSafari() }
            if checks.safariOpened {
              Button("I saw 77") { checks.recordSafari(returned77: true) }
              Button("I saw a different result") { checks.recordSafari(returned77: false) }
            }
          }
        }
      } else {
        Text("Checking bundled fixtures in a separate editor. Close this window to stop.")
          .foregroundStyle(.secondary)
        WorkspaceView(m: checks.editor)
      }
      if !checks.reportError.isEmpty { Text(checks.reportError).foregroundStyle(.red) }
    }.padding(16)
  }
}
