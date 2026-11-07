import AppKit
import SwiftUI

struct StudioControls: View {
  @ObservedObject var model: Session
  @State private var customDevice = false
  @State private var widthText = ""
  @State private var heightText = ""
  private let presets = [
    ("Phone", "iphone", 390, 844), ("Tablet", "ipad", 820, 1180),
    ("Desktop", "desktopcomputer", 1280, 800),
  ]
  var body: some View {
    ViewThatFits(in: .horizontal) {
      controls(compact: false)
      controls(compact: true)
    }.padding(.horizontal, 8).frame(maxWidth: .infinity).frame(height: 35)
      .background(StudioInk.paper)
      .popover(isPresented: $customDevice) { dimensions }
  }
  private func controls(compact: Bool) -> some View {
    HStack(spacing: compact ? 5 : 9) {
      if compact {
        Menu {
          ForEach(presets, id: \.0) { kind in
            Button {
              model.useDevice(kind.0, Double(kind.2), Double(kind.3))
            } label: {
              Label(kind.0, systemImage: kind.1)
            }
          }
          Button("Rotate preview") {
            model.useDevice(model.device, model.deviceHeight, model.width)
          }
        } label: {
          Image(systemName: presets.first { $0.0 == model.device }?.1 ?? "display")
        }.fixedSize().accessibilityLabel("Preview device: " + model.device)
      } else {
        HStack(spacing: 2) {
          ForEach(presets, id: \.0) { kind in
            Button {
              model.useDevice(kind.0, Double(kind.2), Double(kind.3))
            } label: {
              Label(kind.0, systemImage: kind.1)
                .font(.caption.weight(.semibold)).padding(.horizontal, 6).frame(height: 23)
                .background(
                  model.device == kind.0 ? StudioInk.green.opacity(0.15) : .clear,
                  in: RoundedRectangle(cornerRadius: 5))
            }.buttonStyle(.plain).accessibilityValue(model.device == kind.0 ? "Selected" : "")
          }
        }.fixedSize()
        Button {
          model.useDevice(model.device, model.deviceHeight, model.width)
        } label: {
          Image(systemName: "rotate.right")
        }.buttonStyle(.borderless).help("Rotate preview").accessibilityLabel("Rotate preview")
      }
      Button("\(Int(model.width)) × \(Int(model.deviceHeight))") {
        widthText = String(Int(model.width))
        heightText = String(Int(model.deviceHeight))
        customDevice = true
      }.fixedSize().font(.caption.monospacedDigit()).help("Set or scrub the preview width")
      Spacer(minLength: 0)
      if model.hasFreePage && !model.running && !model.writing {
        Menu {
          Button("At all widths") { model.devicePlacement = false }
          Button("Only this breakpoint") { model.devicePlacement = true }
        } label: {
          if compact {
            Image(
              systemName: model.devicePlacement
                ? "rectangle.inset.filled" : "rectangle.expand.vertical")
          } else {
            Text(model.devicePlacement ? model.band.capitalized + " only" : "All widths")
          }
        }.fixedSize().accessibilityLabel("Move and resize scope").accessibilityValue(
          model.devicePlacement ? model.band : "All widths"
        )
        .help("Apply moves and resizes to all widths or this breakpoint")
      }
      Picker("Zoom", selection: $model.zoom) {
        ForEach(["Fit", "50%", "75%", "100%", "150%"], id: \.self) { Text($0).tag($0) }
      }.labelsHidden().fixedSize().help("Canvas magnification")
    }.controlSize(.small)
  }
  private var dimensions: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Preview dimensions").font(.headline)
      HStack {
        Text("Width")
        TextField("px", text: $widthText)
      }
      HStack {
        Text("Height")
        TextField("px", text: $heightText)
      }
      Slider(
        value: Binding(
          get: { model.width },
          set: { n in
            model.useDevice("Custom", n, model.deviceHeight)
            widthText = String(Int(n))
          }), in: 240...4096, step: 1
      ).accessibilityLabel("Adjust viewport width")
      Button("Apply") {
        guard let w = Int(widthText), let h = Int(heightText), (240...4096).contains(w),
          (240...4096).contains(h)
        else {
          model.status = "Enter dimensions between 240 and 4096 CSS pixels."
          return
        }
        model.useDevice("Custom", Double(w), Double(h))
        customDevice = false
      }.keyboardShortcut(.defaultAction)
    }.padding(14).frame(width: 245)
  }
}

