import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Mode: String, CaseIterable {
  case design = "Design"
  case split = "Split"
  case code = "Code"
}
struct PreviewState {
  let token: String, marker: String, page: String, html: String, files: [String: SourceFile],
    nodes: [ElementRow], run: Bool, writing: Bool, caret: Int?, writeTarget: [Int]?,
    scroll: [Double]?
  var assetRoot: URL? = nil
  var linkedAssets: Set<String> = []
}
final class Session: ObservableObject {
  @Published var site: Site?
  @Published var page = ""
  @Published var file = ""
  private var designPanel = "Insert"
  @Published var mode = Mode.design {
    didSet {
      if mode == .code && oldValue != .code {
        designPanel = sidebarTab
        sidebarTab = "Files"
        insertTool = ""
        groupIDs = []
      }
      if oldValue == .code && mode != .code {
        if sidebarTab == "Files" { sidebarTab = designPanel }
        if site != nil { render() }
      }
    }
  }
  struct WritingFormat: Equatable {
    var bold = false, italic = false, list = "", block = "", href = ""
    var fontFamily = "", fontSize = "", ink = "", fill = "", hasImage = false
    var title: String {
      if block == "p" { return "Paragraph" }
      if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(block) {
        return "Heading " + block.dropFirst()
      }
      return "Paragraph style"
    }
  }
  @Published var writingFormat = WritingFormat()
  @Published var writing = false
  @Published var snap = true
  @Published var gridVisible = true
  @Published var dropOnPage = true
  let elements: [InsertElement]
  let layerParents: [String: [String]]
  var paletteGroups: [String] {
    elements.reduce(into: []) { if !$0.contains($1.group) { $0.append($1.group) } }
  }
  @Published var insertTool = ""
  @Published var pageImages = [String: NSImage]()
  var nextScroll: [Double]?
  var resumeCanvasFocus = false
  func addPageImage(_ image: NSImage, path: String) {
    if pageImages.count >= 24, pageImages[path] == nil, let evict = pageImages.keys.sorted().first {
      pageImages.removeValue(forKey: evict)
    }
    pageImages[path] = image
  }
  @Published var inspectorTab = "Style"
  @Published var zoom = "Fit"
  weak var designer: Canvas.Coordinator?
  private var writeTarget: [Int]?
  func startText(_ id: Int, offset: Int) {
    guard safeToEdit, nodes.indices.contains(id), offset >= 0 else { return }
    select(id)
    writeTarget = [id, offset]
    setWriting(true)
  }
  func arm(_ item: String) {
    insertTool = insertTool == item ? "" : item
    status =
      insertTool.isEmpty
      ? "Select a layer." : "Click the page to place " + item.lowercased() + ". Escape cancels."
  }
  func requestFrame(_ values: [String: Int]) {
    guard safeToEdit, let id = inspection?.id, designer?.state.token == preview?.token else {
      return
    }
    designer?.frame(id, values: values)
  }
  weak var writer: Canvas.Coordinator?
  private var freshBlank: URL?
  private var lastTyping: (caret: Int, time: TimeInterval, token: String)?
  var writingCaret: Int?
  func setWriting(_ enabled: Bool) {
    guard writing != enabled else { return }
    insertTool = ""
    groupIDs = []
    writing = enabled
    writingCaret = nil
    refresh()
    status = enabled ? "Click in the page to write." : "Select an element to inspect or move it."
  }
  func afterWriting(onFailure: (() -> Void)? = nil, _ action: @escaping () -> Void) {
    if let writer, writing, !running, mode != .code, writer.state.token == preview?.token {
      writer.afterWriting(action, onFailure: onFailure)
    } else {
      action()
    }
  }
  func writeCommand(_ kind: String, _ value: String = "") {
    guard let writer, writer.state.token == preview?.token, safeToEdit else { return }
    writer.command(kind, value)
  }
  func writingLink() {
    guard safeToEdit else { return }
    let alert = NSAlert()
    alert.messageText = "Link address"
    alert.informativeText = "Enter a URL, a relative page path, or a #fragment."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
    field.stringValue = writingFormat.href
    field.placeholderString = "https:// or page.html"
    alert.accessoryView = field
    alert.addButton(withTitle: "Insert Link")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    if alert.runModal() == .alertFirstButtonReturn { writeCommand("link", field.stringValue) }
  }
  @Published var running = false
  @Published var busy = false
  @Published var nodes = [ElementRow]()
  @Published var groupIDs = [Int]()
  var selectedIDs: [Int] { groupIDs.isEmpty ? selected.map { [$0] } ?? [] : groupIDs }
  @Published var selected: Int?
  @Published var inspection: Inspection?
  @Published var status = "Open a page or site folder."
  @Published var preview: PreviewState?
  @Published var sourceIssue = ""
  @Published var property = "margin-top"
  @Published var width = 1280.0
  @Published var devicePlacement = false
  var hasFreePage: Bool { nodes.contains { $0.freeCanvas == true } }
  var targetsPage: Bool { hasFreePage && dropOnPage }
  var supportsDevicePlacement: Bool {
    hasFreePage && nodes.contains { $0.label == "style#webbench-layout" }
  }
  var band: String { width <= 600 ? "phone" : width <= 1024 ? "tablet" : "desktop" }
  @Published var deviceHeight = 800.0
  @Published var device = "Desktop"
  @Published var showSize = false
  func useDevice(_ label: String, _ w: Double, _ h: Double) {
    device = label
    width = w
    deviceHeight = h
  }
  func styleSelection(_ key: String, _ value: String) {
    guard safeToEdit, !running, mode != .code, groupIDs.isEmpty else { return }
    if writing {
      writeCommand(key, value)
      return
    }
    guard let id = selected, inspection?.id == id else { return }
    mutate(["kind": "inline", "prop": key, "value": value], id: id, name: "Change " + key)
  }
  func openSizeControls() {
    afterWriting {
      self.setWriting(false)
      self.showSize = true
    }
  }
  func newStudioDraft(_ template: String = "canvas-page") {
    guard mayLeave() else { return }
    do {
      let isInteractionExample = ["Signal-check", "Power-meter", "Device-workbench"].contains(template)
      let data = Data(try Resources.string(template, "html", in: isInteractionExample ? "Fixtures" : nil).utf8)
      let dir = Self.supportDirectory.appendingPathComponent("Drafts").appendingPathComponent(
        UUID().uuidString)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let url = dir.appendingPathComponent("index.html")
      try data.write(to: url, options: .withoutOverwriting)
      mode = .design
      sidebarTab = "Insert"
      zoom = "Fit"
      useDevice("Desktop", 1280, 800)
      use(try Site.open(url))
      if isInteractionExample, let test = nodes.first(where: { $0.label == "button#test" }) {
        select(test.id)
        openInteractions()
      } else {
        status = "Drag a part onto the page. Double-click its text to type."
      }
    } catch { alert(error.localizedDescription) }
  }
  func exportSnapshot(folder: Bool) {
    guard !busy, let snapshot = site, let current = snapshot.files[page] else { return }
    let entry = page
    let panel = NSSavePanel()
    panel.title = folder ? "Export website folder" : "Export HTML snapshot"
    panel.prompt = "Export"
    if snapshot.standalone {
      panel.message =
        "Embedded images and scripts travel with this page. For local linked files, open the site folder before exporting."
    } else if !folder {
      panel.message =
        "This saves the current HTML. Use Website folder to include the site's local assets."
    }
    panel.nameFieldStringValue = folder ? "Website" : "index.html"
    if !folder { panel.allowedContentTypes = [.html] }
    panel.directoryURL =
      FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let dest = url.resolvingSymlinksInPath().standardizedFileURL
    if snapshot.files.keys.contains(where: {
      snapshot.root.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL == dest
    }) {
      alert("Choose a separate destination for your snapshot.")
      return
    }
    busy = true
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result {
        if folder {
          try snapshot.exportWebsite(to: url, entry: entry)
        } else {
          try current.bytes.write(to: url, options: .atomic)
        }
      }
      DispatchQueue.main.async {
        self.busy = false
        switch result {
        case .success:
          self.status = "Exported " + url.lastPathComponent
          NSWorkspace.shared.activateFileViewerSelecting([
            folder ? url.appendingPathComponent("index.html") : url
          ])
        case .failure(let e): self.alert(e.localizedDescription)
        }
      }
    }
  }
  @Published var freePlacement = false
  @Published var logs = [String]()
  @Published var codeRange = NSRange(location: 0, length: 0)
  @Published var revealID = UUID()
  @Published var reviewTitle = "Source changes"
  @Published var impactRequest: String?
  @Published var diffText: String?
  @Published var sidebarTab = "Insert"
  @Published var showInspector =
    (UserDefaults.standard.object(forKey: "inspectorVisible") as? Bool) ?? true
  func toggleInspector() {
    guard site != nil, !running else { return }
    if mode == .code {
      mode = .split
      showInspector = true
    } else {
      showInspector.toggle()
    }
    UserDefaults.standard.set(showInspector, forKey: "inspectorVisible")
  }
  @Published var paperColor = ""
  @Published var paperHasImage = false
  @Published var workflow: InteractionDraft?
  @Published var snippetEditor: SnippetDraft?
  @Published var photoEditor: PhotoJob?
  @Published var iconEditor: FaviconEdit?
  func paintBackground(pageWide: Bool, color: String, keepImage: Bool) {
    afterWriting {
      let canvas = self.writing ? self.writer : self.designer
      guard self.safeToEdit, let canvas, canvas.state.token == self.preview?.token else { return }
      guard pageWide || self.groupIDs.isEmpty && self.selected != nil else { return }
      canvas.paint(
        pageWide ? "page" : "element", id: self.selected ?? -1, color: color, keepImage: keepImage)
    }
  }
  func receivePaint(_ message: [String: Any]) {
    guard safeToEdit, let engine, let file = site?.files[page], let src = file.text,
      let scope = message["scope"] as? String, let id = message["id"] as? Int,
      let parts = message["parts"] as? [[String: Any]],
      scope == "page"
        || (scope == "element" && id == selected && parts.allSatisfy({ $0["id"] as? Int == id }))
    else { return }
    if parts.isEmpty {
      status = "That background is already applied."
      return
    }
    do {
      let result = try engine.call(
        "backgrounds", [src, scope, parts, selected ?? -1], as: EditResult.self)
      change(
        [Change(path: page, bytes: try file.encoded(result.text))],
        scope == "page" ? "Page background" : "Element background",
        focus: selected == nil ? nil : result.focus)
    } catch { codeFallback(error.localizedDescription, id: selected) }
  }
  let history = UndoManager()
  let engine: Engine?
  private var timer: Timer?, pendingFocus: Int?, revision = 0
  var previewRevision = -1
  init() {
    do { engine = try Engine() } catch {
      engine = nil
      status = error.localizedDescription
    }
    elements = (try? engine?.call("catalog", [], as: [InsertElement].self)) ?? []
    layerParents = (try? engine?.call("parentRules", [], as: [String: [String]].self)) ?? [:]
    history.groupsByEvent = false
    history.levelsOfUndo = 120
  }
  var layers: [ElementRow] {
    let excluded = Set([
      "html", "head", "meta", "script", "style", "link", "title", "base", "noscript", "template",
    ])
    var hidden = Set<Int>()
    var result = [ElementRow]()
    for row in nodes {
      if row.tag == "html" { continue }
      if excluded.contains(row.tag) || hidden.contains(row.parent) {
        hidden.insert(row.id)
      } else {
        result.append(row)
      }
    }
    return result
  }
  var currentText: String { site?.files[file]?.text ?? "" }
  var changed: Bool { !(site?.dirtyPaths.isEmpty ?? true) }
  var safeToEdit: Bool { !busy && !running && previewRevision == revision && sourceIssue.isEmpty }
  func alert(_ msg: String) {
    status = msg
    let a = NSAlert()
    a.messageText = "WebBench"
    a.informativeText = msg
    a.runModal()
  }
  func mayLeave() -> Bool {
    if busy {
      NSSound.beep()
      return false
    }
    guard discardInteractionEdits() else { return false }
    guard changed else { return true }
    let a = NSAlert()
    a.messageText = "Keep your WebBench changes?"
    a.informativeText = "The project contains unsaved edits."
    a.addButton(withTitle: "Save")
    a.addButton(withTitle: "Cancel")
    a.addButton(withTitle: "Discard")
    switch a.runModal() {
    case .alertFirstButtonReturn: return saveSync()
    case .alertThirdButtonReturn: return true
    default: return false
    }
  }
  func openPanel() {
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = true
    p.allowsMultipleSelection = false
    p.prompt = "Open in WebBench"
    if p.runModal() == .OK, let u = p.url { open(u) }
  }
  func open(_ u: URL) {
    load { try Site.open(u) }
  }
  static var supportDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Green Shoe Garage/WebBench")
  }
  static func sampleSource() throws -> URL {
    guard let fixtures = Bundle.main.url(forResource: "Fixtures", withExtension: nil) else {
      throw BenchError("The bundled fixtures are missing. Re-extract WebBench.")
    }
    return fixtures.appendingPathComponent("Site")
  }
  func openSample() {
    load {
      try Site.copySample(
        from: Self.sampleSource(), into: Self.supportDirectory.appendingPathComponent("Samples"))
    }
  }
  func tryCanvas() {
    mode = .design
    sidebarTab = "Insert"
    load {
      let dir = Self.supportDirectory.appendingPathComponent("Samples").appendingPathComponent(
        UUID().uuidString)
      let html = try Resources.string("board", "html")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let url = dir.appendingPathComponent("Practice canvas.html")
      try Data(html.utf8).write(to: url, options: .withoutOverwriting)
      return try Site.open(url)
    }
  }
  func showProject() {
    guard let site else { return }
    NSWorkspace.shared.activateFileViewerSelecting([
      site.standalone ? site.root.appendingPathComponent(page) : site.root
    ])
  }
  private func load(_ read: @escaping () throws -> Site) {
    guard mayLeave() else { return }
    busy = true
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result { try read() }
      DispatchQueue.main.async {
        self.busy = false
        switch result {
        case .success(let site): self.use(site)
        case .failure(let error): self.alert(error.localizedDescription)
        }
      }
    }
  }
  func use(_ site: Site) {
    timer?.invalidate()
    workflow = nil
    self.site = site
    devicePlacement = false
    nextScroll = nil
    resumeCanvasFocus = false
    pageImages.removeAll()
    history.removeAllActions()
    logs = []
    impactRequest = nil
    diffText = nil
    let pages = site.pages.filter { site.files[$0]?.text != nil }
    guard let first = pages.first else { return }
    let name = pages.contains("index.html") ? "index.html" : first
    let focusBlank =
      freshBlank?.standardizedFileURL == site.root.appendingPathComponent(name).standardizedFileURL
    freshBlank = nil
    writing = focusBlank
    if focusBlank { mode = .design }
    choosePage(name, focusBlank: focusBlank)
    status =
      writing
      ? "Type on the page. Escape finishes text editing."
      : "Drag from Insert to add an element. Drag an element to move it. Double-click text to type."
  }
  func newFolder() {
    let panel = NSSavePanel()
    panel.title = "Create a site folder"
    panel.nameFieldStringValue = "Website"
    panel.prompt = "Create"
    guard !busy, panel.runModal() == .OK, let url = panel.url, mayLeave() else { return }
    do {
      try Site.createFolder(at: url, blankPage: Resources.string("blank", "html"))
      site = nil
      open(url)
    } catch { alert(error.localizedDescription) }
  }
  func new(_ template: String) {
    guard !busy else { return }
    let p = NSSavePanel()
    p.allowedContentTypes = [.html]
    p.nameFieldStringValue = template == "instrument" ? "field-instrument.html" : "index.html"
    guard p.runModal() == .OK, let url = p.url, mayLeave() else { return }
    do {
      let text = try Resources.string(template, "html")
      try Data(text.utf8).write(to: url, options: .atomic)
      // Discard was deliberate or save completed. Opening may now proceed without a second prompt.
      site = nil
      if template == "board" {
        writing = false
        mode = .design
        sidebarTab = "Insert"
        inspectorTab = "Arrange"
      }
      freshBlank = template == "blank" ? url : nil
      open(url)
    } catch { alert(error.localizedDescription) }
  }
  func choosePage(_ name: String, focusBlank: Bool = false) {
    guard site?.files[name]?.text != nil else {
      status = "This page encoding is read-only."
      return
    }
    insertTool = ""
    dropOnPage = true
    writeTarget = nil
    writingFormat = WritingFormat()
    writingCaret = nil
    if focusBlank, let text = site?.files[name]?.text {
      let p = (text as NSString).range(of: "<p></p>")
      if p.location != NSNotFound { writingCaret = p.location + 3 }
    }
    nextScroll = nil
    resumeCanvasFocus = false
    groupIDs = []
    paperColor = ""
    paperHasImage = false
    page = name
    file = name
    running = false
    selected = nil
    inspection = nil
    pendingFocus = nil
    codeRange = NSRange(location: 0, length: 0)
    refresh()
  }
  func chooseFile(_ name: String) {
    guard let site else { return }
    if site.pages.contains(name) {
      choosePage(name)
      return
    }
    guard site.files[name]?.text != nil else {
      status = "Drag this artwork onto a layout container."
      return
    }
    file = name
    codeRange = NSRange(location: 0, length: 0)
    if mode == .design { mode = .split }
  }
  func refresh(later: Bool = false) {
    timer?.invalidate()
    lastTyping = nil
    revision += 1
    inspection = nil
    if later {
      timer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: false) { [weak self] _ in
        self?.render()
      }
    } else {
      render()
    }
  }
  func render() {
    guard let site, let s = site.files[page]?.text, let engine else { return }
    let marker = "data-wb-" + UUID().uuidString.lowercased()
    do {
      let ix = try engine.call("info", [s, marker], as: IndexedPage.self)
      nodes = ix.nodes
      sourceIssue = ix.error
      if !ix.error.isEmpty && !running {
        preview = nil
        inspection = nil
        status = ix.error + " Your source is retained."
        return
      }
      if let focus = pendingFocus {
        let row = nodes.first(where: { $0.start == focus })
        selected = row?.id
        if let row { reveal(page, NSRange(location: row.start, length: row.length)) }
        pendingFocus = nil
      } else if let anchor = groupIDs.first, nodes.indices.contains(anchor), file == page {
        let row = nodes[anchor]
        reveal(page, NSRange(location: row.start, length: row.length))
      } else if !nodes.contains(where: { $0.id == selected }) {
        selected = nil
      }
      previewRevision = revision
      preview = PreviewState(
        token: UUID().uuidString, marker: marker, page: page, html: running ? s : ix.html,
        files: site.files, nodes: ix.nodes, run: running, writing: writing && !running,
        caret: writingCaret, writeTarget: writeTarget, scroll: nextScroll, assetRoot: site.root,
        linkedAssets: site.linkedAssets)
      nextScroll = nil
      writeTarget = nil
    } catch {
      sourceIssue = error.localizedDescription
      preview = nil
    }
  }
  func setRun(_ run: Bool) {
    guard !run || site?.files[page]?.text != nil else { return }
    insertTool = ""
    groupIDs = []
    running = run
    logs = []
    if run && mode == .code { mode = .split }
    refresh()
    status =
      run
      ? "Run preview · Option-click to identify runtime DOM."
      : "Edit canvas · page scripts are inactive."
  }
  func reveal(_ path: String, _ range: NSRange) {
    file = path
    codeRange = range
    revealID = UUID()
  }
  func select(_ id: Int) {
    guard let n = nodes.first(where: { $0.id == id }) else { return }
    if !groupIDs.isEmpty { groupIDs = [] }
    if selected != id { inspection = nil }
    selected = id
    reveal(page, NSRange(location: n.start, length: n.length))
  }
  func showRule(_ r: RuleInfo) {
    guard let p = localPath(r.source), let t = site?.files[p]?.text else {
      status = "Open the owning site folder to locate this source."
      return
    }
    mode = .split
    if r.styleIndex == -2, let id = selected {
      select(id)
      return
    }
    let o: [String: Any] = ["styleIndex": r.styleIndex, "selector": r.selector, "path": r.path]
    if let range = try? engine?.call("ruleRange", [t, o], as: [Int].self), range.count == 2 {
      reveal(p, NSRange(location: range[0], length: range[1]))
      status = "Showing " + r.selector + " in " + p
    } else {
      reveal(p, NSRange(location: 0, length: 0))
      status = "The exact source range is ambiguous. Search for " + r.selector + " in " + p
    }
  }
  func codeFallback(_ reason: String, id: Int? = nil) {
    if let id { select(id) }
    mode = .code
    status = reason
  }
  func inspect(_ data: [String: Any]) {
    guard let d = try? JSONSerialization.data(withJSONObject: data),
      let item = try? JSONDecoder().decode(Inspection.self, from: d), item.prop == property
    else { return }
    if selected != item.id || !groupIDs.isEmpty { select(item.id) }
    inspection = item
  }
  func selectGroup(_ ids: [Int]) {
    guard ids.count > 1, Set(ids).count == ids.count,
      let first = ids.first, nodes.indices.contains(first),
      ids.allSatisfy({ nodes.indices.contains($0) && nodes[$0].parent == nodes[first].parent })
    else { return }
    if selectedIDs != ids {
      showInspector = true
      selected = first
      groupIDs = ids
      reveal(page, NSRange(location: nodes[first].start, length: nodes[first].length))
    }
    if inspection != nil { inspection = nil }
  }
  var canDeleteSelection: Bool {
    !selectedIDs.isEmpty
      && selectedIDs.allSatisfy {
        nodes.indices.contains($0) && nodes[$0].parent >= 0
          && !["html", "head", "body", "meta", "link", "base", "script", "style", "template"]
            .contains(nodes[$0].tag)
      }
  }
  func deleteLayers() {
    guard safeToEdit, !writing, mode != .code, canDeleteSelection else { return }
    mutate(
      ["kind": "deleteLayers", "ids": selectedIDs],
      name: selectedIDs.count == 1 ? "Delete layer" : "Delete layers")
  }
  func arrangeGroup(_ command: String, dx: Double = 0, dy: Double = 0) {
    guard !groupIDs.isEmpty, safeToEdit, mode != .code, designer?.state.token == preview?.token
    else { return }
    designer?.arrange(groupIDs, command: command, dx: dx, dy: dy)
  }
  func insertFromCanvas(_ data: [String: Any], armed: Bool = false) {
    guard let id = data["id"] as? Int, nodes.indices.contains(id),
      let item = data["item"] as? String,
      !armed || insertTool == item
    else { return }
    insertTool = ""
    if writing {
      writing = false
      writingCaret = nil
    }
    nextScroll = data["scroll"] as? [Double]
    resumeCanvasFocus = true
    let before = data["before"] ?? NSNull()
    let point = data["point"] ?? NSNull()
    if let kind = SnippetKind(item: item) {
      if preview?.writing == true { refresh() }
      openSnippet(at: id, adding: kind, placement: ["before": before, "point": point])
    } else if item == "Image" {
      if preview?.writing == true { refresh() }
      pickImage(at: id, before: before, point: point)
    } else {
      mutate(
        ["kind": "insert", "item": item, "before": before, "point": point], id: id,
        name: "Insert " + item)
    }
  }
  struct Change {
    let path: String
    let bytes: Data?
  }
  func change(
    _ list: [Change], _ name: String, focus: Int? = nil, later: Bool = false,
    live: Bool = false, registerUndo: Bool = true, beforeCaret: Int? = nil, afterCaret: Int? = nil,
    arrangement: (page: String, ids: [Int])? = nil
  ) {
    guard var s = site, !busy else { return }
    var reverse = [Change]()
    for c in list {
      let old = s.files[c.path]
      if old?.bytes == c.bytes { continue }
      reverse.append(Change(path: c.path, bytes: old?.bytes))
      if let bytes = c.bytes {
        if var f = old {
          f.bytes = bytes
          s.files[c.path] = f
        } else {
          s.files[c.path] = SourceFile(path: c.path, data: bytes, new: true)
        }
      } else if old?.original == nil {
        s.files.removeValue(forKey: c.path)
      }
      // An already-saved artwork remains on disk when undoing its insertion.
    }
    guard !reverse.isEmpty else { return }
    if !pageImages.isEmpty {
      let pages = Set(s.pages)
      if reverse.contains(where: { !pages.contains($0.path) }) {
        pageImages.removeAll()
      } else {
        for item in reverse { pageImages.removeValue(forKey: item.path) }
      }
    }
    let undo = reverse
    let previous = nodes.first(where: { $0.id == selected })?.start
    if registerUndo {
      let ownGroup = !history.isUndoing && !history.isRedoing
      if ownGroup { history.beginUndoGrouping() }
      history.registerUndo(withTarget: self) { model in
        model.change(
          undo, name, focus: previous, beforeCaret: model.writingCaret ?? afterCaret,
          afterCaret: beforeCaret, arrangement: arrangement)
      }
      history.setActionName(name)
      if ownGroup { history.endUndoGrouping() }
    }
    site = s
    groupIDs = []
    if let arrangement, arrangement.page == page, !writing, !running {
      selected = arrangement.ids.first
      groupIDs = arrangement.ids
      pendingFocus = nil
    } else {
      pendingFocus = arrangement == nil ? focus : nil
    }
    writingCaret = afterCaret
    if !live { refresh(later: later) }
    status = name
  }
  func applyWriting(_ d: [String: Any], extra: [Change]) throws {
    guard let f = site?.files[page], let text = f.text, let engine,
      let start = d["start"] as? Int, let old = d["old"] as? String,
      let value = d["value"] as? String, let caret = d["caret"] as? Int
    else {
      throw BenchError("The writing selection is unavailable. Reopen Design to continue.")
    }
    let original = text as NSString
    let length = (old as NSString).length
    guard start >= 0, start <= original.length, length <= original.length - start else {
      throw BenchError("The writing range moved. Review the current source in Code.")
    }
    let range = NSRange(location: start, length: length)
    guard original.substring(with: range).utf8.elementsEqual(old.utf8) else {
      throw BenchError("The text changed before this edit. Review the current source in Code.")
    }
    let next = original.replacingCharacters(in: range, with: value)
    // Index source without marker injection. A live keystroke does not navigate the web view.
    let ix = try engine.call("rows", [next], as: [ElementRow].self)
    let action = d["action"] as? String ?? ""
    let names = [
      "text": "Typing", "paste": "Paste", "link": "Edit link", "bold": "Bold", "italic": "Italic",
      "paragraph": "Insert paragraph", "break": "Insert line break",
      "block": "Change paragraph style",
      "list": "Change list", "element": "Insert element", "join": "Join paragraphs",
      "font-family": "Change typeface", "font-size": "Change type size",
      "color": "Change text color",
    ]
    let typing =
      d["typing"] as? Bool == true && extra.isEmpty && old.isEmpty
      && value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    let now = Date.timeIntervalSinceReferenceDate
    let token = preview?.token ?? ""
    let continued =
      typing && lastTyping?.caret == d["was"] as? Int && lastTyping?.token == token
      && now - (lastTyping?.time ?? 0) < 1.2
    change(
      extra + [Change(path: page, bytes: try f.encoded(next))], names[action] ?? "Write",
      live: true, registerUndo: !continued, beforeCaret: d["was"] as? Int, afterCaret: caret)
    lastTyping = typing ? (caret, now, token) : nil
    nodes = ix
    if file == page { reveal(page, NSRange(location: caret, length: 0)) }
  }
  func editSource(_ text: String) {
    guard !busy, !running, let f = site?.files[file], let data = try? f.encoded(text) else {
      return
    }
    if file == page {
      selected = nil
      pendingFocus = nil
    }
    change([Change(path: file, bytes: data)], "Edit " + file, later: true)
  }
  func undo() { if !running && !busy { history.undo() } }
  func redo() { if !running && !busy { history.redo() } }
  func mutate(
    _ op: [String: Any], id: Int? = nil, name: String = "Visual edit", extra: [Change] = []
  ) {
    guard safeToEdit, let id = id ?? selected, let f = site?.files[page], let s = f.text, let engine
    else { return }
    do {
      let r = try engine.call("run", [s, id, op], as: EditResult.self)
      let arranging = op["kind"] as? String == "selectionFrames"
      let selection = arranging ? (page: page, ids: groupIDs) : nil
      change(
        extra + [Change(path: page, bytes: try f.encoded(r.text))], name, focus: r.focus,
        arrangement: selection)
      if let range = r.range, range.count == 2 {
        mode = .split
        reveal(page, NSRange(location: range[0], length: range[1]))
      }
    } catch { codeFallback(error.localizedDescription, id: id) }
  }
  func nudge(_ dx: Double, _ dy: Double) {
    if !groupIDs.isEmpty {
      arrangeGroup("move", dx: dx, dy: dy)
      return
    }
    guard let i = inspection, i.canMove else {
      status = "Choose an absolute child of an explicitly positioned parent."
      return
    }
    if devicePlacement && supportsDevicePlacement {
      requestFrame(["left": Int((i.x + dx).rounded()), "top": Int((i.y + dy).rounded())])
      return
    }
    mutate(["kind": "move", "x": i.x + dx, "y": i.y + dy], name: "Move object")
  }
  @discardableResult func addAsset(
    _ name: String, bytes: Data?, existing: String?, id: Int, before: Any, point: Any = NSNull(),
    replace: Bool = false
  ) -> Bool {
    guard safeToEdit, let site, let token = preview?.token else { return false }
    do {
      var extra = [Change]()
      let url: String
      if let existing {
        let ext = (existing as NSString).pathExtension.lowercased()
        let target = PhotoTarget(
          token: token, id: id, before: before, point: point, replace: replace)
        if site.linkedAssets.contains(existing) {
          let input = try PhotoInput(url: Site.safe(existing, under: site.root))
          startPhoto(input, target: target, offer: input.byteCount > photoBudget(target))
          return false
        }
        if let file = site.files[existing], embedPhotoCopy || !Site.images.contains(ext) {
          return addAsset(
            (existing as NSString).lastPathComponent, bytes: file.bytes, existing: nil,
            id: id, before: before, point: point, replace: replace)
        }
        url = Site.relative(existing, from: page)
      } else if let bytes {
        let target = PhotoTarget(
          token: token, id: id, before: before, point: point, replace: replace)
        let limit = photoBudget(target)
        let ext = (name as NSString).pathExtension.lowercased()
        if Site.rasterPhotos.contains(ext) && (bytes.count > limit || !Site.images.contains(ext)) {
          startPhoto(
            PhotoInput(data: bytes, name: name), target: target, offer: bytes.count > limit)
          return false
        }
        if embedPhotoCopy {
          let ext = (name as NSString).pathExtension.lowercased()
          guard Site.images.contains(ext), bytes.count <= 2 * 1024 * 1024 else {
            throw BenchError(
              "Single-file artwork must be an image under 2 MiB. Open a site folder for linked artwork."
            )
          }
          url = "data:" + mime(name) + ";base64," + bytes.base64EncodedString()
        } else {
          let path = try site.assetPath(name, data: bytes)
          if site.files[path] == nil { extra.append(Change(path: path, bytes: bytes)) }
          url = Site.relative(path, from: page)
        }
      } else {
        return false
      }
      if replace {
        guard nodes.indices.contains(id), nodes[id].tag == "img" else { return false }
        mutate(
          ["kind": "attr", "key": "src", "value": url], id: id, name: "Replace image", extra: extra)
        return mode != .code
      }
      if writing && !running && mode != .code, let writer, writer.state.token == preview?.token {
        writer.image(
          url, alt: ((name as NSString).lastPathComponent as NSString).deletingPathExtension,
          changes: extra)
        return mode != .code
      }
      mutate(
        [
          "kind": "asset", "url": url,
          "alt": ((name as NSString).lastPathComponent as NSString).deletingPathExtension,
          "before": before, "point": point,
        ], id: id, name: "Insert artwork", extra: extra)
      return mode != .code
    } catch {
      alert(error.localizedDescription)
      return false
    }
  }
  func pickImage(
    at parent: Int? = nil, before: Any = NSNull(), point: Any = NSNull(), replace: Bool = false
  ) {
    guard let id = parent ?? selected ?? (writing ? 0 : nil) else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image, .svg]
    guard panel.runModal() == .OK, let url = panel.url, let token = preview?.token else { return }
    importPhotoFile(
      url, target: PhotoTarget(token: token, id: id, before: before, point: point, replace: replace)
    )
  }
  func localPath(_ address: String) -> String? {
    if address.isEmpty { return page }
    guard let u = URL(string: address), u.scheme == "webbench", u.host == "project" else {
      return nil
    }
    let path = String(u.path.dropFirst())
    return site?.files[path] == nil ? nil : path
  }
  func applyStyle(value: String, target: String, scope: String, breakpoint: Int, external: String) {
    guard safeToEdit, let i = inspection, i.prop == property, let engine, let site,
      let f = site.files[page],
      let text = f.text
    else { return }
    do {
      if target == "Winning rule" {
        guard let r = i.rules.indices.contains(i.winner) ? i.rules[i.winner] : nil else {
          throw BenchError("No source-backed winning declaration for this property.")
        }
        if r.styleIndex == -2 {
          mutate(
            ["kind": "inline", "prop": property, "value": value], name: "Edit inline declaration")
          return
        }
        guard let p = localPath(r.source), let sf = site.files[p], let css = sf.text else {
          throw BenchError("Open the stylesheet's site folder to edit this rule.")
        }
        let o: [String: Any] = [
          "styleIndex": r.styleIndex, "path": r.path, "selector": r.selector, "prop": property,
          "value": value,
        ]
        let result = try engine.call("replaceRule", [css, o], as: String.self)
        change(
          [Change(path: p, bytes: try sf.encoded(result))], "Edit " + r.selector,
          focus: nodes[i.id].start)
        return
      }
      if target == "Element" && scope == "Global" {
        mutate(
          ["kind": "inline", "prop": property, "value": value], name: "Edit inline declaration")
        return
      }
      let out = external != "Page" ? site.files[external] : nil
      let o: [String: Any] = [
        "selector": target == "Element" ? "" : target, "prop": property, "value": value,
        "mobile": scope == "Breakpoint", "width": breakpoint, "external": out != nil,
        "css": out?.text ?? "",
      ]
      let r = try engine.call("style", [text, i.id, o], as: EditResult.self)
      var changes = [Change(path: page, bytes: try f.encoded(r.text))]
      if let out, let css = r.css {
        changes.append(Change(path: out.path, bytes: try out.encoded(css)))
      }
      change(
        changes, "Add " + (scope == "Breakpoint" ? "breakpoint" : "global") + " rule",
        focus: r.focus)
    } catch {
      if target == "Winning rule", i.rules.indices.contains(i.winner) {
        showRule(i.rules[i.winner])
        mode = .code
        status = error.localizedDescription
      } else {
        codeFallback(error.localizedDescription, id: i.id)
      }
    }
  }
  func handler() {
    guard let i = inspection, let site else { return }
    let id = i.attributes["id"] ?? ""
    if !id.isEmpty {
      let safeID = NSRegularExpression.escapedPattern(for: id)
      let pattern =
        "(?:getElementById\\(\\s*['\"]" + safeID + "['\"]\\s*\\)|querySelector\\(\\s*['\"]#"
        + safeID + "['\"]\\s*\\))\\s*\\.\\s*(?:addEventListener\\(\\s*['\"]click['\"]|onclick\\s*=)"
      let rx = try? NSRegularExpression(pattern: pattern)
      if let html = site.files[page]?.text,
        let scripts = try? engine?.call("scripts", [html], as: [ScriptRange].self)
      {
        var components = URLComponents()
        components.scheme = "webbench"
        components.host = "project"
        components.path = "/" + page
        for script in scripts where script.javascript {
          let p: String
          let text: String
          let range: NSRange
          if script.src.isEmpty {
            p = page
            text = html
            range = NSRange(location: script.start, length: script.end - script.start)
          } else {
            guard let u = URL(string: script.src, relativeTo: components.url)?.absoluteURL,
              let local = localPath(u.absoluteString), let js = site.files[local]?.text
            else { continue }
            p = local
            text = js
            range = NSRange(location: 0, length: (text as NSString).length)
          }
          guard let match = rx?.firstMatch(in: text, range: range) else { continue }
          mode = .split
          reveal(p, match.range)
          status = "Possible click handler in " + p
          return
        }
      }
    }
    mutate(["kind": "handler"], name: "Wire click handler")
  }
  var recoveryRoot: URL {
    Self.supportDirectory.appendingPathComponent("Recovery")
  }
  func finishSave(_ s: Site, _ error: Error?) -> Bool {
    site = s
    if let c = error as? Conflict {
      let a = NSAlert()
      a.messageText = "External change · " + c.path
      a.informativeText =
        c.localizedDescription + " Use the external version to continue saving other files."
      a.addButton(withTitle: "Keep editing")
      a.addButton(withTitle: "Show recovery copies")
      a.addButton(withTitle: "Use external version")
      let choice = a.runModal()
      if choice == .alertSecondButtonReturn {
        NSWorkspace.shared.activateFileViewerSelecting([c.recovery])
      }
      if choice == .alertThirdButtonReturn {
        useExternal(c)
      }
      status = c.localizedDescription
      return false
    }
    if let error {
      alert(error.localizedDescription)
      return false
    }
    status = "Saved · original bytes preserved for untouched files."
    return true
  }
  func useExternal(_ conflict: Conflict) {
    guard var current = site else { return }
    let path = conflict.path
    current.files[path] = conflict.disk.map { SourceFile(path: path, data: $0) }
    site = current
    history.removeAllActions()
    groupIDs = []
    selected = nil
    if current.files[page]?.text == nil {
      if let next = current.pages.first(where: { current.files[$0]?.text != nil }) {
        choosePage(next)
      } else {
        timer?.invalidate()
        running = false
        selected = nil
        inspection = nil
        nodes = []
        preview = nil
        page = ""
        file = current.files.keys.sorted().first(where: { current.files[$0]?.text != nil }) ?? ""
        sourceIssue = "No readable HTML page remains in this project."
        mode = .code
      }
    } else {
      if current.files[file]?.text == nil { reveal(page, NSRange(location: 0, length: 0)) }
      refresh()
    }
  }
  func saveSync() -> Bool {
    guard var s = site else { return true }
    do {
      try s.save(recovery: recoveryRoot)
      return finishSave(s, nil)
    } catch { return finishSave(s, error) }
  }
  func save() {
    lastTyping = nil
    if writing && !running && mode != .code && !busy {
      _ = saveSync()
      return
    }
    guard var s = site, !busy else { return }
    let recovery = recoveryRoot
    busy = true
    DispatchQueue.global(qos: .userInitiated).async {
      var failure: Error?
      do { try s.save(recovery: recovery) } catch { failure = error }
      let result = s
      let err = failure
      DispatchQueue.main.async {
        self.busy = false
        _ = self.finishSave(result, err)
      }
    }
  }
  func diff() {
    guard let site else { return }
    reviewTitle = "Source changes"
    let paths = site.dirtyPaths
    if paths.isEmpty {
      diffText = "No changes. All files match their opened bytes."
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      var parts = [String]()
      for p in paths {
        guard let f = site.files[p] else { continue }
        if f.text == nil {
          parts.append("Added or changed binary asset: " + p)
          continue
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          defer { try? FileManager.default.removeItem(at: dir) }
          let old = dir.appendingPathComponent("a")
          let new = dir.appendingPathComponent("b")
          let original = SourceFile(path: p, data: f.original ?? Data()).text ?? ""
          try Data(original.utf8).write(to: old)
          try Data((f.text ?? "").utf8).write(to: new)
          let task = Process()
          let pipe = Pipe()
          task.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
          task.arguments = ["-u", "-L", "a/" + p, "-L", "b/" + p, old.path, new.path]
          task.standardOutput = pipe
          task.standardError = pipe
          try task.run()
          let out = pipe.fileHandleForReading.readDataToEndOfFile()
          task.waitUntilExit()
          parts.append(String(decoding: out, as: UTF8.self))
        } catch { parts.append(p + " · " + error.localizedDescription) }
      }
      let result = parts.joined(separator: "\n")
      DispatchQueue.main.async {
        self.reviewTitle = "Source changes"
        self.diffText = result
      }
    }
  }
}

