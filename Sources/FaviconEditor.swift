import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension IconBitmap {
  var image: CGImage? {
    let channels = pixels.flatMap { p in
      [
        UInt8(p >> 24), UInt8(truncatingIfNeeded: p >> 16), UInt8(truncatingIfNeeded: p >> 8),
        UInt8(truncatingIfNeeded: p),
      ]
    }
    guard let provider = CGDataProvider(data: Data(channels) as CFData) else { return nil }
    return CGImage(
      width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4 * size,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }
  func png() throws -> Data {
    let data = NSMutableData()
    guard let image,
      let writer = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw BenchError("The favicon image could not be encoded.") }
    CGImageDestinationAddImage(writer, image, nil)
    guard CGImageDestinationFinalize(writer) else { throw BenchError("The PNG was incomplete.") }
    return data as Data
  }
  static func load(_ data: Data, preferred: Int, preserveSize: Bool) throws -> IconBitmap {
    guard sizes.contains(preferred) else { throw BenchError("Choose a supported favicon grid size.") }
    guard !data.isEmpty, data.count <= 12 * 1024 * 1024 else {
      throw BenchError("Choose an image under 12 MiB.")
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0,
      let kind = CGImageSourceGetType(source) as String?, let type = UTType(kind),
      type.conforms(to: .image)
    else {
      throw BenchError("This image could not be read. Import a PNG, ICO, JPEG, or WebP image.")
    }
    // Raster inputs have no external dependencies. Only self-contained static SVG is eligible.
    if type.conforms(to: .svg) {
      guard let xml = String(data: data, encoding: .utf8),
        xml.range(
          of:
            #"(?i)<!DOCTYPE|<!ENTITY|<\s*(?:script|style|image|foreignObject|use|feImage|animate|set)\b|\bon\w+\s*=|\bhref\s*=|@import|url\s*\(\s*['"]?(?!#)[^)]"#,
          options: .regularExpression) == nil
      else {
        throw BenchError("Import a self-contained static SVG or a PNG rendering of this icon.")
      }
    }
    let count = min(128, CGImageSourceGetCount(source))
    var best = 0
    var score = Int.max
    var native = preferred
    for i in 0..<count {
      let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
      let w = props?[kCGImagePropertyPixelWidth] as? Int ?? preferred
      let h = props?[kCGImagePropertyPixelHeight] as? Int ?? preferred
      guard w > 0, h > 0, w <= 32768, h <= 32768 else { continue }
      let rank = abs(max(w, h) - preferred) + (w < h || w > h ? 100000 : 0)
      if rank < score {
        best = i
        score = rank
        native = preserveSize && w == h && sizes.contains(w) ? w : preferred
      }
    }
    guard score < Int.max else { throw BenchError("Image dimensions are too large.") }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: native,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(source, best, opts as CFDictionary) else {
      throw BenchError("This image format could not be rasterized. Import a PNG copy.")
    }
    var result = IconBitmap(size: native)
    var bytes = [UInt8](repeating: 0, count: native * native * 4)
    try bytes.withUnsafeMutableBytes { buf in
      guard
        let ctx = CGContext(
          data: buf.baseAddress, width: native, height: native, bitsPerComponent: 8,
          bytesPerRow: native * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue)
      else { throw BenchError("Cannot allocate icon pixels.") }
      let scale = CGFloat(native) / CGFloat(max(img.width, img.height))
      let w = max(1, round(CGFloat(img.width) * scale))
      let h = max(1, round(CGFloat(img.height) * scale))
      ctx.interpolationQuality = img.width == native && img.height == native ? .none : .high
      ctx.draw(
        img,
        in: CGRect(
          x: floor((CGFloat(native) - w) / 2), y: floor((CGFloat(native) - h) / 2), width: w,
          height: h))
    }
    for i in result.pixels.indices {
      let start = i * 4
      let a = Int(bytes[start + 3])
      if a > 0 {
        func c(_ j: Int) -> UInt32 { UInt32(min(255, (Int(bytes[start + j]) * 255 + a / 2) / a)) }
        result.pixels[i] = c(0) << 24 | c(1) << 16 | c(2) << 8 | UInt32(a)
      }
    }
    return result
  }
}

struct FaviconEdit: Identifiable {
  let id = UUID()
  let page: String, metadata: IconLinks
}
extension Session {
  func openFavicon() {
    afterWriting {
      guard self.safeToEdit, let engine = self.engine, let text = self.site?.files[self.page]?.text
      else { return }
      do {
        self.iconEditor = FaviconEdit(
          page: self.page, metadata: try engine.call("icons", [text], as: IconLinks.self))
      } catch { self.codeFallback(error.localizedDescription) }
    }
  }
  func existingIcon(_ link: IconLink?, metadata: IconLinks) throws -> Data? {
    guard let site else { return nil }
    guard let link else { return site.standalone ? nil : site.files["favicon.ico"]?.bytes }
    let href = link.href.replacingOccurrences(of: "&amp;", with: "&")
    if href.lowercased().hasPrefix("data:") {
      guard let comma = href.firstIndex(of: ","),
        href[..<comma].lowercased().hasPrefix("data:image/")
      else { throw BenchError("Unsupported favicon data URL.") }
      let value = String(href[href.index(after: comma)...])
      let data =
        href[..<comma].lowercased().contains(";base64")
        ? Data(base64Encoded: value) : value.removingPercentEncoding.map { Data($0.utf8) }
      guard let data else { throw BenchError("The embedded favicon could not be decoded.") }
      return data
    }
    var pageURL = URLComponents()
    pageURL.scheme = "webbench"
    pageURL.host = "project"
    pageURL.path = "/" + page
    guard let pageAddress = pageURL.url else { throw BenchError("Invalid page path.") }
    let base =
      metadata.base.isEmpty
      ? pageAddress : URL(string: metadata.base, relativeTo: pageAddress)?.absoluteURL
    guard let base, let url = URL(string: href, relativeTo: base)?.absoluteURL,
      let path = localPath(url.absoluteString),
      let bytes = site.files[path]?.bytes
    else {
      throw BenchError(
        "The linked icon is outside the open project. Open its site folder, import artwork, or draw a replacement."
      )
    }
    return bytes
  }
  func setFavicon(_ icon: IconBitmap, link: Int, edit: FaviconEdit) throws {
    guard safeToEdit, edit.page == page, let site, let file = site.files[page], let src = file.text,
      let engine
    else { throw BenchError("The active page changed. Open Favicon again.") }
    let png = try icon.png()
    var changes = [Change]()
    let asset = try site.faviconAsset(png, from: page, hasBase: !edit.metadata.base.isEmpty)
    if let path = asset.newPath { changes.append(Change(path: path, bytes: png)) }
    let result = try engine.call(
      "setIcon", [src, link, asset.url, icon.size, selected ?? -1], as: EditResult.self)
    changes.append(Change(path: page, bytes: try file.encoded(result.text)))
    change(changes, "Set favicon", focus: selected == nil ? nil : result.focus)
  }
}

private func pixelColor(_ n: UInt32) -> Color {
  Color(
    .sRGB, red: Double(n >> 24) / 255, green: Double((n >> 16) & 255) / 255,
    blue: Double((n >> 8) & 255) / 255, opacity: Double(n & 255) / 255)
}

struct FaviconEditor: View {
  let model: Session, edit: FaviconEdit
  @Environment(\.dismiss) private var dismiss
  @State private var icon = IconBitmap()
  @State private var baseline = IconBitmap()
  @State private var linkID = -1
  @State private var tool = "Pencil"
  @State private var ink: UInt32 = 0x225B_48FF
  @State private var past = [IconBitmap]()
  @State private var future = [IconBitmap]()
  @State private var strokeStart: IconBitmap?
  @State private var lastCell: CGPoint?
  @State private var note = ""
  @State private var initials = ""
  @State private var pendingLink: Int?
  private let drawingSide: CGFloat = 288
  private static let colors: [UInt32] = [
    0x1626_23FF, 0xFFFF_FFFF, 0x225B_48FF, 0x5AB8_7BFF, 0x276A_A9FF, 0xE6B5_45FF, 0xBD4D_49FF,
    0x8B63_A4FF,
  ]
  private var changed: Bool { icon != baseline }
  private func record(_ old: IconBitmap) {
    if old != icon {
      past.append(old)
      if past.count > 50 { past.removeFirst() }
      future = []
    }
  }
  private func load(_ id: Int) {
    linkID = id
    note = ""
    do {
      let link = edit.metadata.links.first { $0.id == id }
      if let bytes = try model.existingIcon(link, metadata: edit.metadata) {
        let hinted = Int(link?.sizes.split(separator: "x").first.map(String.init) ?? "")
        icon = try IconBitmap.load(
          bytes, preferred: hinted.flatMap { IconBitmap.sizes.contains($0) ? $0 : nil } ?? 32,
          preserveSize: true)
      } else {
        icon = IconBitmap()
      }
    } catch {
      icon = IconBitmap()
      note = error.localizedDescription
    }
    baseline = icon
    past = []
    future = []
    strokeStart = nil
    lastCell = nil
  }
  private func importArt() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .ico, .jpeg, .webP, .gif, .tiff, .svg]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      if size > 12 * 1024 * 1024 {
        let alert = NSAlert()
        alert.messageText = "Resize this image for the favicon?"
        alert.informativeText =
          "Create a copy for the current icon grid. The original file will be preserved."
        alert.addButton(withTitle: "Resize for favicon")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = try PhotoInput(url: url)
        let image = try PhotoRender.thumbnail(input.imageSource(), edge: icon.size)
        let data = NSMutableData()
        guard
          let writer = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)
        else { throw BenchError("Cannot prepare the icon image.") }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else {
          throw BenchError("Cannot resize the icon image.")
        }
        let old = icon
        icon = try IconBitmap.load(data as Data, preferred: icon.size, preserveSize: false)
        record(old)
        note = ""
        return
      }
      let old = icon
      icon = try IconBitmap.load(Data(contentsOf: url), preferred: icon.size, preserveSize: false)
      record(old)
      note = ""
    } catch { note = error.localizedDescription }
  }
  private func saveImage(_ multi: Bool) {
    let p = NSSavePanel()
    p.allowedContentTypes = [multi ? .ico : .png]
    p.nameFieldStringValue = multi ? "favicon.ico" : "favicon.png"
    guard p.runModal() == .OK, let url = p.url else { return }
    do {
      if model.site?.files.keys.contains(where: {
        model.site?.root.appendingPathComponent($0).standardizedFileURL == url.standardizedFileURL
      }) == true {
        throw BenchError("Export outside the working files, or use Apply to page.")
      }
      let data =
        try multi
        ? IconBitmap.ico(images: [16, 32, 48].map { ($0, try icon.scaled(to: $0).png()) })
        : icon.png()
      try data.write(to: url, options: .atomic)
      note = "Exported " + url.lastPathComponent
    } catch { note = error.localizedDescription }
  }
  private func mark(_ location: CGPoint) {
    let cell = CGPoint(
      x: floor(location.x * CGFloat(icon.size) / drawingSide),
      y: floor(location.y * CGFloat(icon.size) / drawingSide))
    guard cell.x >= 0, cell.y >= 0, cell.x < CGFloat(icon.size), cell.y < CGFloat(icon.size) else {
      lastCell = nil
      return
    }
    if strokeStart == nil { strokeStart = icon }
    if lastCell == cell { return }
    let x = Int(cell.x)
    let y = Int(cell.y)
    switch tool {
    case "Sample": ink = icon.pixels[y * icon.size + x]
    case "Fill": if lastCell == nil { icon.fill(x: x, y: y, color: ink) }
    default:
      let prev = lastCell ?? cell
      icon.stroke(from: (Int(prev.x), Int(prev.y)), to: (x, y), color: tool == "Erase" ? 0 : ink)
    }
    lastCell = cell
  }
  private var drawing: some View {
    SwiftUI.Canvas { context, size in
      let square = size.width / 16
      for y in 0..<16 {
        for x in 0..<16 {
          context.fill(
            Path(
              CGRect(x: CGFloat(x) * square, y: CGFloat(y) * square, width: square, height: square)),
            with: .color((x + y) % 2 == 0 ? Color(white: 0.97) : Color(white: 0.86)))
        }
      }
      if let cg = icon.image {
        context.draw(
          Image(decorative: cg, scale: 1).interpolation(.none),
          in: CGRect(origin: .zero, size: size))
      }
      let step = size.width / CGFloat(icon.size)
      var lines = Path()
      for index in 0...icon.size {
        let p = CGFloat(index) * step
        lines.move(to: CGPoint(x: p, y: 0))
        lines.addLine(to: CGPoint(x: p, y: size.height))
        lines.move(to: CGPoint(x: 0, y: p))
        lines.addLine(to: CGPoint(x: size.width, y: p))
      }
      context.stroke(lines, with: .color(.black.opacity(0.12)), lineWidth: 0.5)
    }.frame(width: drawingSide, height: drawingSide).border(Color.secondary.opacity(0.5))
      .contentShape(Rectangle()).gesture(
        DragGesture(minimumDistance: 0).onChanged { mark($0.location) }.onEnded { v in
          mark(v.location)
          if let old = strokeStart { record(old) }
          strokeStart = nil
          lastCell = nil
        }
      ).accessibilityLabel("Favicon pixel canvas")
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Favicon").font(.title2.bold())
          Text(edit.page).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Import artwork…", action: importArt)
        Menu("Export") {
          Button("PNG…") { saveImage(false) }
          Button("ICO · 16, 32, 48 px…") { saveImage(true) }
        }
      }
      if edit.metadata.links.count > 1 {
        Picker(
          "Icon link",
          selection: Binding(
            get: { linkID }, set: { id in if changed { pendingLink = id } else { load(id) } })
        ) {
          ForEach(edit.metadata.links) { link in Text(link.label).tag(link.id) }
        }
      }
      HStack(alignment: .top, spacing: 18) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Tool", selection: $tool) {
            ForEach(["Pencil", "Erase", "Fill", "Sample"], id: \.self) { Text($0) }
          }.pickerStyle(.segmented).labelsHidden()
          drawing
        }
        VStack(alignment: .leading, spacing: 12) {
          Text("Preview").font(.headline)
          HStack(alignment: .bottom, spacing: 10) {
            ForEach([16, 32, 48], id: \.self) { n in
              VStack(spacing: 4) {
                if let image = icon.image {
                  Image(decorative: image, scale: 1).interpolation(.none).resizable().frame(
                    width: CGFloat(n), height: CGFloat(n))
                }
                Text("\(n) px").font(.caption2)
              }
            }
          }.padding(8).background(Color(nsColor: .textBackgroundColor)).cornerRadius(5)
          Picker(
            "Canvas",
            selection: Binding(
              get: { icon.size },
              set: { n in
                let old = icon
                icon = icon.scaled(to: n)
                record(old)
              })
          ) {
            ForEach(IconBitmap.sizes, id: \.self) { n in Text("\(n) × \(n)").tag(n) }
          }
          Divider()
          HStack {
            TextField("Initials", text: $initials).accessibilityLabel("One to three initials")
            Button("Create") {
              do {
                let old = icon
                icon = try IconBitmap.initials(initials, size: icon.size, color: ink)
                record(old)
                note = ""
              } catch { note = error.localizedDescription }
            }.disabled(initials.isEmpty)
          }
          ColorPicker(
            "Ink",
            selection: Binding(
              get: { pixelColor(ink) },
              set: { c in
                let hex = PaintControl.hexValue(c)
                ink = UInt32(hex.count == 6 ? hex + "FF" : hex, radix: 16) ?? ink
              }))
          LazyVGrid(columns: Array(repeating: GridItem(.fixed(25)), count: 4), spacing: 6) {
            ForEach(Self.colors, id: \.self) { n in
              Button {
                ink = n
              } label: {
                Circle().fill(pixelColor(n)).overlay(
                  Circle().stroke(Color.secondary, lineWidth: ink == n ? 2 : 0.5)
                ).frame(width: 22, height: 22)
              }.buttonStyle(.plain).accessibilityLabel(String(format: "Color #%08X", n))
            }
          }
          HStack {
            Button("Undo") {
              if let old = past.popLast() {
                future.append(icon)
                icon = old
              }
            }.disabled(past.isEmpty)
            Button("Redo") {
              if let next = future.popLast() {
                past.append(icon)
                icon = next
              }
            }.disabled(future.isEmpty)
          }
          Button("Clear canvas") {
            let old = icon
            icon = IconBitmap(size: old.size)
            record(old)
          }
        }.frame(width: 164)
      }
      if !note.isEmpty { Text(note).font(.caption).fixedSize(horizontal: false, vertical: true) }
      Divider()
      HStack {
        Text("Applies to this page.").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply to page") {
          do {
            try model.setFavicon(icon, link: linkID, edit: edit)
            dismiss()
          } catch { note = error.localizedDescription }
        }.keyboardShortcut(.defaultAction).disabled(!changed)
      }
    }.padding(20).frame(width: 520)
      .onAppear { load(edit.metadata.links.last?.id ?? -1) }
      .confirmationDialog(
        "Discard these favicon edits and switch links?",
        isPresented: Binding(get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } })
      ) {
        Button("Discard and switch", role: .destructive) {
          if let id = pendingLink { load(id) }
          pendingLink = nil
        }
        Button("Keep editing", role: .cancel) { pendingLink = nil }
      }
  }
}
