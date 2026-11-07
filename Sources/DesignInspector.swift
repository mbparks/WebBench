import AppKit
import SwiftUI

struct DesignInspector: View {
  @ObservedObject var model: Session
  let selection: Inspection
  @State private var fields = [String: String]()
  @State private var ink = Color.black
  @State private var size = ""
  @State private var radius = ""

  private var metrics: [String: Double] {
    ["left": selection.x, "top": selection.y, "width": selection.width, "height": selection.height]
  }
  private func restore() {
    fields = metrics.mapValues { String(Int($0.rounded())) }
    ink = Self.browserColor(selection.ink) ?? .black
    size = selection.fontSize.replacingOccurrences(of: "px", with: "")
    radius = ""
  }
  static func browserColor(_ string: String) -> Color? {
    let values = string.split(whereSeparator: { !"0123456789.-".contains($0) }).compactMap {
      Double($0)
    }
    guard values.count >= 3, string.hasPrefix("rgb") else { return nil }
    return Color(
      .sRGB, red: values[0] / 255, green: values[1] / 255, blue: values[2] / 255,
      opacity: values.count > 3 ? values[3] : 1)
  }
  private func applyColor(_ color: Color, to property: String) {
    guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
    let channels = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map {
      Int(($0 * 255).rounded())
    }
    let value = channels.map { String(format: "%02x", $0) }.joined()
    set(property, "#" + value)
  }
  private func set(_ property: String, _ value: String) {
    model.mutate(
      ["kind": "inline", "prop": property, "value": value], id: selection.id,
      name: "Set " + property)
  }
  private func applyNumber(_ source: String, property: String, min: Int) {
    guard let val = Int(source), (min...10000).contains(val) else {
      model.status = "Enter a whole number from \(min) to 10000."
      return
    }
    set(property, "\(val)px")
  }
  private func applyFrame() {
    var changes = [String: Int]()
    for (prop, old) in metrics {
      let position = prop == "left" || prop == "top"
      if position ? !selection.canMove : !selection.canResize { continue }
      guard let value = Int(fields[prop] ?? ""),
        ((position ? -1_000_000 : 1)...1_000_000).contains(value)
      else {
        model.status = "Enter a whole pixel value. Width and height must be positive."
        return
      }
      if value != Int(old.rounded()) { changes[prop] = value }
    }
    if !changes.isEmpty { model.requestFrame(changes) }
  }
  private func metric(_ label: String, _ key: String, enabled: Bool) -> some View {
    HStack(spacing: 4) {
      Text(label).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 14)
      TextField(label, text: Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0 }))
        .onSubmit { applyFrame() }
        .accessibilityLabel(
          [
            "left": "Horizontal position", "top": "Vertical position", "width": "CSS width",
            "height": "CSS height",
          ][key] ?? label)
    }.disabled(!enabled)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if model.inspectorTab == "Arrange" {
        Text("Position and size").font(.headline)
        Grid(alignment: .leading, horizontalSpacing: 9, verticalSpacing: 6) {
          GridRow {
            metric("X", "left", enabled: selection.canMove)
            metric("Y", "top", enabled: selection.canMove)
          }
          GridRow {
            metric("W", "width", enabled: selection.canResize)
            metric("H", "height", enabled: selection.canResize)
          }
        }
        Button("Apply frame", action: applyFrame).disabled(
          !selection.canMove && !selection.canResize)
        Text(
          selection.canMove
            ? "Drag to move. Shift constrains the drag. Option bypasses snapping."
            : "This layer follows its container’s layout. Drag it on the page to change its position in the flow."
        )
        .font(.caption).foregroundStyle(.secondary)
        if let position = selection.position, ["absolute", "fixed", "sticky"].contains(position) {
          Button("Use normal flow") {
            model.mutate(
              ["kind": "inline", "prop": "position", "value": "static", "important": true],
              id: selection.id, name: "Use normal flow")
          }
        }
        if selection.canLift {
          Button("Place freely in container") { model.designer?.lift(selection.id) }
          Text("Removes this layer from flow. Siblings can shift.").font(.caption).foregroundStyle(
            .secondary)
        }
        if selection.canResize {
          Text("Drag an edge or corner to resize. Hold Shift on the corner to keep proportions.")
            .font(.caption).foregroundStyle(.secondary)
        }
        if selection.canStack {
          Divider()
          Text("Stacking").font(.headline)
          HStack {
            Button("To back") { model.requestFrame(["z-index": selection.backLevel]) }
            Button("To front") { model.requestFrame(["z-index": selection.frontLevel]) }
          }
          Text("Stacking level \(selection.stack)").font(.caption).foregroundStyle(.secondary)
        }
        Divider()
        Text("Document order").font(.headline)
        HStack {
          ForEach([LayerStep.up, .down], id: \.self) { step in
            let slot = model.slot(for: selection.id, step: step)
            Button(step == .up ? "Earlier" : "Later") {
              if let slot { model.moveLayer(selection.id, to: slot) }
            }.disabled(slot == nil)
          }
        }
      } else {
        Text("Appearance").font(.headline)
        if model.nodes.indices.contains(selection.id), model.nodes[selection.id].tag == "img" {
          Button("Edit photo…") { model.editSelectedPhoto() }
        }
        if model.nodes.indices.contains(selection.id),
          ["audio", "video"].contains(model.nodes[selection.id].tag)
        {
          Button("Choose media file…") { model.chooseMedia(for: selection.id) }
        }
        BackgroundControl(model: model, pageWide: false)
        HStack {
          ColorPicker("Text", selection: $ink)
          Spacer()
          Button("Set ink") { applyColor(ink, to: "color") }
        }
        HStack {
          TextField("Corner radius (px)", text: $radius)
          Button("Round") { applyNumber(radius, property: "border-radius", min: 0) }
        }
        Divider()
        Text("Typography").font(.headline)
        HStack {
          TextField("Font size (px)", text: $size)
          Button("Set size") { applyNumber(size, property: "font-size", min: 1) }
        }
        HStack {
          ForEach(["left", "center", "right"], id: \.self) { align in
            Button {
              set("text-align", align)
            } label: {
              Image(systemName: "text.align" + align)
            }
            .help("Align text " + align).accessibilityLabel("Align text " + align)
          }
        }
        Text("Applies to this element at all widths. Use Inspect for shared rules and breakpoints.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }.onAppear(perform: restore)
      .onChange(of: model.preview?.token) { _, _ in restore() }
      .onChange(of: selection.id) { _, _ in restore() }
      .onChange(of: metrics) { _, _ in restore() }
  }
}