struct FontControl: View {
  let current: String
  let apply: (String) -> Void
  @State private var open = false
  @State private var filter = ""
  private static let favorites = [
    "System Sans", "Georgia", "Helvetica Neue", "Avenir Next", "Baskerville", "Menlo",
  ]
  private static let available = NSFontManager.shared.availableFontFamilies.filter {
    $0.range(of: "^[A-Za-z][A-Za-z0-9 -]{0,75}$", options: .regularExpression) != nil
  }.sorted()
  private var title: String {
    let text =
      current.components(separatedBy: ",").first?.trimmingCharacters(
        in: CharacterSet(charactersIn: " \"'")) ?? ""
    return text.isEmpty ? "Typeface" : text == "system-ui" ? "System Sans" : text
  }
  var body: some View {
    Button {
      filter = ""
      open = true
    } label: {
      Label(title, systemImage: "textformat").lineLimit(1)
    }
    .frame(maxWidth: 175, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    .accessibilityLabel("Typeface, " + title).popover(isPresented: $open) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Typeface").font(.headline)
        TextField("Find a font", text: $filter)
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(
              (Self.favorites + Self.available.filter { !Self.favorites.contains($0) }).filter {
                filter.isEmpty || $0.localizedCaseInsensitiveContains(filter)
              }, id: \.self
            ) { family in
              Button {
                let fallback =
                  ["Baskerville", "Georgia", "Times New Roman"].contains(family)
                  ? "serif"
                  : ["Menlo", "Monaco", "Courier New"].contains(family) ? "monospace" : "sans-serif"
                apply(family == "System Sans" ? "system-ui, sans-serif" : family + ", " + fallback)
                open = false
              } label: {
                HStack {
                  Text(family).font(family == "System Sans" ? .body : .custom(family, size: 15))
                  Spacer()
                  if title == family { Image(systemName: "checkmark") }
                }.padding(4).contentShape(Rectangle())
              }.buttonStyle(.plain)
            }
          }
        }.frame(height: 235)
      }.padding(12).frame(width: 245)
    }
  }
}

struct FontSizeControl: View {
  let current: String
  let apply: (String) -> Void
  @State private var input = ""
  var body: some View {
    HStack(spacing: 2) {
      TextField("Size", text: $input).frame(width: 39).onSubmit {
        if let size = Int(input), (1...999).contains(size) { apply("\(size)px") }
      }.accessibilityLabel("Font size in pixels")
      Menu("px") {
        ForEach([12, 14, 16, 18, 20, 24, 32, 40, 48, 64, 80, 96, 120], id: \.self) { v in
          Button("\(v) px") {
            input = String(v)
            apply("\(v)px")
          }
        }
      }.fixedSize()
    }.onAppear { update() }.onChange(of: current) { _, _ in update() }
  }
  func update() {
    if let n = Double(current.replacingOccurrences(of: "px", with: "")) {
      input = String(Int(n.rounded()))
    } else {
      input = ""
    }
  }
}