struct ShapeSilhouette: Decodable {
  let width: Double, height: Double
  let radius: Double?, ellipse: Bool?, points: [[Double]]?
}

struct InsertElement: Identifiable, Decodable {
  let shape: ShapeSilhouette?
  let id: String, title: String, group: String, symbol: String, tag: String
}
extension Session {
  var canEditLayers: Bool { safeToEdit && mode != .code && preview != nil }
  func accepts(_ tag: String, in parent: ElementRow) -> Bool { order.accepts(tag, in: parent) }
  var selectedContainer: ElementRow? {
    guard let selected, nodes.indices.contains(selected), groupIDs.isEmpty else { return nil }
    let row = nodes[selected]
    return elements.contains { accepts($0.tag, in: row) } ? row : nil
  }
  func insertChild(_ item: InsertElement, in parent: Int) {
    guard canEditLayers, nodes.indices.contains(parent), accepts(item.tag, in: nodes[parent]) else {
      status = "Choose a compatible container in Layers."
      return
    }
    let token = preview?.token
    let bytes = site?.files[page]?.bytes
    afterWriting { [weak self] in
      guard let self, self.preview?.token == token, self.site?.files[self.page]?.bytes == bytes
      else { return }
      self.insertFromCanvas(["id": parent, "item": item.id])
    }
  }
  var order: LayerOrder { LayerOrder(nodes: nodes, layerParents: layerParents) }
  func movableLayer(_ id: Int) -> Bool { order.movableLayer(id) }
  func slot(for child: Int, at target: Int, zone: LayerZone) -> LayerSlot? {
    canEditLayers ? order.slot(for: child, at: target, zone: zone) : nil
  }
  func slot(for child: Int, step: LayerStep) -> LayerSlot? {
    canEditLayers ? order.slot(for: child, step: step) : nil
  }
  func moveLayer(_ child: Int, to slot: LayerSlot) {
    guard canEditLayers else { return }
    let token = preview?.token
    let bytes = site?.files[page]?.bytes
    afterWriting { [weak self] in
      guard let self, self.preview?.token == token, self.site?.files[self.page]?.bytes == bytes
      else { return }
      self.writing = false
      self.writingCaret = nil
      self.mutate(
        ["kind": "relocate", "child": child, "before": slot.before as Any? ?? NSNull()],
        id: slot.parent, name: "Move layer")
    }
  }
}

