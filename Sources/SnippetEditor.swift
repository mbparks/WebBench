import AppKit
import SwiftUI

enum SnippetKind: String, Decodable {
  case code, html, iframe

  init?(item: String) {
    switch item {
    case "Code snippet": self = .code
    case "Custom HTML": self = .html
    case "Iframe embed": self = .iframe
    default: return nil
    }
  }
  var title: String {
    switch self {
    case .code: return "Code snippet"
    case .html: return "Custom HTML"
    case .iframe: return "Iframe embed"
    }
  }
}

struct SnippetDetails: Decodable {
  let kind: SnippetKind, text: String
  var url: String?, title: String?, fields: Bool?
}

final class SnippetDraft: ObservableObject, Identifiable {
  let id = UUID()
  let page: String, original: Data, node: Int, existing: Bool
  let placement: [String: Any], details: SnippetDetails
  @Published var text: String
  @Published var url: String
  @Published var title: String
  @Published var fields: Bool
  @Published var issue = ""

  init(page: String, original: Data, node: Int, existing: Bool, placement: [String: Any], details: SnippetDetails) {
    self.page = page
    self.original = original
    self.node = node
    self.existing = existing
    self.placement = placement
    self.details = details
    text = details.text
    url = details.url ?? ""
    title = details.title ?? ""
    fields = details.fields ?? false
  }
}

extension Session {
  func snippetNode(at id: Int) -> ElementRow? {
    var candidate = id
    while nodes.indices.contains(candidate) {
      let row = nodes[candidate]
      if row.snippet != nil { return row }
      candidate = row.parent
    }
    return nil
  }

  func openSnippet(at id: Int, adding kind: SnippetKind? = nil, placement: [String: Any] = [:]) {
    guard safeToEdit, mode != .code, let engine, let current = site?.files[page], let source = current.text else { return }
    do {
      let node: Int, details: SnippetDetails
      if let kind {
        node = id
        switch kind {
        case .code: details = SnippetDetails(kind: kind, text: "const reading = 12.5;")
        case .html: details = SnippetDetails(kind: kind, text: "<p>Custom content</p>")
        case .iframe:
          details = SnippetDetails(kind: kind, text: "", url: "", title: "Embedded page", fields: true)
        }
      } else {
        guard let owner = snippetNode(at: id) else { return }
        node = owner.id
        details = try engine.call("snippetDetails", [source, node], as: SnippetDetails.self)
      }
      snippetEditor = SnippetDraft(page: page, original: current.bytes, node: node, existing: kind == nil,
                                   placement: placement, details: details)
    } catch { codeFallback(error.localizedDescription, id: snippetNode(at: id)?.id ?? id) }
  }

  func applySnippet(_ draft: SnippetDraft) {
    guard snippetEditor === draft, safeToEdit, page == draft.page, let engine,
          let current = site?.files[page], current.bytes == draft.original, let source = current.text else {
      draft.issue = "The page changed. Copy your draft, then reopen this editor on the current source."
      return
    }
    var request = draft.placement
    request["kind"] = "snippet"
    request["type"] = draft.details.kind.rawValue
    request["text"] = draft.text
    request["existing"] = draft.existing
    request["fields"] = draft.fields
    request["url"] = draft.url
    request["title"] = draft.title
    do {
      let result = try engine.call("run", [source, draft.node, request], as: EditResult.self)
      let bytes = try current.encoded(result.text)
      snippetEditor = nil
      if bytes != current.bytes {
        change([Change(path: page, bytes: bytes)], (draft.existing ? "Edit " : "Insert ") + draft.details.kind.title, focus: result.focus)
      }
    } catch { draft.issue = error.localizedDescription }
  }

