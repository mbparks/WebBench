import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

final class PhotoInput {
  let name: String, byteCount: Int
  private let url: URL?, data: Data?, temporary: Bool
  init(url: URL, name: String? = nil, temporary: Bool = false) throws {
    let meta = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard meta.isRegularFile == true else { throw BenchError("Choose a photo file.") }
    self.name = name ?? url.lastPathComponent
    byteCount = meta.fileSize ?? 0
    self.url = url
    self.data = nil
    self.temporary = temporary
  }
  init(data: Data, name: String) {
    self.data = data
    self.name = name
    byteCount = data.count
    url = nil
    temporary = false
  }
  deinit { if temporary, let url { try? FileManager.default.removeItem(at: url) } }
  func imageSource() throws -> CGImageSource {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    let s: CGImageSource?
    if let url {
      s = CGImageSourceCreateWithURL(url as CFURL, options)
    } else if let data {
      s = CGImageSourceCreateWithData(data as CFData, options)
    } else {
      s = nil
    }
    guard let s, let type = CGImageSourceGetType(s) as String?, let ut = UTType(type),
      ut.conforms(to: .image), !ut.conforms(to: .svg), !ut.conforms(to: .pdf),
      CGImageSourceGetCount(s) > 0
    else {
      throw BenchError("Photo tools need a raster image such as JPEG, PNG, HEIC, TIFF, or WebP.")
    }
    return s
  }
}
struct PhotoInfo {
  let w: Int, h: Int, frames: Int, alpha: Bool
  init(_ source: CGImageSource) throws {
    guard let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = p[kCGImagePropertyPixelWidth] as? Int,
      let height = p[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
    else { throw BenchError("The photo has no readable pixel dimensions.") }
    let swapped = (5...8).contains(p[kCGImagePropertyOrientation] as? Int ?? 1)
    w = swapped ? height : width
    h = swapped ? width : height
    frames = CGImageSourceGetCount(source)
    alpha = p[kCGImagePropertyHasAlpha] as? Bool ?? false
  }
}
struct PhotoTarget {
  let token: String, id: Int, before: Any, point: Any, replace: Bool
}
struct PhotoJob: Identifiable {
  let id = UUID()
  let input: PhotoInput, target: PhotoTarget, budget: Int, resizeOffer: Bool
}
struct PhotoResult {
  let image: CGImage, bytes: Data, ext: String
}
enum PhotoCodec: String, CaseIterable {
  case auto = "Automatic"
  case jpeg = "JPEG"
  case png = "PNG"
}
enum PhotoRender {
  static func thumbnail(_ source: CGImageSource, edge: Int) throws -> CGImage {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, edge), kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw BenchError("This photo could not be decoded. Choose another file.")
    }
    return image
  }
  static func render(_ job: PhotoJob, recipe: PhotoRecipe, codec: PhotoCodec, quality: Double)
    throws -> PhotoResult
  {
    let source = try job.input.imageSource()
    let info = try PhotoInfo(source)
    let full = recipe.crop.box(width: info.w, height: info.h)
    let needed = Double(recipe.edge) * Double(max(info.w, info.h)) / Double(max(full.w, full.h))
    let thumb = try thumbnail(source, edge: min(6144, Int(min(6144, ceil(needed)))))
    let b = recipe.crop.box(width: thumb.width, height: thumb.height)
    guard let cropped = thumb.cropping(to: CGRect(x: b.x, y: b.y, width: b.w, height: b.h)) else {
      throw BenchError("Choose a crop inside the photo.")
    }
    let alpha =
      CGImageSourceGetType(source) as String? != UTType.jpeg.identifier
      && (info.alpha
        || [.first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly].contains(
          thumb.alphaInfo))
    let jpeg = codec == .jpeg || (codec == .auto && !alpha)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    var limit = recipe.edge
    while true {
      try Task.checkCancellation()
      let dims = recipe.dimensions(width: info.w, height: info.h, limit: limit)
      let w = recipe.turns % 2 == 0 ? dims.width : dims.height
      let h = recipe.turns % 2 == 0 ? dims.height : dims.width
      var input = [UInt8](repeating: 0, count: w * h * 4)
      try input.withUnsafeMutableBytes { raw in
        guard
          let ctx = CGContext(
            data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw BenchError("Cannot allocate a photo preview.") }
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        if jpeg {
          ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
          ctx.fill(bounds)
        }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: bounds)
      }
      let pixels = try recipe.finish(input, width: w, height: h)
      guard let provider = CGDataProvider(data: Data(pixels) as CFData),
        let image = CGImage(
          width: dims.width, height: dims.height, bitsPerComponent: 8, bitsPerPixel: 32,
          bytesPerRow: 4 * dims.width, space: space,
          bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
              | CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil,
          shouldInterpolate: true, intent: .defaultIntent)
      else { throw BenchError("Cannot create the edited photo.") }
      let data = NSMutableData()
      guard
        let writer = CGImageDestinationCreateWithData(
          data, (jpeg ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil)
      else { throw BenchError("Cannot start the image encoder.") }
      let options: [CFString: Any] =
        jpeg ? [kCGImageDestinationLossyCompressionQuality: quality] : [:]
      CGImageDestinationAddImage(writer, image, options as CFDictionary)
      guard CGImageDestinationFinalize(writer) else {
        throw BenchError("The photo could not be encoded.")
      }
      if data.length <= job.budget {
        let bytes = data as Data
        guard let encodedSource = CGImageSourceCreateWithData(bytes as CFData, nil),
          let preview = CGImageSourceCreateImageAtIndex(encodedSource, 0, nil)
        else {
          throw BenchError("The edited photo could not be reopened for preview.")
        }
        return PhotoResult(image: preview, bytes: bytes, ext: jpeg ? "jpg" : "png")
      }
      let current = max(dims.width, dims.height)
      guard current > 1 else {
        throw BenchError(
          "The HTML file has no room for another embedded image. Use a site folder for linked photos."
        )
      }
      limit = PhotoRecipe.smallerEdge(current, bytes: data.length, budget: job.budget)
    }
  }
}

