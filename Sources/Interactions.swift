import AppKit
import SwiftUI

enum ActionKind: String, CaseIterable, Codable {
  case text, color, background, show, hide, toggle, dialog, download, downloadText, chooseFile, upload

  var title: String {
    switch self {
    case .text: return "Change text"
    case .color: return "Change text color"
    case .background: return "Change background color"
    case .show: return "Show element"
    case .hide: return "Hide element"
    case .toggle: return "Toggle visibility"
    case .dialog: return "Open a dialog"
    case .download: return "Download a site file"
    case .downloadText: return "Download a text file"
    case .chooseFile: return "Choose a file and show its name"
    case .upload: return "Upload a file"
    }
  }
  var needsTarget: Bool { [.text, .color, .background, .show, .hide, .toggle, .chooseFile].contains(self) }
  var symbol: String {
    switch self {
    case .text: return "textformat"
    case .color, .background: return "paintpalette"
    case .show, .hide, .toggle: return "eye"
    case .dialog: return "macwindow"
    case .download, .downloadText: return "arrow.down.doc"
    case .chooseFile: return "folder"
    case .upload: return "arrow.up.doc"
    }
  }
}

struct InteractionStep: Decodable, Identifiable, Equatable {
  let id = UUID()
  var kind: ActionKind, target: Int, value: String, detail: String
  enum CodingKeys: String, CodingKey { case kind, target, value, detail }
  init(_ kind: ActionKind) {
    self.kind = kind
    target = -1
    value = ""
    detail = ""
    switch kind {
    case .color, .background: value = "#33634F"
    case .dialog: value = "Message"
    case .upload: detail = "file"
    case .downloadText: value = "readout.txt"
    default: break
    }
  }
  var payload: [String: Any] {
    ["kind": kind.rawValue, "target": target, "value": value, "detail": detail]
  }
}

struct InteractionRecord: Decodable, Identifiable {
  let key: String, trigger: Int, label: String, event: String, preventDefault: Bool
  let steps: [InteractionStep]
  var id: String { key }
}

struct InteractionCatalog: Decodable {
  let elements: [Int], flows: [InteractionRecord]
}

enum InteractionPick: Equatable { case trigger, target(UUID) }

final class InteractionDraft: ObservableObject {
  let page: String, original: Data, rows: [ElementRow], catalog: InteractionCatalog
  @Published var key = ""
  @Published var trigger = -1
  @Published var event = "click"
  @Published var preventDefault = true
  @Published var steps = [InteractionStep]()
  @Published var picking: InteractionPick?
  @Published var issue = ""
  var existing: Bool { catalog.flows.contains { $0.key == key } }
  private var initial = ""
  init(page: String, bytes: Data, rows: [ElementRow], catalog: InteractionCatalog, selected: Int?) {
    self.page = page
    original = bytes
    let eligible = Set(catalog.elements)
    self.rows = rows.filter { eligible.contains($0.id) }
    self.catalog = catalog
    let initialTrigger = selected.flatMap { eligible.contains($0) ? $0 : nil }
    load(catalog.flows.first { $0.trigger == initialTrigger }, trigger: initialTrigger)
  }
  func load(_ record: InteractionRecord?, trigger selected: Int? = nil) {
    key = record?.key ?? UUID().uuidString.lowercased()
    trigger = record?.trigger ?? selected ?? -1
    event = record?.event ?? "click"
    preventDefault = record?.preventDefault ?? true
    steps = record?.steps ?? [InteractionStep(.text)]
    issue = ""
    picking = trigger < 0 ? .trigger : nil
    initial = fingerprint
  }
  var payload: [String: Any] {
    ["key": key, "existing": existing, "trigger": trigger, "event": event,
     "preventDefault": preventDefault, "steps": steps.map(\.payload)]
  }
  private var fingerprint: String {
    (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).base64EncodedString()) ?? ""
  }
  var dirty: Bool { initial != fingerprint }
  func label(_ id: Int) -> String {
    guard let row = rows.first(where: { $0.id == id }) else { return "Choose element" }
    return row.name == row.tag || row.name == row.label ? row.label : "\(row.name) · \(row.label)"
  }
  func pick(_ id: Int, for role: InteractionPick) {
    guard rows.contains(where: { $0.id == id }) else {
      issue = "Choose a source element inside the page body."
      return
    }
    switch role {
    case .trigger: trigger = id
    case .target(let uuid):
      guard let index = steps.firstIndex(where: { $0.id == uuid }) else { return }
      steps[index].target = id
    }
    picking = nil
    issue = ""
  }
}