struct GroupInspector: View {
  @ObservedObject var model: Session
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(model.groupIDs.count) layers").font(.headline)
      if let id = model.groupIDs.first, model.nodes.indices.contains(id) {
        Text("Align to " + model.nodes[id].name).font(.subheadline)
      }
      Grid(alignment: .leading, horizontalSpacing: 5, verticalSpacing: 6) {
        GridRow {
          action("Left", "left")
          action("Center", "centerX").help("Align horizontal centers")
          action("Right", "right")
        }
        GridRow {
          action("Top", "top")
          action("Middle", "centerY").help("Align vertical centers")
          action("Bottom", "bottom")
        }
      }
      Divider()
      Text("Equal gaps").font(.subheadline.bold())
      HStack {
        action("Horizontal", "spaceX")
        action("Vertical", "spaceY")
      }.disabled(model.groupIDs.count < 3)
      Text("The two outer layers stay in place.").font(.caption).foregroundStyle(.secondary)
      Divider()
      Text("Drag the selection or use the arrow keys. Shift–arrow moves 10 px.").font(.caption)
      if let id = model.groupIDs.first {
        Button("Select only the first layer") { model.select(id) }
      }
    }.disabled(!model.safeToEdit)
  }
  func action(_ label: String, _ command: String) -> some View {
    Button(label) { model.arrangeGroup(command) }.controlSize(.small)
  }
}
