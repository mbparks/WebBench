import AppKit
import SwiftUI

enum ActionKind: String, CaseIterable, Codable {
  case text, color, background, show, hide, toggle, dialog, download, downloadText, chooseFile, upload

  case copyValue, calculate, classChange, enabled, checked, focus, scroll, resetForm, disclosure, mediaControl

  case serialOpen, serialRead, serialWrite, serialClose
  case usbOpen, usbRead, usbWrite, usbClose
  case cameraStart, cameraSnapshot, cameraStop
  case micStart, micStop

  static let groups: [(String, [Self])] = [
    ("Values and math", [.text, .copyValue, .calculate]),
    ("Appearance", [.color, .background, .classChange, .show, .hide, .toggle]),
    ("Forms", [.enabled, .checked, .resetForm, .focus]),
    ("Page and media", [.dialog, .disclosure, .scroll, .mediaControl]),
    ("Files", [.download, .downloadText, .chooseFile, .upload]),
    ("Serial port", [.serialOpen, .serialRead, .serialWrite, .serialClose]),
    ("USB device", [.usbOpen, .usbRead, .usbWrite, .usbClose]),
    ("Camera", [.cameraStart, .cameraSnapshot, .cameraStop]),
    ("Microphone", [.micStart, .micStop])
  ]

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
    case .copyValue: return "Copy a live value"
    case .calculate: return "Calculate a result"
    case .classChange: return "Change a CSS class"
    case .enabled: return "Enable or disable a control"
    case .checked: return "Set a checkbox or radio button"
    case .focus: return "Focus an element"
    case .scroll: return "Scroll to an element"
    case .resetForm: return "Reset a form"
    case .disclosure: return "Open or close details"
    case .serialOpen: return "Connect a serial port"
    case .serialRead: return "Read a line of serial text"
    case .serialWrite: return "Send serial text"
    case .serialClose: return "Disconnect serial port"
    case .usbOpen: return "Connect a USB device"
    case .usbRead: return "Read USB bytes"
    case .usbWrite: return "Send USB bytes"
    case .usbClose: return "Disconnect USB device"
    case .cameraStart: return "Show live camera"
    case .cameraSnapshot: return "Take a snapshot"
    case .cameraStop: return "Stop camera"
    case .micStart: return "Show microphone level"
    case .micStop: return "Stop microphone"
    case .mediaControl: return "Play or pause media"
    }
  }
  var needsTarget: Bool { ![.dialog, .download, .downloadText, .upload, .serialOpen, .serialClose, .serialWrite, .usbOpen, .usbClose, .usbWrite, .cameraStop, .micStop].contains(self) }
  var symbol: String {
    switch self {
    case .text: return "textformat"
    case .color, .background: return "paintpalette"
    case .show, .hide, .toggle: return "eye"
    case .dialog: return "macwindow"
    case .download, .downloadText: return "arrow.down.doc"
    case .chooseFile: return "folder"
    case .upload: return "arrow.up.doc"
    case .copyValue: return "doc.on.doc"
    case .calculate: return "plus.forwardslash.minus"
    case .classChange: return "paintbrush"
    case .enabled, .checked, .resetForm: return "checklist"
    case .focus: return "scope"
    case .scroll: return "arrow.down.to.line"
    case .disclosure: return "chevron.down.square"
    case .serialOpen, .serialRead, .serialWrite, .serialClose: return "cable.connector"
    case .usbOpen, .usbRead, .usbWrite, .usbClose: return "externaldrive.connected.to.line.below"
    case .cameraStart, .cameraSnapshot, .cameraStop: return "camera"
    case .micStart, .micStop: return "mic"
    case .mediaControl: return "playpause"
    }
  }
}