struct PaintControl: View {
  let title: String, symbol: String, current: String
  var background = false
  var hasImage = false
  private let pick: (String, Bool) -> Void
  init(title: String, symbol: String, current: String, apply: @escaping (String) -> Void) {
    self.title = title
    self.symbol = symbol
    self.current = current
    self.pick = { value, _ in apply(value) }
  }
  init(
    backgroundTitle: String, current: String, hasImage: Bool, pick: @escaping (String, Bool) -> Void
  ) {
    title = backgroundTitle
    symbol = "paintpalette"
    self.current = current
    background = true
    self.hasImage = hasImage
    self.pick = pick
  }
  @State private var keepImage = false
  @State private var open = false
  @State private var hex = ""
  @State private var error = ""
  @State private var custom = Color.black
  private static let colors = [
    ("Ink", "192C27"), ("Forest", "285947"), ("Sky", "2864AB"), ("Teal", "138080"),
    ("Plum", "77426A"), ("Rust", "B35531"), ("Ochre", "CD923B"), ("Rose", "CF5C77"),
    ("Slate", "687785"), ("Paper", "F6F3E9"), ("White", "FFFFFF"), ("Black", "141616"),
  ]
  private static func color(_ rgb: String) -> Color {
    let n = UInt32(rgb, radix: 16) ?? 0
    return Color(
      .sRGB, red: Double(n >> 16) / 255, green: Double((n >> 8) & 255) / 255,
      blue: Double(n & 255) / 255, opacity: 1)
  }
  static func hexValue(_ color: Color) -> String {
    guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "000000" }
    let parts = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map {
      String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded()))
    }
    return parts.prefix(parts[3] == "FF" ? 3 : 4).joined()
  }
  var body: some View {
    Button {
      custom = DesignInspector.browserColor(current) ?? .black
      keepImage = false
      hex = Self.hexValue(custom)
      error = ""
      open = true
    } label: {
      HStack(spacing: 4) {
        Circle().fill(DesignInspector.browserColor(current) ?? .clear).strokeBorderOverlay().frame(
          width: 12, height: 12)
        Text(title)
      }
    }
    .accessibilityLabel(title).popover(isPresented: $open) {
      VStack(alignment: .leading, spacing: 9) {
        Text(title).font(.headline)
        if background {
          Button("Transparent") {
            pick("transparent", keepImage)
            open = false
          }
          if hasImage { Toggle("Keep background image or gradient", isOn: $keepImage) }
        }
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(27)), count: 6), spacing: 7) {
          ForEach(Self.colors, id: \.0) { c in
            Button {
              pick("#" + c.1, keepImage)
              open = false
            } label: {
              Circle().fill(Self.color(c.1)).strokeBorderOverlay().frame(width: 24, height: 24)
            }
            .buttonStyle(.plain).accessibilityLabel(c.0).help(c.0)
          }
        }
        Divider()
        ColorPicker(
          "Custom color",
          selection: Binding(
            get: { custom },
            set: {
              custom = $0
              hex = Self.hexValue($0)
            }))
        HStack {
          Text("#")
          TextField("RGB or RGBA hex", text: $hex).onSubmit(commit)
          Button("Apply", action: commit)
        }
        if !error.isEmpty { Text(error).font(.caption) }
      }.padding(12).frame(width: 230)
    }
  }
  func commit() {
    let v = hex.trimmingCharacters(
      in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
    guard v.range(of: "^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$", options: .regularExpression) != nil
    else {
      error = "Enter 6 or 8 hex digits."
      return
    }
    pick("#" + v, keepImage)
    open = false
  }
}
extension View {
  fileprivate func strokeBorderOverlay() -> some View {
    overlay(Circle().stroke(.secondary.opacity(0.55), lineWidth: 0.7))
  }
}