private func photoBytes(_ count: Int) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
}
struct PhotoEditor: View {
  @ObservedObject var model: Session
  let job: PhotoJob
  @Environment(\.dismiss) private var dismiss
  @State private var recipe = PhotoRecipe()
  @State private var codec = PhotoCodec.auto
  @State private var quality = 0.84
  @State private var info: PhotoInfo?
  @State private var original: CGImage?
  @State private var result: PhotoResult?
  @State private var rendered: Settings?
  @State private var error = ""
  @State private var view = "Edited"
  @State private var drag: PhotoCrop?
  private struct Settings: Equatable { let recipe: PhotoRecipe, codec: PhotoCodec, quality: Double }
  private var settings: Settings { Settings(recipe: recipe, codec: codec, quality: quality) }
  private func badge(_ value: PhotoCrop, _ size: CGSize) -> CGRect {
    CGRect(
      x: value.x * size.width, y: value.y * size.height, width: value.width * size.width,
      height: value.height * size.height)
  }
  private func startingEdge(_ info: PhotoInfo) -> Int {
    min(job.resizeOffer ? 1600 : 4096, max(info.w, info.h))
  }
  private var displayed: CGImage? { view == "Edited" ? result?.image ?? original : original }
  private var stage: some View {
    GeometryReader { bounds in
      ZStack {
        Color(nsColor: .underPageBackgroundColor)
        if let image = displayed {
          let scale = min(
            (bounds.size.width - 20) / Double(image.width),
            (bounds.size.height - 20) / Double(image.height))
          let size = CGSize(
            width: max(1, Double(image.width) * scale), height: max(1, Double(image.height) * scale)
          )
          Image(decorative: image, scale: 1).resizable().frame(
            width: size.width, height: size.height
          )
          .overlay {
            if view == "Crop" {
              let box = badge(drag ?? recipe.crop, size)
              ZStack(alignment: .topLeading) {
                Path { p in
                  p.addRect(CGRect(origin: .zero, size: size))
                  p.addRect(box)
                }.fill(.black.opacity(0.46), style: FillStyle(eoFill: true))
                Rectangle().stroke(.white, lineWidth: 2).frame(width: box.width, height: box.height)
                  .offset(x: box.minX, y: box.minY)
              }.frame(width: size.width, height: size.height, alignment: .topLeading).contentShape(
                Rectangle()
              )
              .gesture(
                DragGesture(minimumDistance: 2).onChanged { v in
                  let a = min(1, max(0, v.startLocation.x / size.width))
                  let b = min(1, max(0, v.startLocation.y / size.height))
                  let x = min(1, max(0, v.location.x / size.width))
                  let y = min(1, max(0, v.location.y / size.height))
                  drag = PhotoCrop(
                    x: min(a, x), y: min(b, y), width: abs(x - a), height: abs(y - b))
                }.onEnded { _ in
                  if let drag, drag.width * size.width >= 3, drag.height * size.height >= 3 {
                    recipe.crop = drag
                  }
                  drag = nil
                })
            }
          }
        } else if error.isEmpty {
          ProgressView()
        }
      }
    }
  }
  private func adjustment(_ label: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>)
    -> some View
  {
    VStack(alignment: .leading, spacing: 1) {
      HStack {
        Text(label)
        Spacer()
        Text(String(format: "%.2f", binding.wrappedValue)).monospacedDigit().foregroundStyle(
          .secondary)
      }
      Slider(value: binding, in: range).accessibilityLabel(label)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(job.resizeOffer ? "Resize photo for this page" : "Edit photo").font(.title2.bold())
          Text(
            job.input.name + " · " + photoBytes(job.input.byteCount)
              + (info.map { " · \($0.w) × \($0.h) px" } ?? "")
          ).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        Button("Reset") {
          recipe = PhotoRecipe()
          if let info { recipe.edge = startingEdge(info) }
          codec = .auto
          quality = 0.84
          view = "Edited"
        }
      }
      if job.resizeOffer {
        Text(
          "Create a copy that fits this page’s " + photoBytes(job.budget)
            + " image budget. The original stays on disk."
        ).font(.callout)
      }
      HStack(alignment: .top, spacing: 15) {
        VStack {
          Picker("Preview", selection: $view) {
            ForEach(["Edited", "Crop", "Original"], id: \.self) { Text($0) }
          }.pickerStyle(.segmented).labelsHidden()
          stage
          if view == "Crop" { Text("Drag a rectangle on the original to crop.").font(.caption) }
          HStack {
            if let r = result {
              Text(
                "\(r.image.width) × \(r.image.height) px · " + photoBytes(r.bytes.count) + " · "
                  + r.ext.uppercased()
              ).monospacedDigit()
            }
            Spacer()
            if info != nil && rendered != settings && error.isEmpty {
              ProgressView().controlSize(.small)
            }
          }.font(.caption)
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            Text("Size & crop").font(.headline)
            HStack {
              Text("Longest edge")
              TextField("Pixels", value: $recipe.edge, format: .number.grouping(.never)).frame(
                width: 62)
              Text("px")
            }
            HStack(spacing: 4) {
              ForEach([640, 1280, 1920], id: \.self) { edge in
                Button(String(edge)) { recipe.edge = edge }
              }
            }.controlSize(.small).accessibilityLabel("Longest edge presets")
            Picker(
              "Crop",
              selection: Binding<String>(
                get: { "Crop preset" },
                set: { value in
                  guard let info else { return }
                  view = "Crop"
                  let ratio = [
                    "Square": 1.0, "4:3": 4.0 / 3, "16:9": 16.0 / 9, "Portrait": 3.0 / 4,
                  ][value]
                  recipe.crop =
                    ratio.map {
                      PhotoCrop.centered(ratio: $0, imageWidth: info.w, imageHeight: info.h)
                    } ?? PhotoCrop()
                })
            ) {
              ForEach(
                ["Crop preset", "Full image", "Square", "4:3", "16:9", "Portrait"], id: \.self
              ) { Text($0) }
            }.labelsHidden()
            HStack {
              Button {
                recipe.turns = (recipe.turns + 3) % 4
                view = "Edited"
              } label: {
                Image(systemName: "rotate.left")
              }.help("Rotate left").accessibilityLabel("Rotate left")
              Button {
                recipe.turns = (recipe.turns + 1) % 4
                view = "Edited"
              } label: {
                Image(systemName: "rotate.right")
              }.help("Rotate right").accessibilityLabel("Rotate right")
              Toggle("Mirror", isOn: $recipe.mirror).toggleStyle(.button)
            }
            Divider()
            Picker("Filter", selection: $recipe.filter) {
              ForEach(PhotoFilter.allCases, id: \.self) { Text($0.rawValue) }
            }
            adjustment("Brightness", $recipe.brightness, -0.4...0.4)
            adjustment("Contrast", $recipe.contrast, 0.5...1.6)
            adjustment("Saturation", $recipe.saturation, 0...2)
            Divider()
            Picker("Border", selection: $recipe.border) {
              ForEach(PhotoBorder.allCases, id: \.self) { Text($0.rawValue) }
            }
            if recipe.border != .none {
              ColorPicker(
                "Border color",
                selection: Binding(
                  get: {
                    Color(
                      .sRGB, red: Double(recipe.borderRGB >> 16) / 255,
                      green: Double((recipe.borderRGB >> 8) & 255) / 255,
                      blue: Double(recipe.borderRGB & 255) / 255)
                  },
                  set: { c in
                    if let rgb = NSColor(c).usingColorSpace(.sRGB) {
                      let v = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
                        UInt32((min(1, max(0, $0)) * 255).rounded())
                      }
                      recipe.borderRGB = v[0] << 16 | v[1] << 8 | v[2]
                    }
                  }), supportsOpacity: false)
              adjustment("Border width (%)", $recipe.borderPercent, 0.5...10)
            }
            Picker("Format", selection: $codec) {
              ForEach(PhotoCodec.allCases, id: \.self) { Text($0.rawValue) }
            }
            if codec != .png { adjustment("JPEG quality", $quality, 0.4...0.98) }
            if (info?.frames ?? 0) > 1 {
              Text("Applying creates a still image from the first frame.").font(.caption)
            }
          }.padding(.trailing, 4)
        }.frame(width: 215)
      }
      if !error.isEmpty { Text(error).foregroundStyle(.red).font(.callout) }
      Divider()
      HStack {
        Text("Original file preserved").foregroundStyle(.secondary).font(.caption)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button(
          job.target.replace
            ? "Apply to photo" : job.resizeOffer ? "Resize and insert" : "Insert photo"
        ) {
          guard let result, rendered == settings else { return }
          if model.applyPhoto(result, to: job) { dismiss() } else { error = model.status }
        }.keyboardShortcut(.defaultAction).disabled(result == nil || rendered != settings)
      }
    }.padding(18).frame(
      minWidth: 690, idealWidth: 760, maxWidth: 820, minHeight: 470, idealHeight: 530,
      maxHeight: 600
    )
    .task {
      do {
        let pair = try await Task.detached(priority: .userInitiated) { [job] in
          let src = try job.input.imageSource()
          return try (PhotoInfo(src), PhotoRender.thumbnail(src, edge: 900))
        }.value
        try Task.checkCancellation()
        if recipe.edge == 1600 { recipe.edge = startingEdge(pair.0) }
        info = pair.0
        original = pair.1
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    .task(id: settings) {
      let request = settings
      rendered = nil
      guard (1...4096).contains(request.recipe.edge) else {
        error = "Enter a longest edge from 1 to 4096 pixels."
        return
      }
      do {
        try await Task.sleep(nanoseconds: 140_000_000)
        error = ""
        let worker = Task.detached(priority: .userInitiated) { [job] in
          try PhotoRender.render(
            job, recipe: request.recipe, codec: request.codec, quality: request.quality)
        }
        let finished = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        result = finished
        rendered = request
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
}

extension Session {
  var embedPhotoCopy: Bool { site?.standalone == true || nodes.contains { $0.tag == "base" } }
  func photoBudget(_ target: PhotoTarget) -> Int {
    guard embedPhotoCopy, let f = site?.files[page] else { return 12 * 1024 * 1024 }
    let old =
      target.replace && inspection?.id == target.id ? inspection?.attributes["src"] ?? "" : ""
    let units = (f.format == .utf16BE || f.format == .utf16LE) ? 2 : 1
    let free = max(0, 6 * 1024 * 1024 - f.bytes.count + old.utf8.count * units - 1024 * units)
    return min(2 * 1024 * 1024, free / units / 4 * 3)
  }
  func startPhoto(_ input: PhotoInput, target: PhotoTarget, offer: Bool) {
    guard safeToEdit, preview?.token == target.token else { return }
    let budget = photoBudget(target)
    guard budget >= 128 else {
      status =
        "There is no room in this HTML file for an embedded image. Use a site folder to link a photo."
      return
    }
    photoEditor = PhotoJob(input: input, target: target, budget: budget, resizeOffer: offer)
  }
  func importPhotoFile(_ url: URL, target: PhotoTarget) {
    do {
      let input = try PhotoInput(url: url)
      let ext = url.pathExtension.lowercased()
      if Site.rasterPhotos.contains(ext)
        && (input.byteCount > photoBudget(target) || !Site.images.contains(ext))
      {
        startPhoto(input, target: target, offer: input.byteCount > photoBudget(target))
        return
      }
      guard Site.images.contains(ext) else {
        throw BenchError("Choose a JPEG, PNG, HEIC, TIFF, WebP, GIF, AVIF, BMP or SVG image.")
      }
      guard input.byteCount <= 12 * 1024 * 1024 else {
        throw BenchError(
          "This SVG exceeds the import budget. Use a smaller SVG or choose a raster rendering.")
      }
      addAsset(
        input.name, bytes: try Data(contentsOf: url, options: .mappedIfSafe), existing: nil,
        id: target.id, before: target.before, point: target.point, replace: target.replace)
    } catch { alert(error.localizedDescription) }
  }
  func editSelectedPhoto() {
    guard safeToEdit, let site, let i = inspection, let token = preview?.token,
      nodes.indices.contains(i.id), nodes[i.id].tag == "img"
    else { return }
    guard i.responsivePhoto != true else {
      codeFallback(
        "This image uses picture or srcset. Choose the specific responsive source in Code.",
        id: i.id)
      return
    }
    let src = i.attributes["src"] ?? ""
    do {
      let input: PhotoInput
      if src.lowercased().hasPrefix("data:image/") {
        guard let comma = src.firstIndex(of: ","), src[..<comma].lowercased().contains(";base64"),
          let data = Data(
            base64Encoded: String(src[src.index(after: comma)...]),
            options: .ignoreUnknownCharacters)
        else { throw BenchError("Use a base64-embedded raster photo or a local image file.") }
        input = PhotoInput(data: data, name: "Embedded photo")
      } else {
        guard let address = i.photoURL, let url = URL(string: address), url.scheme == "webbench",
          url.host == "project"
        else { throw BenchError("Import a local copy of this photo to edit it offline.") }
        let path = String(url.path.dropFirst())
        if let file = site.files[path] {
          input = PhotoInput(data: file.bytes, name: url.lastPathComponent)
        } else if site.linkedAssets.contains(path) {
          input = try PhotoInput(url: Site.safe(path, under: site.root))
        } else {
          throw BenchError("Open the enclosing site folder so WebBench can read the linked photo.")
        }
      }
      startPhoto(
        input,
        target: PhotoTarget(
          token: token, id: i.id, before: NSNull(), point: NSNull(), replace: true), offer: false)
    } catch { alert(error.localizedDescription) }
  }
  func applyPhoto(_ result: PhotoResult, to job: PhotoJob) -> Bool {
    guard safeToEdit, preview?.token == job.target.token, photoEditor?.id == job.id else {
      status = "The page changed. Reopen the photo editor for the current page."
      return false
    }
    let stem = (job.input.name as NSString).deletingPathExtension
    return addAsset(
      stem + "-edited." + result.ext, bytes: result.bytes, existing: nil, id: job.target.id,
      before: job.target.before, point: job.target.point, replace: job.target.replace)
  }
}