struct InteractionStep: Decodable, Identifiable, Equatable {
  let id = UUID()
  var kind: ActionKind, target: Int, value: String, detail: String
  var input: Int?, operand: Int?, constant: String?, digits: Int?, invalid: String?
  var settings: [String: String]?
  enum CodingKeys: String, CodingKey { case kind, target, value, detail, input, operand, constant, digits, invalid, settings }
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
    case .copyValue: input = -1
    case .calculate:
      input = -1; operand = -1; value = "multiply"; digits = -1; invalid = "Check the input values."
    case .classChange: value = "toggle"
    case .enabled: value = "enable"
    case .checked, .disclosure: value = "toggle"
    case .serialOpen: value = "115200"
    case .serialWrite: detail = "lf"
    case .usbOpen: settings = ["vendor": "", "product": "", "configuration": "1", "interface": "0", "alternate": "0"]
    case .usbRead: value = "1"; detail = "64"
    case .usbWrite: value = "1"; detail = "01 0A"
    case .mediaControl: value = "play"
    default: break
    }
  }
  var payload: [String: Any] {
    var result: [String: Any] = ["kind": kind.rawValue, "target": target, "value": value, "detail": detail]
    result["input"] = input
    result["operand"] = constant == nil ? operand : nil
    result["constant"] = constant
    result["digits"] = digits
    result["invalid"] = invalid
    result["settings"] = settings
    return result
  }
}

struct InteractionCondition: Decodable {
  var source = -1, test = "filled", value = ""
  var payload: [String: Any] { ["source": source, "test": test, "value": value] }
}

struct InteractionRecord: Decodable, Identifiable {
  let key: String, trigger: Int, label: String, event: String, preventDefault: Bool
  let steps: [InteractionStep], otherwise: [InteractionStep]?
  let condition: InteractionCondition?
  var id: String { key }
}

struct InteractionCatalog: Decodable {
  let elements: [Int], flows: [InteractionRecord], choices: [String: [Int]], classes: [String]
}

enum InteractionPick: Equatable {
  case trigger, condition, target(UUID), input(UUID), operand(UUID)
  var label: String {
    switch self {
    case .trigger: return "Trigger element"
    case .condition: return "Condition element"
    case .target: return "Action target"
    case .input: return "Source value"
    case .operand: return "Second value"
    }
  }
}

