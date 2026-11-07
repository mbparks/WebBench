import AppKit
import SwiftUI
@preconcurrency import WebKit

func mime(_ path: String) -> String {
  let types = [
    "html": "text/html", "htm": "text/html", "js": "text/javascript", "mjs": "text/javascript",
    "css": "text/css", "svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg",
    "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "avif": "image/avif",
    "heic": "image/heic", "heif": "image/heif", "tiff": "image/tiff", "tif": "image/tiff",
    "bmp": "image/bmp", "ico": "image/x-icon", "woff": "font/woff", "woff2": "font/woff2",
    "otf": "font/otf",
    "mp3": "audio/mpeg", "m4a": "audio/mp4", "wav": "audio/wav", "ogg": "audio/ogg",
    "flac": "audio/flac",
    "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime", "webm": "video/webm",
    "ttf": "font/ttf", "json": "application/json", "wasm": "application/wasm",
  ]
  return types[(path as NSString).pathExtension.lowercased()] ?? "application/octet-stream"
}
private final class ProjectScheme: NSObject, WKURLSchemeHandler {
  let state: PreviewState
  var inserted = [String: SourceFile]()
  init(_ state: PreviewState) { self.state = state }
  func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
    guard let u = task.request.url, u.scheme == "webbench", u.host == "project" else {
      task.didFailWithError(URLError(.badURL))
      return
    }
    let path = String(u.path.dropFirst())
    var asset = state.files[path] ?? inserted[path]
    if asset == nil, state.linkedAssets.contains(path), let root = state.assetRoot {
      do {
        let url = try Site.safe(path, under: root)
        asset = SourceFile(path: path, data: try Data(contentsOf: url, options: .mappedIfSafe))
      } catch {
        task.didFailWithError(error)
        return
      }
    }
    guard let f = asset else {
      task.didFailWithError(URLError(.fileDoesNotExist))
      return
    }
    let data: Data
    let enc: String?
    if path == state.page {
      data = Data(state.html.utf8)
      enc = "utf-8"
    } else if let s = f.text {
      data = Data(s.utf8)
      enc = "utf-8"
    } else {
      data = f.bytes
      enc = nil
    }
    let script = state.run ? "'self' webbench: 'unsafe-inline' 'unsafe-eval' blob:" : "'none'"
    let policy =
      "default-src 'none'; script-src " + script
      + "; style-src 'self' webbench: 'unsafe-inline' data:; img-src 'self' webbench: data: blob:; font-src 'self' webbench: data:; media-src 'self' webbench: data: blob:; connect-src 'self' webbench: blob: data:; object-src 'none'; frame-src 'none'; base-uri 'self'; form-action 'none'"
    var headers = [
      "Content-Type": mime(path) + (enc.map { "; charset=" + $0 } ?? ""),
      "Content-Security-Policy": policy, "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
    ]
    var status = 200
    var payload = data[...]
    if Site.media.contains((path as NSString).pathExtension.lowercased()) {
      headers["Accept-Ranges"] = "bytes"
      if let range = task.request.value(forHTTPHeaderField: "Range") {
        if let slice = Site.mediaRange(range, length: data.count) {
          status = 206
          payload = data[slice]
          headers["Content-Range"] =
            "bytes " + String(slice.lowerBound) + "-" + String(slice.upperBound - 1) + "/"
            + String(data.count)
        } else {
          status = 416
          payload = data.prefix(0)
          headers["Content-Range"] = "bytes */" + String(data.count)
        }
      }
      headers["Content-Length"] = String(payload.count)
    }
    guard
      let response = HTTPURLResponse(
        url: u, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
    else {
      task.didFailWithError(URLError(.badServerResponse))
      return
    }
    task.didReceive(response)
    if !payload.isEmpty { task.didReceive(payload) }
    task.didFinish()
  }
  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
// Finder can provide the source URL directly. WebKit still resolves the destination on the canvas.
private final class DesignWebView: WKWebView {
  private var droppedURL: URL?
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let files =
      sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]) as? [URL]
    droppedURL = files?.count == 1 ? files?.first : nil
    let accepted = super.performDragOperation(sender)
    if !accepted { droppedURL = nil }
    return accepted
  }
  func takePhoto(named name: String, size: Int) -> PhotoInput? {
    defer { droppedURL = nil }
    guard let url = droppedURL, url.lastPathComponent == name,
      let input = try? PhotoInput(url: url), input.byteCount == size
    else { return nil }
    return input
  }
}
struct Canvas: NSViewRepresentable {
  @ObservedObject var model: Session
  let state: PreviewState
  var zoom: CGFloat = 1
  func makeCoordinator() -> Coordinator { Coordinator(model, state) }
  func makeNSView(context: Context) -> WKWebView {
    let c = context.coordinator
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.defaultWebpagePreferences.allowsContentJavaScript = state.run
    config.preferences.javaScriptCanOpenWindowsAutomatically = false
    let scheme = ProjectScheme(state)
    c.scheme = scheme
    config.setURLSchemeHandler(scheme, forURLScheme: "webbench")
    let controller = config.userContentController
    do {
      if state.run {
        controller.add(c, name: "output")
        controller.addUserScript(
          WKUserScript(
            source: try Resources.string("console", "js"), injectionTime: .atDocumentStart,
            forMainFrameOnly: true))
      } else {
        let mini = state.nodes.map {
          ["id": $0.id, "tag": $0.tag, "parent": $0.parent] as [String: Any]
        }
        var options: [String: Any] = ["marker": state.marker, "token": state.token, "tree": mini]
        options["photoBudget"] = model.embedPhotoCopy ? 2 * 1024 * 1024 : 12 * 1024 * 1024
        options["scroll"] = state.scroll
        var script: String
        if state.writing {
          options["source"] = state.files[state.page]?.text ?? ""
          options["caret"] = state.caret
          options["writeTarget"] = state.writeTarget
          script = try ["source", "appearance", "layout-drop", "writing", "document"].map {
            try Resources.string($0, "js")
          }
          .joined(separator: "\n")
        } else {
          script = try ["source", "appearance", "layout-drop", "arrange", "canvas"].map {
            try Resources.string($0, "js")
          }.joined(
            separator: "\n")
        }
        let json = String(
          decoding: try JSONSerialization.data(withJSONObject: options), as: UTF8.self)
        let code = "const WB=" + json + ";\n" + script
        controller.add(c, contentWorld: .defaultClient, name: "design")
        controller.addUserScript(
          WKUserScript(
            source: code, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
        )
      }
    } catch { DispatchQueue.main.async { model.alert(error.localizedDescription) } }
    let web =
      state.run
      ? WKWebView(frame: .zero, configuration: config)
      : DesignWebView(frame: .zero, configuration: config)
    web.pageZoom = zoom
    web.navigationDelegate = c
    c.web = web
    // Block network subresources, even if a WebKit version ignores CSP on custom scheme responses.
    let rules =
      "["
      + ["^https?://", "^wss?://", "^ftp://", "^file://"].map {
        #"{"trigger":{"url-filter":""# + $0 + #""},"action":{"type":"block"}}"#
      }.joined(separator: ",") + "]"
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: "WebBench-offline-v1", encodedContentRuleList: rules
    ) { [weak web] list, err in
      guard let web else { return }
      guard let list else {
        model.status = err?.localizedDescription ?? "Offline preview filter failed."
        return
      }
      web.configuration.userContentController.add(list)
      var u = URLComponents()
      u.scheme = "webbench"
      u.host = "project"
      u.path = "/" + state.page
      if let url = u.url { web.load(URLRequest(url: url)) }
    }
    return web
  }
  func updateNSView(_ nsView: WKWebView, context: Context) {
    if abs(nsView.pageZoom - zoom) > 0.00001 { nsView.pageZoom = zoom }
    context.coordinator.sync()
  }
  static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
    if coordinator.model.writer === coordinator { coordinator.model.writer = nil }
    if coordinator.model.designer === coordinator { coordinator.model.designer = nil }
    coordinator.cancelBarriers()
    view.stopLoading()
    view.navigationDelegate = nil
    view.configuration.userContentController.removeAllScriptMessageHandlers()
  }
  final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var web: WKWebView?
    let model: Session, state: PreviewState
    var ready = false, last = ""
    var placement: Bool?, lastPageDrop: Bool?
    private var lastTool: String?, lastSnap: Bool?
    func lift(_ id: Int) { evaluate("webBenchLift", [id]) }
    func frame(_ id: Int, values: [String: Int]) { evaluate("webBenchFrame", [id, values]) }
    func toggle(_ id: Int) { evaluate("webBenchToggle", [id]) }
    func arrange(_ ids: [Int], command: String, dx: Double, dy: Double) {
      evaluate("webBenchArrange", [ids, command, dx, dy])
    }
    func palette(_ item: String, phase: String, screen: NSPoint, snap: Bool) {
      guard ready, model.safeToEdit, !state.run, model.preview?.token == state.token,
        let web, let window = web.window, web.bounds.width > 0, web.bounds.height > 0
      else { return }
      let p = web.convert(window.convertPoint(fromScreen: screen), from: nil)
      let u = (p.x - web.bounds.minX) / web.bounds.width
      let y = (p.y - web.bounds.minY) / web.bounds.height
      let visible = web.visibleRect.contains(p)
      evaluate(
        "webBenchPaletteDrag",
        [
          item, visible ? phase : "cancel", Double(u), Double(web.isFlipped ? y : 1 - y),
          model.freePlacement, snap,
        ])
    }
    private var receivingPhoto = false
    private func receivePhoto(key: String, name: String, size: Int, target: PhotoTarget) {
      guard !receivingPhoto, let web else { return }
      if let input = (web as? DesignWebView)?.takePhoto(named: name, size: size) {
        evaluate("webBenchReleasePhoto", [key])
        model.startPhoto(input, target: target, offer: size > model.photoBudget(target))
        return
      }
      if size > 128 * 1024 * 1024 {
        evaluate("webBenchReleasePhoto", [key])
        let notice = NSAlert()
        notice.messageText = "Resize this large photo?"
        notice.informativeText =
          "Choose the original file to open “" + name + "” directly in the photo editor."
        notice.addButton(withTitle: "Choose original…")
        notice.addButton(withTitle: "Cancel")
        guard notice.runModal() == .alertFirstButtonReturn else { return }
        model.pickImage(at: target.id, before: target.before, point: target.point)
        return
      }
      receivingPhoto = true
      let pageBytes = model.site?.files[model.page]?.bytes
      let caret = model.writingCaret
      Task { @MainActor in
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
          "WebBench-photo-" + UUID().uuidString)
        var handedOff = false
        defer {
          receivingPhoto = false
          evaluate("webBenchReleasePhoto", [key])
          if !handedOff { try? FileManager.default.removeItem(at: file) }
        }
        do {
          try Data().write(to: file, options: .withoutOverwriting)
          let output = try FileHandle(forWritingTo: file)
          defer { try? output.close() }
          var offset = 0
          model.status = "Preparing " + name + "…"
          while offset < size {
            guard model.preview?.token == target.token else { return }
            let length = min(512 * 1024, size - offset)
            let v = try await web.callAsyncJavaScript(
              "return await window.webBenchPhotoPart(key, offset, length)",
              arguments: ["key": key, "offset": offset, "length": length], in: nil,
              contentWorld: .defaultClient)
            guard let str = v as? String, str.utf8.count <= 700000,
              let data = Data(base64Encoded: str), data.count == length
            else { throw BenchError("The photo drop was interrupted. Drop it again.") }
            try output.write(contentsOf: data)
            offset += length
          }
          try output.synchronize()
          guard model.preview?.token == target.token else { return }
          if state.writing
            && (caret != model.writingCaret || model.site?.files[model.page]?.bytes != pageBytes)
          {
            model.status = "The insertion point moved. Drop the photo again."
            return
          }
          let input = try PhotoInput(url: file, name: name, temporary: true)
          handedOff = true
          model.startPhoto(input, target: target, offer: size > model.photoBudget(target))
        } catch { model.status = error.localizedDescription }
      }
    }
    private var lastScope: Bool?
    private var lastScale: CGFloat?
    private var lastGrid: Bool?
    func paint(_ scope: String, id: Int, color: String, keepImage: Bool) {
      evaluate("webBenchPaint", [scope, id, color, keepImage])
    }
    func center(_ id: Int) { evaluate("webBenchCenter", [id]) }
    func scrub(_ id: Int, axis: String, value: Int, phase: String) {
      guard model.preview?.token == state.token else { return }
      evaluate("webBenchScrub", [id, axis, value, phase])
    }
    var showingImpact = false
    fileprivate weak var scheme: ProjectScheme?
    var sequence = 0
    private var barriers = [String: (run: () -> Void, cancel: (() -> Void)?)]()
    private var assets = [String: [Session.Change]]()
    private func evaluate(_ method: String, _ arguments: [Any]) {
      guard let data = try? JSONSerialization.data(withJSONObject: arguments) else { return }
      let js = "window." + method + "(..." + String(decoding: data, as: UTF8.self) + ")"
      web?.evaluateJavaScript(js, in: nil, in: .defaultClient) { [weak self] result in
        if case .failure(let error) = result, let self,
          self.model.preview?.token == self.state.token
        {
          self.model.status = error.localizedDescription
        }
      }
    }
    func command(_ kind: String, _ value: String) {
      web?.window?.makeFirstResponder(web)
      evaluate("webBenchWrite", [kind, value])
    }
    func image(_ url: String, alt: String, changes: [Session.Change]) {
      let id = UUID().uuidString
      // The imported file and its referencing HTML share one undo group.
      for change in changes {
        if let bytes = change.bytes {
          scheme?.inserted[change.path] = SourceFile(path: change.path, data: bytes, new: true)
        }
      }
      assets.removeAll()
      assets[id] = changes
      web?.window?.makeFirstResponder(web)
      evaluate("webBenchWrite", ["element", "image", ["url": url, "alt": alt, "asset": id]])
    }
    func cancelBarriers() {
      let pending = barriers
      barriers.removeAll()
      for entry in pending.values { entry.cancel?() }
    }
    func afterWriting(_ action: @escaping () -> Void, onFailure: (() -> Void)?) {
      guard web != nil else {
        onFailure?()
        return
      }
      let id = UUID().uuidString
      barriers[id] = (action, onFailure)
      web?.evaluateJavaScript("window.webBenchBarrier('\(id)')", in: nil, in: .defaultClient) {
        [weak self] result in
        if case .failure(let error) = result, let self, self.barriers.removeValue(forKey: id) != nil
        {
          self.model.writer = nil
          onFailure?()
          self.model.status =
            "Writing preview stopped. Retry the command. " + error.localizedDescription
        }
      }
    }
    init(_ model: Session, _ state: PreviewState) {
      self.model = model
      self.state = state
    }
    func sync() {
      guard ready, !state.run, model.safeToEdit, model.preview?.token == state.token else { return }
      let pageDrop = model.hasFreePage && model.dropOnPage
      if lastPageDrop != pageDrop {
        lastPageDrop = pageDrop
        evaluate("webBenchDropOnPage", [pageDrop])
      }
      if state.writing { return }
      let grid = model.gridVisible && model.hasFreePage
      if grid != lastGrid {
        lastGrid = grid
        evaluate("webBenchGrid", [grid])
      }
      let scoped = model.hasFreePage && model.devicePlacement
      if lastScope != scoped {
        lastScope = scoped
        evaluate("webBenchVariant", [scoped])
      }
      if let web, lastScale != web.pageZoom {
        lastScale = web.pageZoom
        evaluate("webBenchScale", [Double(web.pageZoom)])
      }
      if lastTool != model.insertTool || lastSnap != model.snap {
        lastTool = model.insertTool
        lastSnap = model.snap
        evaluate("webBenchTools", [model.insertTool, model.snap])
      }
      if placement != model.freePlacement {
        placement = model.freePlacement
        web?.evaluateJavaScript(
          "window.webBenchPlacement(" + String(model.freePlacement) + ")", in: nil,
          in: .defaultClient, completionHandler: nil)
      }
      if let selector = model.impactRequest, !showingImpact,
        let data = try? JSONEncoder().encode(selector)
      {
        showingImpact = true
        web?.evaluateJavaScript(
          "window.webBenchMatches(" + String(decoding: data, as: UTF8.self) + ")", in: nil,
          in: .defaultClient
        ) { [weak self] result in
          guard let self else { return }
          self.showingImpact = false
          self.model.impactRequest = nil
          guard self.model.preview?.token == self.state.token else { return }
          switch result {
          case .success(let result):
            self.model.reviewTitle = "Affected elements · " + selector
            self.model.diffText = result as? String
          case .failure(let e): self.model.status = e.localizedDescription
          }
        }
      }
      let ids = model.selectedIDs
      let key = "\(ids)/" + model.property
      guard last != key else { return }
      last = key
      evaluate("webBenchSelectMany", [ids, model.property, true])
    }
    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      guard message.frameInfo.isMainFrame, model.preview?.token == state.token else { return }
      if state.run {
        guard message.name == "output", let line = message.body as? String, model.logs.count < 400
        else { return }
        model.logs.append(String(line.prefix(3000)))
        return
      }
      guard let d = message.body as? [String: Any],
        d["token"] as? String == state.token, let kind = d["kind"] as? String
      else { return }
      // Readiness is a view-lifecycle event. A save may temporarily suspend edits while WebKit loads.
      if kind == "paper" {
        if let c = d["color"] as? String, let image = d["image"] as? Bool {
          if model.paperColor != c { model.paperColor = c }
          if model.paperHasImage != image { model.paperHasImage = image }
        }
        return
      }
      if kind == "paint" {
        model.receivePaint(d)
        return
      }
      if kind == "ready" {
        evaluate("webBenchPaper", [])
        ready = true
        if !state.writing {
          model.designer = self
          if model.resumeCanvasFocus {
            model.resumeCanvasFocus = false
            web?.window?.makeFirstResponder(web)
          }
        }
        if state.writing {
          if model.site?.files[state.page]?.bytes != state.files[state.page]?.bytes {
            model.refresh()
            return
          }
          model.writer = self
          if (state.caret != nil || state.writeTarget != nil) && model.mode != .code {
            web?.window?.makeFirstResponder(web)
          }
        }
        sync()
        return
      }
      if kind == "paletteDrop" {
        guard model.safeToEdit, model.mode != .code else { return }
        if state.writing {
          model.afterWriting { [weak self] in
            guard let self, self.model.preview?.token == self.state.token else { return }
            self.model.insertFromCanvas(d)
          }
        } else {
          model.insertFromCanvas(d)
        }
        return
      }
      if kind == "photoFile" || kind == "asset" {
        guard model.safeToEdit, model.mode != .code else { return }
        switch kind {
        case "photoFile":
          if let id = d["id"] as? Int, let key = d["key"] as? String,
            let name = d["name"] as? String, let size = d["size"] as? Int,
            id >= 0, model.nodes.indices.contains(id), size > 0,
            Site.rasterPhotos.contains((name as NSString).pathExtension.lowercased())
          {
            let target = PhotoTarget(
              token: state.token, id: id, before: d["before"] ?? NSNull(),
              point: d["point"] ?? NSNull(), replace: false)
            receivePhoto(key: key, name: name, size: size, target: target)
          }
          return
        case "asset":
          if let id = d["id"] as? Int, let name = d["name"] as? String,
            let b64 = d["data"] as? String,
            b64.utf8.count < 17 * 1024 * 1024, let bytes = Data(base64Encoded: b64)
          {
            model.addAsset(
              name, bytes: bytes, existing: nil, id: id, before: d["before"] ?? NSNull(),
              point: d["point"] ?? NSNull())
          }
        default: break
        }
        return
      }
      if state.writing {
        if kind == "barrier", let id = d["id"] as? String {
          barriers.removeValue(forKey: id)?.run()
          return
        }
        guard model.safeToEdit, model.mode != .code else { return }
        switch kind {
        case "write":
          do {
            guard d["seq"] as? Int == sequence + 1 else {
              throw BenchError("The writing sequence changed. Continue in Code.")
            }
            let key = d["asset"] as? String ?? ""
            var extra: [Session.Change] = []
            if !key.isEmpty {
              guard let staged = assets.removeValue(forKey: key) else {
                throw BenchError("Choose the artwork again.")
              }
              extra = staged
            }
            try model.applyWriting(d, extra: extra)
            sequence += 1
          } catch {
            model.refresh()
            model.codeFallback(error.localizedDescription)
          }
        case "writeSelection":
          if let id = d["id"] as? Int, let a = d["a"] as? Int, let b = d["b"] as? Int,
            a >= 0, b >= a, model.nodes.indices.contains(id)
          {
            var format = Session.WritingFormat(
              bold: d["bold"] as? Bool ?? false, italic: d["italic"] as? Bool ?? false,
              list: d["list"] as? String ?? "", block: d["block"] as? String ?? "",
              href: d["href"] as? String ?? "")
            format.fontFamily = d["fontFamily"] as? String ?? ""
            format.fontSize = d["fontSize"] as? String ?? ""
            format.ink = d["ink"] as? String ?? ""
            format.fill = d["fill"] as? String ?? ""
            format.hasImage = d["hasImage"] as? Bool ?? false
            if model.writingFormat != format { model.writingFormat = format }
            model.selected = id
            model.writingCaret = a
            if model.file == model.page {
              model.reveal(model.page, NSRange(location: a, length: b - a))
            }
          }
        case "writeError":
          model.codeFallback(d["message"] as? String ?? "Continue in Code.", id: d["id"] as? Int)
        case "notice": model.status = d["message"] as? String ?? ""
        case "requestLink": model.writingLink()
        case "returnToLayout": model.setWriting(false)
        case "historyUndo": model.undo()
        case "historyRedo": model.redo()
        default: break
        }
        return
      }
      guard model.safeToEdit else { return }
      let id = d["id"] as? Int
      switch kind {
      case "notice": model.status = d["message"] as? String ?? ""
      case "unmapped":
        model.codeFallback(
          "WebKit repaired or generated this element. Use its source in Code.", id: id)
      case "select":
        if let id, let prop = d["prop"] as? String, prop == model.property {
          last = "\([id])/" + prop
          model.inspect(d)
        }
      case "multiSelect":
        if let ids = d["ids"] as? [Int], d["prop"] as? String == model.property {
          last = "\(ids)/" + model.property
          model.selectGroup(ids)
        }
      case "deselect":
        last = "[]/" + model.property
        model.groupIDs = []
        model.selected = nil
        model.inspection = nil
      case "deleteLayers":
        if d["ids"] as? [Int] == model.selectedIDs { model.deleteLayers() }
      case "flowDrop":
        guard let id, let child = d["child"] as? Int, model.selected == child else { return }
        model.nextScroll = d["scroll"] as? [Double]
        model.resumeCanvasFocus = true
        model.mutate(
          [
            "kind": "relocate", "child": child, "before": d["before"] ?? NSNull(),
            "point": d["point"] ?? NSNull(),
          ], id: id, name: "Move layer")
      case "selectionFrames":
        let names = [
          "move": "Move layers", "left": "Align left", "right": "Align right",
          "centerX": "Align horizontal centers", "top": "Align top", "bottom": "Align bottom",
          "centerY": "Align vertical centers", "spaceX": "Space horizontally",
          "spaceY": "Space vertically",
        ]
        guard let ids = d["ids"] as? [Int], ids.count > 1, ids == model.groupIDs,
          let members = d["members"] as? [[String: Any]],
          members.compactMap({ $0["id"] as? Int }) == ids,
          members.count == ids.count, let command = d["command"] as? String,
          let name = names[command]
        else { return }
        model.nextScroll = d["scroll"] as? [Double]
        model.resumeCanvasFocus = d["canvasFocus"] as? Bool == true
        model.mutate(
          ["kind": "selectionFrames", "members": members, "band": d["band"] as? String ?? ""],
          id: ids[0], name: name)
      case "cancelTool": model.insertTool = ""
      case "writeAt":
        if let id, let offset = d["offset"] as? Int { model.startText(id, offset: offset) }
      case "place": model.insertFromCanvas(d, armed: true)
      case "free":
        guard let id, model.inspection?.id == id, model.inspection?.canLift == true,
          let values = d["values"] as? [String: Int]
        else { return }
        model.nextScroll = d["scroll"] as? [Double]
        model.mutate(["kind": "free", "values": values], id: id, name: "Place layer freely")
      case "frame":
        guard let id, let i = model.inspection, i.id == id, let v = d["values"] as? [String: Int],
          !v.isEmpty,
          v.allSatisfy({ key, value in
            (-1_000_000...1_000_000).contains(value)
              && ((["left", "top", "z-index"].contains(key) && i.canMove)
                || (["width", "height"].contains(key) && i.canResize && value > 0))
          })
        else { return }
        model.nextScroll = d["scroll"] as? [Double]
        model.resumeCanvasFocus = d["canvasFocus"] as? Bool == true
        model.mutate(
          [
            "kind": "frame", "values": v, "band": d["band"] as? String ?? "",
            "promote": d["promote"] as? Bool == true,
          ], id: id,
          name: "Arrange " + i.label)
      case "move":
        if let id, model.inspection?.id == id, model.inspection?.canMove == true,
          let x = d["x"] as? Double, let y = d["y"] as? Double, x.isFinite, y.isFinite
        {
          model.mutate(["kind": "move", "x": x, "y": y], id: id, name: "Move positioned object")
        }
      case "drop":
        guard let id, let item = d["item"] as? String else { return }
        if item.hasPrefix("Node/") {
          let parts = item.split(separator: "/")
          guard parts.count == 3, parts[1] == state.token, let child = Int(parts[2]) else { return }
          model.mutate(
            [
              "kind": "relocate", "child": child, "before": d["before"] ?? NSNull(),
              "point": d["point"] ?? NSNull(),
            ],
            id: id, name: "Move layer")
        } else if item.hasPrefix("Asset/") {
          let path = String(item.dropFirst(6))
          if state.files[path] != nil || state.linkedAssets.contains(path) {
            model.addAsset(
              path, bytes: nil, existing: path, id: id, before: d["before"] ?? NSNull(),
              point: d["point"] ?? NSNull())
          }
        } else if item == "Image" {
          model.pickImage(at: id, before: d["before"] ?? NSNull(), point: d["point"] ?? NSNull())
        } else {
          model.mutate(
            [
              "kind": "insert", "item": item, "before": d["before"] ?? NSNull(),
              "point": d["point"] ?? NSNull(),
            ], id: id, name: "Insert " + item)
        }
      default: break
      }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      // Page cards reuse the first rendered viewport. Visiting a site never starts extra page scripts.
      guard !state.run, !state.writing, model.selected == nil, model.pageImages[state.page] == nil,
        webView.bounds.width > 1, webView.bounds.height > 1
      else { return }
      let config = WKSnapshotConfiguration()
      config.snapshotWidth = 196
      config.rect = CGRect(
        x: 0, y: 0, width: webView.bounds.width,
        height: min(webView.bounds.height, webView.bounds.width * 0.52))
      webView.takeSnapshot(with: config) { [weak self] image, _ in
        guard let self, let image, self.model.preview?.token == self.state.token,
          self.model.selected == nil
        else { return }
        self.model.addPageImage(image, path: self.state.page)
      }
    }
    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard action.targetFrame?.isMainFrame == true, let url = action.request.url,
        url.scheme == "webbench", url.host == "project"
      else {
        decisionHandler(.cancel)
        return
      }
      let p = String(url.path.dropFirst())
      decisionHandler(p == state.page || (state.run && state.files[p] != nil) ? .allow : .cancel)
    }
    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      guard model.preview?.token == state.token, (error as NSError).code != NSURLErrorCancelled
      else { return }
      model.status = error.localizedDescription
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      guard state.token == model.preview?.token else { return }
      cancelBarriers()
      if model.writer === self { model.writer = nil }
      model.status = "Preview stopped. Switch Edit / Run to reload your source."

    }
  }
}