extension Session {
  func openInteractions() {
    guard workflow == nil, !running, !busy, let engine, let file = site?.files[page], let source = file.text else { return }
    let selectedID = selected
    do {
      let catalog = try engine.call("workflows", [source], as: InteractionCatalog.self)
      guard !catalog.elements.isEmpty else { status = "Add a button or another page element to start an interaction."; return }
      if writing { setWriting(false) }
      mode = .design
      if !safeToEdit { render() }
      insertTool = ""
      groupIDs = []
      workflow = InteractionDraft(page: page, bytes: file.bytes, rows: nodes, catalog: catalog, selected: selectedID)
    } catch {
      codeFallback(error.localizedDescription)
      let range = try? engine.call("workflowIssueRange", [source], as: [Int].self)
      if let range, range.count == 2 { reveal(page, NSRange(location: range[0], length: range[1])) }
      else { reveal(page, NSRange(location: 0, length: 0)) }
    }
  }

  func finishInteraction(_ draft: InteractionDraft, remove: Bool = false, preview run: Bool = false) {
    guard workflow === draft else { return }
    guard let engine, let file = site?.files[page], let source = file.text, !running, safeToEdit,
          page == draft.page, file.bytes == draft.original else {
      draft.issue = "The page changed. Close Interactions and reopen it to use the current source."
      return
    }
    var request = draft.payload
    request["remove"] = remove
    do {
      let result = try engine.call("editWorkflow", [source, request], as: EditResult.self)
      let bytes = try file.encoded(result.text)
      workflow = nil
      change([Change(path: page, bytes: bytes)], remove ? "Remove interaction" : "Apply interaction", focus: result.focus)
      if run { setRun(true) }
    } catch { draft.issue = error.localizedDescription }
  }

  func discardInteractionEdits() -> Bool {
    guard let workflow, workflow.dirty else { return true }
    let alert = NSAlert()
    alert.messageText = "Discard this interaction draft?"
    alert.informativeText = "Apply the workflow to keep your changes in the page."
    alert.addButton(withTitle: "Keep editing")
    alert.addButton(withTitle: "Discard draft")
    return alert.runModal() == .alertSecondButtonReturn
  }
}