final class InteractionDraft: ObservableObject {
  let page: String, original: Data, rows: [ElementRow], catalog: InteractionCatalog
  @Published var key = ""
  @Published var trigger = -1
  @Published var event = "click"
  @Published var preventDefault = true
  @Published var steps = [InteractionStep]()
  @Published var otherwise = [InteractionStep]()
  @Published var conditional = false
  @Published var condition = InteractionCondition()
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
    otherwise = record?.otherwise ?? []
    condition = record?.condition ?? InteractionCondition()
    conditional = record?.condition != nil
    issue = ""
    picking = trigger < 0 ? .trigger : nil
    initial = fingerprint
  }
  var payload: [String: Any] {
    var result: [String: Any] = ["key": key, "existing": existing, "trigger": trigger, "event": event,
                                 "preventDefault": preventDefault, "steps": steps.map(\.payload)]
    if conditional {
      result["condition"] = condition.payload
      result["otherwise"] = otherwise.map(\.payload)
    }
    return result
  }
  private var fingerprint: String {
    (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).base64EncodedString()) ?? ""
  }
  var dirty: Bool { initial != fingerprint }
  func label(_ id: Int) -> String {
    guard let row = rows.first(where: { $0.id == id }) else { return "Choose element" }
    return row.name == row.tag || row.name == row.label ? row.label : "\(row.name) · \(row.label)"
  }
  private func targetKind(for role: InteractionPick) -> String? {
    switch role {
    case .trigger: return event == "submit" ? "form" : nil
    case .condition: return ["checked", "valid"].contains(condition.test) ? condition.test : nil
    case .target(let id):
      let step = steps.first { $0.id == id } ?? otherwise.first { $0.id == id }
      switch step?.kind {
      case .cameraStart: return "video"
      case .cameraSnapshot: return "image"
      case .micStart: return "level"
      case .serialRead, .usbRead: return "reading"
      case .resetForm: return "form"
      case .checked: return "checked"
      case .enabled: return "control"
      case .disclosure: return "details"
      case .mediaControl: return "media"
      default: return nil
      }
    default: return nil
    }
  }
  func candidates(for role: InteractionPick) -> [ElementRow] {
    guard let kind = targetKind(for: role) else { return rows }
    let permitted = Set(catalog.choices[kind] ?? [])
    return rows.filter { permitted.contains($0.id) }
  }
  @discardableResult func pick(_ clicked: Int, for role: InteractionPick) -> Int? {
    var candidate = rows.first { $0.id == clicked }
    if let kind = targetKind(for: role) {
      let permitted = Set(catalog.choices[kind] ?? [])
      while let row = candidate, !permitted.contains(row.id) { candidate = rows.first { $0.id == row.parent } }
    }
    guard let id = candidate?.id else {
      issue = "This element cannot be used here. Open the element list to choose a compatible target."
      return nil
    }
    switch role {
    case .trigger: trigger = id
    case .condition: condition.source = id
    case .target(let uuid), .input(let uuid), .operand(let uuid):
      func assign(_ step: inout InteractionStep) {
        switch role {
        case .input: step.input = id
        case .operand: step.operand = id
        default: step.target = id
        }
      }
      if let index = steps.firstIndex(where: { $0.id == uuid }) { assign(&steps[index]) }
      else if let index = otherwise.firstIndex(where: { $0.id == uuid }) { assign(&otherwise[index]) }
      else { return nil }
    }
    picking = nil
    issue = ""
    return id
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
    case .condition: return "Click the element to check."
    case .input: return "Click the element to read."
    case .operand: return "Click the second value for the calculation."
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
              Text("Form submitted").tag("submit")
              Text("Double-clicked").tag("dblclick")
              Text("Gains focus").tag("focus")
              Text("Loses focus").tag("blur")
              Text("Pointer enters").tag("pointerenter")
              Text("Pointer leaves").tag("pointerleave")
              Text("Enter key pressed").tag("enterKey")
              Text("Escape key pressed").tag("escapeKey")
            }.onChange(of: draft.event) { _, event in
              if event == "submit", let form = draft.pick(draft.trigger, for: .trigger) { model.select(form) }
              else if event == "submit" { draft.trigger = -1; draft.picking = .trigger }
            }
            if draft.event == "click" || draft.event == "submit" {
              Toggle(draft.event == "submit" ? "Handle submission in this workflow" : "Replace default link or form action", isOn: $draft.preventDefault).font(.caption)
            }
          }.padding(12).background(StudioInk.card, in: RoundedRectangle(cornerRadius: 9))
          conditionCard
          branch("Then", steps: $draft.steps)
          if draft.conditional { branch("Otherwise", steps: $draft.otherwise) }
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

  private var conditionCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle("Check a condition", isOn: $draft.conditional).font(.headline)
        .onChange(of: draft.conditional) { _, _ in draft.picking = nil }
      if draft.conditional {
        target(draft.condition.source, role: .condition)
        choices("If this element", $draft.condition.test, [
          ("filled","Has a value"), ("empty","Is empty"), ("equals","Equals text"),
          ("contains","Contains text"), ("greater","Is greater than"), ("less","Is less than"),
          ("checked","Is checked"), ("valid","Passes form validation")
        ])
        if ["equals","contains","greater","less"].contains(draft.condition.test) {
          field("Compare with", $draft.condition.value)
        }
      } else if !draft.otherwise.isEmpty {
        Text("Applying with the condition off removes the Otherwise branch.").font(.caption).foregroundStyle(.secondary)
      }
    }.padding(12).background(StudioInk.card, in: RoundedRectangle(cornerRadius: 9))
  }

  @ViewBuilder private func actionChoices(_ choose: @escaping (ActionKind) -> Void) -> some View {
    ForEach(ActionKind.groups, id: \.0) { name, actions in
      Menu(name) {
        ForEach(actions, id: \.self) { kind in
          Button { choose(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
        }
      }
    }
  }

  private func branch(_ title: String, steps: Binding<[InteractionStep]>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title).font(.headline).foregroundStyle(StudioInk.green)
        Spacer()
        Menu {
          actionChoices { kind in steps.wrappedValue.append(InteractionStep(kind)) }
        } label: { Label("Add action", systemImage: "plus") }
          .fixedSize().accessibilityLabel("Add action to " + title)
          .disabled(draft.steps.count + (draft.conditional ? draft.otherwise.count : 0) >= 64)
      }
      ForEach(steps) { step in actionCard(step, in: steps) }
    }
  }

  private func choices(_ title: String, _ selection: Binding<String>, _ items: [(String, String)]) -> some View {
    Picker(title, selection: selection) {
      ForEach(items, id: \.0) { value, label in Text(label).tag(value) }
    }
  }

  private func target(_ selected: Int, role: InteractionPick) -> some View {
    HStack(spacing: 6) {
      InteractionElementList(rows: draft.candidates(for: role), selected: selected, title: draft.label(selected)) { id in
        if let picked = draft.pick(id, for: role) { model.select(picked) }
      }.accessibilityLabel(role.label)
      Button { draft.picking = draft.picking == role ? nil : role } label: {
        Label("Pick", systemImage: "scope")
      }.tint(draft.picking == role ? StudioInk.clay : StudioInk.green)
        .help("Pick this element directly on the canvas")
    }
  }

  private func actionCard(_ binding: Binding<InteractionStep>, in branch: Binding<[InteractionStep]>) -> some View {
    let step = binding.wrappedValue
    let index = branch.wrappedValue.firstIndex(where: { $0.id == step.id }) ?? 0
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(String(index + 1)).font(.caption.bold().monospacedDigit()).foregroundStyle(StudioInk.green)
          .frame(width: 22, height: 22).background(StudioInk.green.opacity(0.12), in: Circle())
        Menu {
          actionChoices { kind in
            if kind != step.kind { binding.wrappedValue = InteractionStep(kind); draft.picking = nil }
          }
        } label: { Text(step.kind.title).font(.headline) }.menuStyle(.borderlessButton)
        Spacer(minLength: 0)
        Menu {
          Button("Move earlier") { branch.wrappedValue.swapAt(index, index - 1) }.disabled(index == 0)
          Button("Move later") { branch.wrappedValue.swapAt(index, index + 1) }.disabled(index + 1 >= branch.wrappedValue.count)
          Divider()
          Button("Remove action", role: .destructive) { branch.wrappedValue.removeAll { $0.id == step.id }; draft.picking = nil }
        } label: { Image(systemName: "ellipsis.circle") }.fixedSize().accessibilityLabel("Options for step " + String(index + 1))
      }
      if step.kind.needsTarget {
        if step.kind == .calculate || step.kind == .copyValue { Text("Write result to").font(.caption).foregroundStyle(.secondary) }
        if let label = deviceTargetLabel(step.kind) { Text(label).font(.caption).foregroundStyle(.secondary) }
        target(step.target, role: .target(step.id))
      }
      switch step.kind {
      case .calculate: calculationFields(binding)
      case .copyValue:
        Text("Read value from").font(.caption).foregroundStyle(.secondary)
        target(step.input ?? -1, role: .input(step.id))
        field("Prefix (optional)", binding.value)
        field("Suffix (optional)", binding.detail)
      case .classChange:
        choices("Class action", binding.value, [("toggle","Toggle"), ("add","Add"), ("remove","Remove")])
        field("CSS class name", binding.detail)
        if !draft.catalog.classes.isEmpty {
          Menu("Choose a class on this page") {
            ForEach(draft.catalog.classes, id: \.self) { name in Button(name) { binding.wrappedValue.detail = name } }
          }
        }
      case .enabled:
        choices("State", binding.value, [("enable","Enabled"),("disable","Disabled")])
      case .checked:
        choices("State", binding.value, [("toggle","Toggle"),("check","Checked"),("uncheck","Unchecked")])
      case .disclosure:
        choices("Details", binding.value, [("toggle","Toggle"),("open","Open"),("close","Close")])
      case .mediaControl:
        choices("Playback", binding.value, [("play","Play"),("pause","Pause")])
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
      default: deviceFields(binding)
      }
    }.padding(11).background(StudioInk.card, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(StudioInk.line, lineWidth: 1))
  }

  private func deviceTargetLabel(_ kind: ActionKind) -> String? {
    switch kind {
    case .cameraStart: return "Video element for the live camera"
    case .cameraSnapshot: return "Image to receive the captured frame"
    case .micStart: return "Meter or readout for the input level"
    case .serialRead, .usbRead: return "Display the received data in"
    default: return nil
    }
  }

  private func deviceHint(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
  }

  private func sendFields(_ step: Binding<InteractionStep>, hex: Bool) -> some View {
    let current = step.wrappedValue
    return VStack(alignment: .leading, spacing: 6) {
      Picker("Send from", selection: Binding(get: { current.input != nil }, set: { useElement in
        step.wrappedValue.input = useElement ? -1 : nil
        draft.picking = nil
      })) {
        Text("Fixed value").tag(false)
        Text("Page element").tag(true)
      }.pickerStyle(.segmented)
      if let input = current.input { target(input, role: .input(current.id)) }
      else { field(hex ? "Hex bytes (e.g. 01 0A FF)" : "Text to send", hex ? step.detail : step.value) }
    }
  }

  @ViewBuilder private func deviceFields(_ step: Binding<InteractionStep>) -> some View {
    switch step.wrappedValue.kind {
    case .serialOpen:
      field("Baud rate (8N1)", step.value)
      deviceHint("Use the baud rate in the device firmware. Put Connect first on a click or key press. Preview uses a simulated port.")
    case .serialWrite:
      sendFields(step, hex: false)
      choices("Line ending", step.detail, [("lf","LF"),("crlf","CRLF"),("none","None")])
    case .serialRead:
      deviceHint("Reads one UTF-8 line through the next newline. Disconnect cancels a waiting read.")
    case .usbOpen:
      DisclosureGroup("Device filter and interface") {
        ForEach(["vendor","product","configuration","interface","alternate"], id: \.self) { key in
          let labels = ["vendor":"Vendor ID (4 hex digits, optional)", "product":"Product ID (4 hex digits, optional)",
                        "configuration":"Configuration number", "interface":"Interface number", "alternate":"Alternate setting"]
          field(labels[key] ?? key, Binding(get: { step.wrappedValue.settings?[key] ?? "" }, set: { step.wrappedValue.settings?[key] = $0 }))
        }
      }
      deviceHint("Use the configuration and interface from the device documentation. A visitor clicks Connect to open the browser picker. Preview simulates USB.")
    case .usbWrite:
      field("OUT endpoint number (1–15)", step.value)
      sendFields(step, hex: true)
    case .usbRead:
      field("IN endpoint number (1–15)", step.value)
      field("Maximum bytes per read (1–4096)", step.detail)
    case .cameraStart:
      deviceHint("A visitor clicks Start to allow a muted live camera feed. Preview shows a test frame.")
    case .cameraSnapshot:
      deviceHint("Start the camera first. Each snapshot replaces the image on the running page.")
    case .micStart:
      deviceHint("A visitor clicks Start to allow a live RMS level (0–100%). Preview uses a simulated signal.")
    default: EmptyView()
    }
  }

  private func calculationFields(_ step: Binding<InteractionStep>) -> some View {
    let current = step.wrappedValue
    return VStack(alignment: .leading, spacing: 8) {
      Text("First value").font(.caption).foregroundStyle(.secondary)
      target(current.input ?? -1, role: .input(current.id))
      choices("Operation", step.value, [("add","Add"),("subtract","Subtract"),("multiply","Multiply"),("divide","Divide")])
      Picker("Second value", selection: Binding(get: { current.constant != nil }, set: { useNumber in
        step.wrappedValue.constant = useNumber ? "1" : nil
        draft.picking = nil
      })) {
        Text("Page element").tag(false)
        Text("Fixed number").tag(true)
      }.pickerStyle(.segmented)
      if current.constant == nil { target(current.operand ?? -1, role: .operand(current.id)) }
      else { field("Number", Binding(get: { step.wrappedValue.constant ?? "" }, set: { step.wrappedValue.constant = $0 })) }
      Picker("Decimal places", selection: Binding(get: { current.digits ?? -1 }, set: { step.wrappedValue.digits = $0 })) {
        Text("Automatic").tag(-1)
        ForEach(0...8, id: \.self) { Text(String($0)).tag($0) }
      }
      field("Result suffix (optional)", step.detail)
      field("Invalid result message", Binding(get: { step.wrappedValue.invalid ?? "" }, set: { step.wrappedValue.invalid = $0 }))
    }
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