struct SizePanel: View {
  @ObservedObject var model: Session
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Object size").font(.headline)
      if let i = model.inspection, i.canResize {
        ForEach(["width", "height"], id: \.self) { axis in
          SizeAxis(
            model: model, id: i.id, axis: axis, measured: axis == "width" ? i.width : i.height)
        }
        if i.canMove { Button("Center in viewport") { model.designer?.center(i.id) } }
        Text("Drag to preview. Release to keep the size.").font(.caption).foregroundStyle(
          .secondary)
      } else {
        Text(
          model.inspection == nil
            ? "Select a page object."
            : "This element has no editable rectangular frame. Select its containing object in Layers."
        ).font(.callout)
      }
    }
  }
}
private struct SizeAxis: View {
  @ObservedObject var model: Session
  let id: Int, axis: String, measured: Double
  @State private var value = 1.0
  @State private var input = ""
  @State private var tracking = false
  private func reset() {
    if !tracking {
      value = max(1, measured.rounded())
      input = String(Int(value))
    }
  }
  private func preview(_ phase: String) {
    model.designer?.scrub(id, axis: axis, value: Int(value.rounded()), phase: phase)
  }
  var body: some View {
    VStack(spacing: 4) {
      HStack {
        Text(axis.capitalized)
        Spacer()
        TextField("px", text: $input).frame(width: 60).onSubmit {
          if let n = Int(input), (1...100000).contains(n) {
            model.requestFrame([axis: n])
          } else {
            reset()
          }
        }
        Text("px").foregroundStyle(.secondary)
      }
      Slider(
        value: Binding(
          get: { value },
          set: {
            value = $0
            input = String(Int($0))
            preview(tracking ? "preview" : "commit")
          }),
        in: 1...max(1200, measured.rounded() * 1.5), step: 1,
        onEditingChanged: { active in
          tracking = active
          if !active { preview("commit") }
        }
      ).accessibilityLabel(axis.capitalized)
    }.onAppear { reset() }.onChange(of: measured) { _, _ in reset() }.onChange(of: id) { _, _ in
      reset()
    }
    .onDisappear { if tracking { preview("cancel") } }
  }
}

struct BackgroundControl: View {
  @ObservedObject var model: Session
  let pageWide: Bool
  var body: some View {
    let current =
      pageWide
      ? model.paperColor : (model.writing ? model.writingFormat.fill : model.inspection?.fill ?? "")
    let hasImage =
      pageWide
      ? model.paperHasImage
      : (model.writing ? model.writingFormat.hasImage : model.inspection?.hasImage == true)
    PaintControl(
      backgroundTitle: pageWide ? "Page background" : "Element background", current: current,
      hasImage: hasImage
    ) { color, keepImage in
      model.paintBackground(pageWide: pageWide, color: color, keepImage: keepImage)
    }
    .disabled(
      !model.safeToEdit
        || (!pageWide
          && (model.selected == nil || !model.groupIDs.isEmpty
            || model.nodes.first(where: { $0.id == model.selected }).map {
              ["html", "head", "body", "script", "style", "title", "link", "meta"].contains($0.tag)
            } == true))
    )
  }
}
struct PageControls: View {
  @ObservedObject var model: Session
  @State private var open = false
  @State private var title = ""
  @State private var height = ""
  private var bodyID: Int? { model.nodes.first { $0.tag == "body" }?.id }
  var body: some View {
    Button {
      title = ""
      height = ""
      open = true
    } label: {
      Label("Page", systemImage: "doc")
    }
    .controlSize(.small).popover(isPresented: $open) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Page settings").font(.headline)
        BackgroundControl(model: model, pageWide: true)
        Button("Edit favicon…") {
          open = false
          model.openFavicon()
        }
        Divider()
        TextField("Window title", text: $title)
        Button("Set title") {
          if let id = bodyID {
            model.mutate(["kind": "pageTitle", "value": title], id: id, name: "Page title")
          }
        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Divider()
        HStack {
          TextField("Page height in pixels", text: $height)
          Button("Set height") {
            guard let id = bodyID, let h = Int(height), (120...100000).contains(h) else {
              model.status = "Enter a page height from 120 to 100000 px."
              return
            }
            model.mutate(
              ["kind": "inline", "prop": "min-height", "value": "max(100vh, \(h)px)"], id: id,
              name: "Page height")
          }
        }
      }.disabled(!model.safeToEdit || bodyID == nil).padding(14).frame(width: 255)
    }
  }
}
