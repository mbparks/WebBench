import Cocoa
import SwiftUI

@main
enum WebBenchApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
  let model = Session()
  var window: NSWindow!
  private var pendingClose = false, closeApproved = false, pendingQuit = false
  private var checkWindow: SampleCheckWindow?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = menus()
    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    w.title = "WebBench — Green Shoe Garage"
    w.minSize = NSSize(width: 850, height: 500)
    w.setFrameAutosaveName("WebBenchWorkspace")
    w.contentView = NSHostingView(rootView: WorkspaceView(m: model))
    w.delegate = self
    w.isReleasedWhenClosed = false
    if !w.setFrameUsingName("WebBenchWorkspace") { w.center() }
    window = w
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async {
      if self.model.site == nil && !self.model.busy { self.model.newStudioDraft() }
    }
  }
  func application(_ sender: NSApplication, open urls: [URL]) {
    if let u = urls.first { model.afterWriting { self.model.open(u) } }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if closeApproved { return true }
    if model.writer != nil && model.writing && !model.running && model.mode != .code {
      guard !pendingClose else { return false }
      pendingClose = true
      model.afterWriting(onFailure: { self.pendingClose = false }) {
        self.pendingClose = false
        if self.model.mayLeave() {
          self.closeApproved = true
          self.model.site = nil
          sender.close()
        }
      }
      return false
    }
    guard model.mayLeave() else { return false }
    model.site = nil
    return true
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if model.site != nil, model.writer != nil,
      model.writing && !model.running && model.mode != .code
    {
      if !pendingQuit {
        pendingQuit = true
        model.afterWriting(onFailure: {
          self.pendingQuit = false
          sender.reply(toApplicationShouldTerminate: false)
        }) {
          self.pendingQuit = false
          sender.reply(toApplicationShouldTerminate: self.model.mayLeave())
        }
      }
      return .terminateLater
    }
    return model.mayLeave() ? .terminateNow : .terminateCancel
  }
  func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model.history }
  func menus() -> NSMenu {
    let bar = NSMenu()
    func menu(_ name: String) -> NSMenu {
      let item = NSMenuItem()
      bar.addItem(item)
      let m = NSMenu(title: name)
      item.submenu = m
      return m
    }
    func item(
      _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
      _ modifier: NSEvent.ModifierFlags = .command, _ target: AnyObject? = nil
    ) {
      let v = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
      v.keyEquivalentModifierMask = modifier
      v.target = target
    }
    let app = menu("WebBench")
    item(
      app, "About WebBench", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "",
      .command, NSApp)
    app.addItem(.separator())
    item(app, "Quit WebBench", #selector(NSApplication.terminate(_:)), "q", .command, NSApp)
    let file = menu("File")
    item(file, "New Site Folder…", #selector(siteFolder), "", .command, self)
    item(file, "New Free Canvas", #selector(freePage), "n", .command, self)
    item(file, "New Studio Portfolio", #selector(portfolio), "", .command, self)
    item(file, "New Sample Board…", #selector(board), "", .command, self)
    item(file, "New Blank Page…", #selector(blank), "", .command, self)
    item(file, "New Field Instrument…", #selector(instrument), "n", [.command, .shift], self)
    item(file, "Open File or Site Folder…", #selector(open), "o", .command, self)
    item(file, "Try Device Workbench", #selector(deviceExample), "", .command, self)
    item(file, "Try Power Meter Workflow", #selector(powerExample), "", .command, self)
    item(file, "Try Interaction Example", #selector(interactionExample), "", .command, self)
    item(file, "Open Sample Workbench…", #selector(sample), "", .command, self)
    item(file, "Show Project in Finder", #selector(showProject), "", .command, self)
    item(file, "Run Sample Checks…", #selector(checkSamples), "", .command, self)
    item(file, "Save Changes", #selector(save), "s", .command, self)
    item(file, "Preview Website in Browser", #selector(browserPreview), "", .command, self)
    item(file, "Export Website Folder…", #selector(exportSite), "e", [.shift, .command], self)
    item(file, "Inspect Diff…", #selector(diff), "d", [.command, .shift], self)
    item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
    let edit = menu("Edit")
    item(edit, "Undo", #selector(undo), "z", .command, self)
    item(edit, "Redo", #selector(redo), "z", [.command, .shift], self)
    edit.addItem(.separator())
    for (s, k) in [("cut:", "x"), ("copy:", "c"), ("paste:", "v"), ("selectAll:", "a")] {
      item(
        edit, ["x": "Cut", "c": "Copy", "v": "Paste", "a": "Select All"][k]!,
        NSSelectorFromString(s), k)
    }
    edit.addItem(.separator())
    item(edit, "Interactions…", #selector(interactions), "j", [.command, .option], self)
    let view = menu("View")
    for (idx, name) in ["Design", "Code", "Split"].enumerated() {
      item(view, name, #selector(mode(_:)), String(idx + 1), .command, self)
    }
    item(view, "Run / Stop", #selector(run), "r", .command, self)
    item(view, "Toggle Inspector", #selector(inspector), "i", [.command, .option], self)
    item(file, "Edit Favicon…", #selector(favicon), "", .command, self)
    let layout = menu("Layout")
    for (title, code) in [
      ("Move Left", 0xf702), ("Move Right", 0xf703), ("Move Up", 0xf700), ("Move Down", 0xf701),
    ] {
      item(
        layout, title, #selector(move(_:)), String(UnicodeScalar(code)!), [.command, .option], self)
    }
    item(layout, "Move Earlier", #selector(earlier), "[", [.command, .option], self)
    item(layout, "Move Later", #selector(later), "]", [.command, .option], self)
    let win = menu("Window")
    item(win, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
    NSApp.windowsMenu = win
    return bar
  }
  @objc func sample() { model.afterWriting { self.model.openSample() } }
  @objc func showProject() { model.showProject() }
  @MainActor @objc func checkSamples() {
    if let checkWindow, checkWindow.isRunning {
      checkWindow.bringForward()
      return
    }
    checkWindow?.close()
    let check = SampleCheckWindow()
    checkWindow = check
    check.start()
  }
  @objc func siteFolder() { model.afterWriting { self.model.newFolder() } }
  @objc func deviceExample() { model.afterWriting { self.model.newStudioDraft("Device-workbench") } }
  @objc func powerExample() { model.afterWriting { self.model.newStudioDraft("Power-meter") } }
  @objc func interactionExample() { model.afterWriting { self.model.newStudioDraft("Signal-check") } }
  @objc func interactions() { model.afterWriting { self.model.openInteractions() } }
  @objc func inspector() { model.toggleInspector() }
  @objc func favicon() { model.openFavicon() }
  @objc func freePage() { model.afterWriting { self.model.newStudioDraft() } }
  @objc func portfolio() { model.afterWriting { self.model.newStudioDraft("studio") } }
  @objc func browserPreview() { model.afterWriting { self.model.previewInBrowser() } }
  @objc func exportSite() { model.afterWriting { self.model.exportSnapshot(folder: true) } }
  @objc func board() { model.afterWriting { self.model.new("board") } }
  @objc func blank() { model.afterWriting { self.model.new("blank") } }
  @objc func instrument() { model.afterWriting { self.model.new("instrument") } }
  @objc func open() { model.afterWriting { self.model.openPanel() } }
  @objc func save() { model.afterWriting { self.model.save() } }
  @objc func diff() { model.afterWriting { self.model.diff() } }
  private var snippetUndo: UndoManager? {
    (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager
  }
  @objc func undo() {
    if model.snippetEditor != nil { snippetUndo?.undo(); return }
    model.afterWriting { self.model.undo() }
  }
  @objc func redo() {
    if model.snippetEditor != nil { snippetUndo?.redo(); return }
    model.afterWriting { self.model.redo() }
  }
  @objc func run() { model.afterWriting { self.model.setRun(!self.model.running) } }
  @objc func mode(_ sender: NSMenuItem) {
    model.afterWriting { self.model.mode = Mode(rawValue: sender.title) ?? .split }
  }
  private func layerStep(_ item: NSMenuItem) -> LayerStep? {
    switch item.keyEquivalent.unicodeScalars.first?.value {
    case 0xf702: return .outdent
    case 0xf703: return .indent
    case 0xf700: return .up
    case 0xf701: return .down
    default: return nil
    }
  }
  private var editingLayerOrder: Bool {
    model.sidebarTab == "Tree" && !model.writing && !model.running && model.mode != .code
  }
  @objc func move(_ sender: NSMenuItem) {
    guard let step = layerStep(sender) else { return }
    if editingLayerOrder {
      if let id = model.selected, let slot = model.slot(for: id, step: step) {
        model.moveLayer(id, to: slot)
      }
    } else {
      model.nudge(
        step == .outdent ? -1 : step == .indent ? 1 : 0,
        step == .up ? -1 : step == .down ? 1 : 0)
    }
  }
  @objc func earlier() { model.mutate(["kind": "reorder", "step": -1], name: "Move earlier") }
  @objc func later() { model.mutate(["kind": "reorder", "step": 1], name: "Move later") }
  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    if model.snippetEditor != nil {
      if item.action == #selector(undo) { item.title = "Undo Typing"; return snippetUndo?.canUndo == true }
      if item.action == #selector(redo) { item.title = "Redo Typing"; return snippetUndo?.canRedo == true }
      return false
    }
    if model.busy || model.workflow != nil { return false }
    if item.action == #selector(interactions) { return model.site != nil && !model.running }
    if item.action == #selector(undo) {
      item.title = model.history.undoMenuItemTitle
      return model.history.canUndo && !model.running
    }
    if item.action == #selector(redo) {
      item.title = model.history.redoMenuItemTitle
      return model.history.canRedo && !model.running
    }
    if item.action == #selector(move(_:)), let step = layerStep(item) {
      if editingLayerOrder {
        item.title = step.rawValue
        guard let id = model.selected, model.groupIDs.isEmpty else { return false }
        return model.slot(for: id, step: step) != nil
      }
      switch step {
      case .up: item.title = "Move Up"
      case .down: item.title = "Move Down"
      case .indent: item.title = "Move Right"
      case .outdent: item.title = "Move Left"
      }
      return (model.inspection?.canMove == true || !model.groupIDs.isEmpty) && model.safeToEdit
    }
    if item.action == #selector(earlier) || item.action == #selector(later) {
      return model.inspection != nil && model.safeToEdit
    }
    return model.site != nil
      || [
        #selector(deviceExample), #selector(powerExample), #selector(interactionExample), #selector(checkSamples), #selector(sample), #selector(siteFolder), #selector(blank),
        #selector(instrument), #selector(freePage), #selector(portfolio), #selector(board),
        #selector(open),
      ].contains(
        item.action ?? #selector(open))
  }
}