  func previewInBrowser() {
    guard !busy, let snapshot = site, snapshot.files[page] != nil else { return }
    let entry = page
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("WebBench-" + UUID().uuidString)
    busy = true
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result { try snapshot.exportWebsite(to: root, entry: entry) }
      DispatchQueue.main.async {
        self.busy = false
        do {
          try result.get()
          let file = root.appendingPathComponent(entry)
          guard let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com/")!) else {
            NSWorkspace.shared.activateFileViewerSelecting([file])
            throw BenchError("Choose a browser to open the selected preview file.")
          }
          NSWorkspace.shared.open([file], withApplicationAt: browser, configuration: .init()) { _,error in
            DispatchQueue.main.async {
              if let error { self.alert(error.localizedDescription) }
              else { self.status = "Opened a temporary website snapshot in your browser." }
            }
          }
        } catch { self.alert(error.localizedDescription) }
      }
    }
  }
}

struct SnippetEditor: View {
  @ObservedObject var model: Session
  @ObservedObject var draft: SnippetDraft
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(draft.details.kind.title).font(.system(size: 25, weight: .semibold, design: .serif))
      switch draft.details.kind {
      case .code:
        Text("Paste the code visitors should be able to read and copy.")
      case .html:
        Text("Paste an HTML fragment. Put CSS in <style> and JavaScript in <script>. Scripts run in Preview and on the exported page.")
      case .iframe:
        if !draft.existing {
          Picker("Input", selection: $draft.fields) {
            Text("Embed URL").tag(true)
            Text("Paste embed code").tag(false)
          }.pickerStyle(.segmented)
        } else if draft.details.fields == true {
          Picker("Edit", selection: $draft.fields) {
            Text("URL and title").tag(true)
            Text("Embed code").tag(false)
          }.pickerStyle(.segmented)
          .disabled(draft.text != draft.details.text || draft.url != draft.details.url || draft.title != draft.details.title)
          .help("Apply changes in the current view before switching formats.")
        }
      }
      if draft.details.kind == .iframe && draft.fields {
        TextField("Embed URL or relative path", text: $draft.url).textFieldStyle(.roundedBorder)
        let paths = (model.site?.pages ?? []).filter { $0 != draft.page }
        if !paths.isEmpty {
          Menu("Choose a project page…") {
            ForEach(paths, id: \.self) { path in
              Button(path) { draft.url = Site.relative(path, from: draft.page) }
            }
          }
        }
        TextField("Accessible title", text: $draft.title).textFieldStyle(.roundedBorder)
      } else {
        SnippetText(text: $draft.text)
          .frame(minHeight: 215).overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.35)))
          .accessibilityLabel(draft.details.kind == .code ? "Code to display" : "HTML source")
      }
      if draft.details.kind == .iframe {
        Text("Preview can load project pages and inline frames. For an online provider, use File → Preview Website in Browser.")
          .font(.callout).foregroundStyle(.secondary)
      }
      if !draft.issue.isEmpty {
        Label(draft.issue, systemImage: "exclamationmark.triangle").font(.callout).textSelection(.enabled)
      }
      HStack {
        Spacer()
        Button("Cancel") { model.snippetEditor = nil }.keyboardShortcut(.cancelAction)
        Button(draft.existing ? "Apply" : "Insert") { model.applySnippet(draft) }.keyboardShortcut(.defaultAction)
      }
    }.padding(22).frame(minWidth: 520, idealWidth: 610)
  }
}

private struct SnippetText: NSViewRepresentable {
  @Binding var text: String
  final class Coordinator: NSObject, NSTextViewDelegate {
    let value: Binding<String>
    init(_ value: Binding<String>) { self.value = value }
    func textDidChange(_ notification: Notification) {
      if let editor = notification.object as? NSTextView { value.wrappedValue = editor.string }
    }
  }
  func makeCoordinator() -> Coordinator { Coordinator($text) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    guard let editor = scroll.documentView as? NSTextView else { return scroll }
    editor.isRichText = false
    editor.allowsUndo = true
    editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.textContainerInset = NSSize(width: 8, height: 8)
    editor.string = text
    editor.delegate = context.coordinator
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    if let editor = scroll.documentView as? NSTextView, !editor.string.utf8.elementsEqual(text.utf8) {
      editor.string = text
    }
  }
}