struct InteractionWorkbench<Surface: View>: View {
  @ObservedObject var model: Session
  @ObservedObject var draft: InteractionDraft
  @ViewBuilder let surface: () -> Surface
  @State private var confirmRemove = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        BenchMark()
        Text("Interactions").font(.system(size: 21, weight: .semibold, design: .serif))
        Text(draft.page).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
        Spacer()
        Button("Cancel") { if model.discardInteractionEdits() { model.workflow = nil } }
        Button("Apply") { model.finishInteraction(draft) }.disabled(draft.steps.isEmpty)
        Button { model.finishInteraction(draft, preview: true) } label: {
          Label("Apply & preview", systemImage: "play.fill")
            .font(.callout.bold()).foregroundStyle(StudioInk.forest)
            .padding(.horizontal, 12).frame(height: 29).background(StudioInk.lime, in: Capsule())
        }.buttonStyle(.plain).disabled(draft.steps.isEmpty)
      }.padding(.horizontal, 14).frame(height: 52)
        .background(StudioInk.forest).environment(\.colorScheme, .dark)
      HSplitView {
        VStack(spacing: 0) {
          HStack {
            Image(systemName: draft.picking == nil ? "doc.richtext" : "scope")
            Text(pickHint)
            Spacer()
            if draft.picking != nil { Button("Cancel pick") { draft.picking = nil } }
          }.font(.callout).padding(.horizontal, 12).frame(height: 36)
            .background(StudioInk.green.opacity(0.10))
          surface()
        }.frame(minWidth: 290, maxWidth: .infinity)
        panel.frame(minWidth: 335, idealWidth: 395, maxWidth: 535)
      }
    }
    .alert("Remove this workflow?", isPresented: $confirmRemove) {
      Button("Remove", role: .destructive) { model.finishInteraction(draft, remove: true) }
      Button("Cancel", role: .cancel) {}
    } message: { Text("You can restore it with Edit → Undo.") }
  }

  private var pickHint: String {
    switch draft.picking {
    case .trigger: return "Click the element that starts this workflow."
    case .target: return "Click the element this action should change."
    case nil: return "Page canvas"
    }
  }
  private var panel: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Workflow").font(.system(size: 18, weight: .semibold, design: .serif))
        Spacer()
        Menu("Page workflows") {
          Button("New workflow") { if model.discardInteractionEdits() { draft.load(nil) } }
          if !draft.catalog.flows.isEmpty { Divider() }
          ForEach(draft.catalog.flows) { f in
            Button((f.trigger < 0 ? f.label + " (missing)" : draft.label(f.trigger)) + " · " + f.event) {
              if model.discardInteractionEdits() { draft.load(f); if f.trigger >= 0 { model.select(f.trigger) } }
            }
          }
        }.fixedSize()
      }.padding(12)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 8) {
            Label("When", systemImage: "bolt.fill").font(.headline).foregroundStyle(StudioInk.clay)
            target(draft.trigger, role: .trigger)
            Picker("Event", selection: $draft.event) {
              Text("Clicked or tapped").tag("click")
              Text("Value committed").tag("change")
              Text("Value changes").tag("input")
            }
            if draft.event == "click" {
              Toggle("Replace default link or form action", isOn: $draft.preventDefault).font(.caption)
            }
          }.padding(12).background(StudioInk.card, in: RoundedRectangle(cornerRadius: 9))
          HStack {
            Text("Then").font(.headline).foregroundStyle(StudioInk.green)
            Spacer()
            Menu {
              ForEach(ActionKind.allCases, id: \.self) { kind in
                Button { draft.steps.append(InteractionStep(kind)) } label: { Label(kind.title, systemImage: kind.symbol) }
              }
            } label: { Label("Add action", systemImage: "plus") }
              .fixedSize().disabled(draft.steps.count >= 64)
          }
          ForEach($draft.steps) { $step in
            actionCard($step)
          }
          if draft.existing {
            Button("Remove workflow…", role: .destructive) { confirmRemove = true }
          }
        }.padding(12)
      }
      if !draft.issue.isEmpty {
        Divider()
        Label(draft.issue, systemImage: "exclamationmark.triangle").font(.callout)
          .foregroundStyle(.primary).textSelection(.enabled).padding(12)
      }
    }.background(StudioInk.paper)
  }

  private func target(_ selected: Int, role: InteractionPick) -> some View {
    HStack(spacing: 6) {
      InteractionElementList(rows: draft.rows, selected: selected, title: draft.label(selected)) { id in
        draft.pick(id, for: role)
        model.select(id)
      }.accessibilityLabel(role == .trigger ? "Trigger element" : "Action target")
      Button { draft.picking = draft.picking == role ? nil : role } label: {
        Label("Pick", systemImage: "scope")
      }.tint(draft.picking == role ? StudioInk.clay : StudioInk.green)
        .help("Pick this element directly on the canvas")
    }
  }

  private func actionCard(_ binding: Binding<InteractionStep>) -> some View {
    let step = binding.wrappedValue
    let index = draft.steps.firstIndex(where: { $0.id == step.id }) ?? 0
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(String(index + 1)).font(.caption.bold().monospacedDigit()).foregroundStyle(StudioInk.green)
          .frame(width: 22, height: 22).background(StudioInk.green.opacity(0.12), in: Circle())
        Menu {
          ForEach(ActionKind.allCases, id: \.self) { kind in
            Button(kind.title) { if kind != step.kind { binding.wrappedValue = InteractionStep(kind); draft.picking = nil } }
          }
        } label: { Text(step.kind.title).font(.headline) }.menuStyle(.borderlessButton)
        Spacer(minLength: 0)
        Menu {
          Button("Move earlier") { draft.steps.swapAt(index, index - 1) }.disabled(index == 0)
          Button("Move later") { draft.steps.swapAt(index, index + 1) }.disabled(index + 1 >= draft.steps.count)
          Divider()
          Button("Remove action", role: .destructive) { draft.steps.removeAll { $0.id == step.id }; draft.picking = nil }
        } label: { Image(systemName: "ellipsis.circle") }.fixedSize().accessibilityLabel("Options for step " + String(index + 1))
      }
      if step.kind.needsTarget { target(step.target, role: .target(step.id)) }
      switch step.kind {
      case .text:
        field("New text", binding.value)
        if draft.rows.contains(where: { $0.parent == step.target }) {
          Text("This replaces the element’s nested content when the action runs.").font(.caption).foregroundStyle(.secondary)
        }
      case .color, .background:
        HStack {
          ColorPicker("Color", selection: Binding(get: {
            let rgb = UInt32(step.value.dropFirst(), radix: 16) ?? 0
            return Color(.sRGB, red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255,
                         blue: Double(rgb & 255) / 255, opacity: 1)
          }, set: { binding.wrappedValue.value = "#" + PaintControl.hexValue($0) }), supportsOpacity: false)
          Text(step.value).font(.caption.monospaced())
        }
      case .dialog: field("Dialog title", binding.value); field("Message", binding.detail)
      case .download:
        field("Relative file path", binding.value)
        Menu("Choose project file…") {
          ForEach(model.site?.workspacePaths ?? [], id: \.self) { path in
            Button(path) { binding.wrappedValue.value = Site.relative(path, from: draft.page) }
          }
        }
        field("Save as (optional)", binding.detail)
        Text("Keep the file with your website. For a self-contained HTML download, choose Download a text file.").font(.caption).foregroundStyle(.secondary)
      case .downloadText: field("File name", binding.value); field("File contents", binding.detail)
      case .upload:
        field("Server upload address", binding.value)
        field("File field name", binding.detail)
        Text("Preview rehearses the upload locally. The published page sends the chosen file to this address using multipart POST.")
          .font(.caption).foregroundStyle(.secondary)
      default: EmptyView()
      }
    }.padding(11).background(StudioInk.card, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(StudioInk.line, lineWidth: 1))
  }

  private func field(_ title: String, _ value: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      TextField(title, text: value, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
    }
  }
}

private struct InteractionElementList: View {
  let rows: [ElementRow], selected: Int, title: String
  let choose: (Int) -> Void
  @State private var open = false
  @State private var query = ""

  var body: some View {
    Button {
      query = ""
      open = true
    } label: {
      HStack {
        Text(title).lineLimit(1).truncationMode(.middle)
        Spacer()
        Image(systemName: "chevron.down").font(.caption2)
      }
    }.popover(isPresented: $open) {
      VStack(alignment: .leading, spacing: 6) {
        TextField("Find an element", text: $query).textFieldStyle(.roundedBorder)
        let matches = rows.filter { query.isEmpty || ($0.name + " " + $0.label).localizedCaseInsensitiveContains(query) }
        if matches.isEmpty { Text("No matching elements").foregroundStyle(.secondary) }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(matches) { row in
              Button {
                choose(row.id)
                open = false
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).lineLimit(1)
                    Text(row.label).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                  }
                  Spacer()
                  if row.id == selected { Image(systemName: "checkmark") }
                }.padding(4).contentShape(Rectangle())
              }.buttonStyle(.plain)
            }
          }
        }
      }.padding(12).frame(width: 280, height: 300)
    }
  }
}