extension Session {
  func chooseMedia(for id: Int) {
    guard canEditLayers, let site, nodes.indices.contains(id),
      ["audio", "video"].contains(nodes[id].tag), let token = preview?.token
    else { return }
    let allowed = nodes[id].tag == "audio" ? Site.audio : Site.video
    let panel = NSOpenPanel()
    panel.allowedContentTypes = allowed.sorted().compactMap { UTType(filenameExtension: $0) }
    if !site.standalone { panel.directoryURL = site.root }
    guard panel.runModal() == .OK, let url = panel.url, preview?.token == token else { return }
    do {
      let leaf = url.lastPathComponent
      let ext = url.pathExtension.lowercased()
      guard allowed.contains(ext) else { throw BenchError("Choose a supported media file.") }
      let prefix = site.root.path + "/"
      let path = url.standardizedFileURL.path
      var changes = [Change]()
      let src: String
      if !embedPhotoCopy, path.hasPrefix(prefix),
        site.linkedAssets.contains(String(path.dropFirst(prefix.count)))
      {
        src = Site.relative(String(path.dropFirst(prefix.count)), from: page)
      } else {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let target = PhotoTarget(
          token: token, id: id, before: NSNull(), point: NSNull(), replace: true)
        let limit = embedPhotoCopy ? photoBudget(target) : 12 * 1024 * 1024
        guard size > 0, size <= limit else {
          throw BenchError(
            "Place this media file in a site folder, open that folder in WebBench, and choose the file from there."
          )
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= limit else {
          throw BenchError("The media file changed. Choose the file again.")
        }
        if embedPhotoCopy {
          src = "data:" + mime(leaf) + ";base64," + data.base64EncodedString()
        } else {
          let asset = try site.assetPath(leaf, data: data, allowed: allowed)
          if site.files[asset] == nil { changes = [Change(path: asset, bytes: data)] }
          src = Site.relative(asset, from: page)
        }
      }
      mutate(
        ["kind": "attr", "key": "src", "value": src], id: id, name: "Set media source",
        extra: changes)
    } catch { alert(error.localizedDescription) }
  }
}
