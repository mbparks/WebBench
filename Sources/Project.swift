import Foundation

struct BenchError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

struct SourceFile {
  enum Format { case utf8, utf8BOM, utf16LE, utf16BE, binary }
  let path: String
  var original: Data?
  var bytes: Data
  let format: Format
  var dirty: Bool { original != bytes }
  var text: String? {
    switch format {
    case .utf8: return String(data: bytes, encoding: .utf8)
    case .utf8BOM: return String(data: bytes.dropFirst(3), encoding: .utf8)
    case .utf16LE: return String(data: bytes.dropFirst(2), encoding: .utf16LittleEndian)
    case .utf16BE: return String(data: bytes.dropFirst(2), encoding: .utf16BigEndian)
    case .binary: return nil
    }
  }
  init(path: String, data: Data, new: Bool = false) {
    self.path = path
    bytes = data
    original = new ? nil : data
    let ext = (path as NSString).pathExtension.lowercased()
    if !Site.sourceExtensions.contains(ext) {
      format = .binary
    } else if data.starts(with: [0xfe, 0xff]) {
      format = Self.roundTrips(data.dropFirst(2), as: .utf16BigEndian) ? .utf16BE : .binary
    } else if data.starts(with: [0xff, 0xfe]) {
      format = Self.roundTrips(data.dropFirst(2), as: .utf16LittleEndian) ? .utf16LE : .binary
    } else if data.starts(with: [0xef, 0xbb, 0xbf]) {
      format = Self.roundTrips(data.dropFirst(3), as: .utf8) ? .utf8BOM : .binary
    } else if String(data: data, encoding: .utf8) != nil {
      format = .utf8
    } else {
      format = .binary
    }
  }
  private static func roundTrips(_ data: Data, as encoding: String.Encoding) -> Bool {
    guard let s = String(data: data, encoding: encoding) else { return false }
    return s.data(using: encoding) == data
  }
  func encoded(_ text: String) throws -> Data {
    switch format {
    case .utf8: return Data(text.utf8)
    case .utf8BOM: return Data([0xef, 0xbb, 0xbf]) + Data(text.utf8)
    case .utf16LE, .utf16BE:
      let little = format == .utf16LE
      guard let d = text.data(using: little ? .utf16LittleEndian : .utf16BigEndian) else {
        throw BenchError("Encoding failed.")
      }
      return Data(little ? [0xff, 0xfe] : [0xfe, 0xff]) + d
    case .binary: throw BenchError("This encoding or asset is read-only.")
    }
  }
}

struct Conflict: LocalizedError {
  let path: String
  let recovery: URL
  let disk: Data?
  var errorDescription: String? {
    "“\(path)” changed on disk. Your buffer and the available disk and baseline versions are in “\(recovery.lastPathComponent)”."
  }
}
struct Site {
  static let sourceExtensions = Set(["html", "htm", "css", "js", "mjs", "svg", "json", "txt"])
  static let images = Set(["png", "jpg", "jpeg", "webp", "gif", "svg", "avif"])
  static let rasterPhotos = images.subtracting(["svg"]).union([
    "heic", "heif", "tif", "tiff", "bmp",
  ])
  static let audio = Set(["mp3", "m4a", "wav", "ogg", "flac"])
  static let video = Set(["mp4", "m4v", "mov", "webm"])
  static let media = audio.union(video)
  static let downloads: Set<String> = ["pdf", "csv", "zip"]
  static let supported = downloads.union(media).union(sourceExtensions).union(images).union(rasterPhotos).union([
    "ico", "woff", "woff2", "ttf", "otf", "wasm",
  ])
  let root: URL
  let standalone: Bool
  var files: [String: SourceFile]
  var linkedAssets: Set<String> = []
  var workspacePaths: [String] { Set(files.keys).union(linkedAssets).sorted() }
  var pages: [String] {
    files.keys.filter { ["htm", "html"].contains(($0 as NSString).pathExtension.lowercased()) }
      .sorted()
  }
  var dirtyPaths: [String] { files.keys.filter { files[$0]?.dirty == true }.sorted() }

  static func safe(_ path: String, under root: URL) throws -> URL {
    guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.standardizedFileURL.path
    else {
      throw BenchError("The project directory changed location. Reopen its real folder.")
    }
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !parts.isEmpty,
      !parts.contains(where: {
        $0.isEmpty || $0.hasPrefix(".") || $0.contains("\\") || $0.contains("\0")
      })
    else {
      throw BenchError("Unsafe project path.")
    }
    var url = root
    for part in parts {
      url.appendPathComponent(String(part))
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
      if attributes?[.type] as? FileAttributeType == .typeSymbolicLink {
        throw BenchError("Symbolic links are outside this workspace.")
      }
    }
    guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else {
      throw BenchError("Path escapes project.")
    }
    return url
  }
  /// Materialize source bytes into a unique writable project. A failed copy never becomes an open site.
  static func copySample(from source: URL, into directory: URL) throws -> Site {
    let original = try Site.open(source)
    guard !original.standalone, original.files["index.html"]?.text != nil else {
      throw BenchError("The bundled workbench sample is incomplete.")
    }
    let fm = FileManager.default
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let parent = directory.resolvingSymlinksInPath()
    let copy = parent.appendingPathComponent("Workbench-" + UUID().uuidString)
    try fm.createDirectory(at: copy, withIntermediateDirectories: false)
    do {
      for (path, file) in original.files {
        let destination = try safe(path, under: copy)
        try fm.createDirectory(
          at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.bytes.write(to: destination, options: .withoutOverwriting)
      }
      try original.copyLinkedAssets(to: copy)
      return try Site.open(copy)
    } catch {
      try? fm.removeItem(at: copy)
      throw error
    }
  }

  static func createFolder(at url: URL, blankPage: String) throws {
    let fm = FileManager.default
    guard !fm.fileExists(atPath: url.path) else { throw BenchError("Choose a new folder name.") }
    guard let start = blankPage.range(of: "<style>"), let end = blankPage.range(of: "</style>"),
      start.upperBound <= end.lowerBound
    else { throw BenchError("Blank template is missing its stylesheet.") }
    let css =
      String(blankPage[start.upperBound..<end.lowerBound]).trimmingCharacters(
        in: .whitespacesAndNewlines) + "\n"
    let html = blankPage.replacingCharacters(
      in: start.lowerBound..<end.upperBound,
      with:
        "<link rel=\"stylesheet\" href=\"css/site.css\">\n  <script defer src=\"js/site.js\"></script>"
    )
    let staging = url.deletingLastPathComponent().appendingPathComponent(
      ".webbench-" + UUID().uuidString)
    try fm.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: staging) }
    for name in ["css", "js", "assets"] {
      try fm.createDirectory(
        at: staging.appendingPathComponent(name), withIntermediateDirectories: false)
    }
    try Data(html.utf8).write(to: staging.appendingPathComponent("index.html"))
    try Data(css.utf8).write(to: staging.appendingPathComponent("css/site.css"))
    try Data("// Page interactions belong here.\n".utf8).write(
      to: staging.appendingPathComponent("js/site.js"))
    try fm.moveItem(at: staging, to: url)
  }
  static func open(_ url: URL) throws -> Site {
    let fm = FileManager.default
    let input = url.standardizedFileURL
    let info = try input.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard info.isSymbolicLink != true else {
      throw BenchError("Open the real file or folder, rather than a symbolic link.")
    }
    let single = info.isDirectory != true
    let root = (single ? input.deletingLastPathComponent() : input).resolvingSymlinksInPath()
    guard root.path != "/" else { throw BenchError("Open a site folder.") }
    var files: [String: SourceFile] = [:]
    var total = 0
    var linkedAssets = Set<String>()
    func read(_ file: URL, _ path: String) throws {
      let ext = file.pathExtension.lowercased()
      guard supported.contains(ext) else { return }
      let values = try file.resourceValues(forKeys: [
        .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey,
      ])
      guard values.isRegularFile == true, values.isSymbolicLink != true else { return }
      let size = values.fileSize ?? 0
      guard files.count + linkedAssets.count < 4096 else {
        throw BenchError("The site exceeds the 4,096 file workspace limit.")
      }
      if !single && (downloads.contains(ext) || media.contains(ext) || (rasterPhotos.contains(ext) && size > 12 * 1024 * 1024))
      {
        _ = try safe(path, under: root)
        linkedAssets.insert(path)
        return
      }
      guard size <= (sourceExtensions.contains(ext) ? 6 : 20) * 1024 * 1024 else {
        throw BenchError("“\(path)” exceeds the per-file limit. Open a smaller site folder.")
      }
      total += size
      guard total <= 160 * 1024 * 1024, files.count < 4096 else {
        throw BenchError("This folder exceeds the 160 MiB / 4,096 file workspace limit.")
      }
      files[path] = SourceFile(path: path, data: try Data(contentsOf: safe(path, under: root)))
    }
    if single {
      try read(input, input.lastPathComponent)
    } else {
      var failed: Error?
      guard
        let en = fm.enumerator(
          at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
          options: [.skipsHiddenFiles, .skipsPackageDescendants],
          errorHandler: { _, err in
            failed = err
            return false
          })
      else { throw BenchError("Folder cannot be read.") }
      for case let file as URL in en {
        let v = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if v.isSymbolicLink == true
          || (v.isDirectory == true
            && ["node_modules", "vendor", "DerivedData"].contains(file.lastPathComponent))
        {
          en.skipDescendants()
          continue
        }
        if v.isDirectory != true {
          try read(file, String(file.path.dropFirst(root.path.count + 1)))
        }
      }
      if let failed { throw failed }
    }
    let site = Site(root: root, standalone: single, files: files, linkedAssets: linkedAssets)
    guard site.pages.contains(where: { files[$0]?.text != nil }) else {
      throw BenchError("Choose a folder or HTML page containing UTF-8 or BOM-marked UTF-16 HTML.")
    }
    return site
  }
  private func diskBytes(_ path: String) throws -> Data? {
    let u = try Self.safe(path, under: root)
    do { return try Data(contentsOf: u) } catch let e as NSError
      where e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoSuchFileError
    { return nil }
  }
  private func check(_ path: String, _ file: SourceFile, recovery: URL) throws {
    let disk = try diskBytes(path)
    guard disk != file.original else { return }
    let dir = recovery.appendingPathComponent("Conflict-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let leaf = (path as NSString).lastPathComponent
    try file.bytes.write(to: dir.appendingPathComponent("WebBench-" + leaf), options: .atomic)
    try disk?.write(to: dir.appendingPathComponent("External-" + leaf), options: .atomic)
    try file.original?.write(to: dir.appendingPathComponent("Baseline-" + leaf), options: .atomic)
    throw Conflict(path: path, recovery: dir, disk: disk)
  }
  // After each successful write advance that file's baseline, including in partial failures.
  mutating func save(recovery: URL) throws {
    let paths = dirtyPaths
    guard !paths.isEmpty else { return }
    for path in files.keys.sorted() {
      guard let f = files[path], f.dirty || f.format != .binary else { continue }
      try check(path, f, recovery: recovery)
    }
    for path in paths {
      guard let f = files[path] else { continue }
      let dest = try Self.safe(path, under: root)
      // Coordination needs a real parent for a newly imported asset.
      try FileManager.default.createDirectory(
        at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
      func write() throws {
        try check(path, f, recovery: recovery)
        if f.original == nil {
          try f.bytes.write(to: dest, options: .withoutOverwriting)
        } else {
          try f.bytes.write(to: dest, options: .atomic)
        }
      }
      #if os(macOS)
        var coordinationError: NSError?
        var error: Error?
        NSFileCoordinator().coordinate(writingItemAt: dest, options: [], error: &coordinationError)
        { coordinatedURL in
          guard coordinatedURL.standardizedFileURL.path == dest.standardizedFileURL.path else {
            error = BenchError("The file moved while saving. Reopen its current location.")
            return
          }
          do { try write() } catch let e { error = e }
        }
        if let e = coordinationError { throw e }
        if let error { throw error }
      #else
        try write()
      #endif
      files[path]?.original = f.bytes
    }
  }

  func assetPath(_ name: String, data: Data, allowed: Set<String> = Site.images) throws -> String {
    let leaf = (name as NSString).lastPathComponent
    guard leaf == name, !leaf.hasPrefix("."),
      allowed.contains((leaf as NSString).pathExtension.lowercased()),
      data.count <= 12 * 1024 * 1024
    else { throw BenchError("Choose a supported asset up to 12 MiB.") }
    let tidy = leaf.map { ($0.isLetter || $0.isNumber || "._-".contains($0)) ? $0 : "-" }
    let clean = String(tidy)
    let base = (clean as NSString).deletingPathExtension
    let ext = (clean as NSString).pathExtension
    for i in 0..<10000 {
      let candidate = "assets/" + (i == 0 ? base : base + "-\(i)") + "." + ext
      if files[candidate]?.bytes == data { return candidate }
      let url = try Self.safe(candidate, under: root)
      if files[candidate] == nil && !FileManager.default.fileExists(atPath: url.path) {
        return candidate
      }
    }
    throw BenchError("Choose a different asset name.")
  }
  func faviconAsset(_ png: Data, from page: String, hasBase: Bool) throws -> (
    url: String, newPath: String?
  ) {
    if standalone || hasBase { return ("data:image/png;base64," + png.base64EncodedString(), nil) }
    let path = try assetPath("favicon.png", data: png)
    return (Self.relative(path, from: page), files[path] == nil ? path : nil)
  }
  static func relative(_ asset: String, from page: String) -> String {
    var a = asset.split(separator: "/")
    var p = page.split(separator: "/").dropLast()
    while let x = a.first, let y = p.first, x == y {
      a.removeFirst()
      p = p.dropFirst()
    }
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return String(repeating: "../", count: p.count)
      + a.map { String($0).addingPercentEncoding(withAllowedCharacters: safe) ?? String($0) }
      .joined(separator: "/")
  }
}

extension Site {
  private func copyPublicMedia(to stage: URL) throws {
    let fm = FileManager.default
    let extensions: Set<String> = [
      "pdf", "mp3", "m4a", "wav", "ogg", "flac", "mp4", "m4v", "mov", "webm", "vtt",
      "srt", "xml", "webmanifest", "rss", "atom", "csv", "gltf", "glb", "bin", "eot",
      "otc", "ttc", "bmp", "tif", "tiff", "apng", "heic", "jxl", "webp", "ico",
    ]
    let excluded: Set<String> = ["node_modules", "vendor", "DerivedData", "build"]
    var enumerationError: Error?
    guard
      let walker = fm.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, err in
          enumerationError = err
          return false
        })
    else { throw BenchError("The site's media folders cannot be read.") }
    for case let url as URL in walker {
      let info = try url.resourceValues(forKeys: [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
      ])
      if info.isSymbolicLink == true
        || (info.isDirectory == true && excluded.contains(url.lastPathComponent))
      {
        walker.skipDescendants()
        continue
      }
      guard info.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) else {
        continue
      }
      let name = String(url.path.dropFirst(root.path.count + 1))
      guard files[name] == nil && !linkedAssets.contains(name) else { continue }
      let dest = try Self.safe(name, under: stage)
      try fm.createDirectory(
        at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
      try fm.copyItem(at: Self.safe(name, under: root), to: dest)
    }
    if let enumerationError { throw enumerationError }
  }

  private func copyLinkedAssets(to stage: URL) throws {
    for name in linkedAssets.sorted() {
      let target = try Self.safe(name, under: stage)
      try FileManager.default.createDirectory(
        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: Self.safe(name, under: root), to: target)
    }
  }

  /// Publish the current buffers to a new directory. Rename the staging directory only after every write succeeds.
  func exportWebsite(to destination: URL, entry: String) throws {
    guard pages.contains(entry), files[entry]?.text != nil else {
      throw BenchError("Choose an HTML page to export.")
    }
    let fm = FileManager.default
    let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
    let output = parent.appendingPathComponent(destination.lastPathComponent)
    if !standalone && (parent.path == root.path || parent.path.hasPrefix(root.path + "/")) {
      throw BenchError("Export beside the working site or choose another folder.")
    }
    guard !fm.fileExists(atPath: output.path) else {
      throw BenchError("Choose a new folder name for this snapshot.")
    }
    let stage = parent.appendingPathComponent(
      "WebBench-export-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: stage, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: stage) }
    for (name, file) in files {
      let target = try Self.safe(name, under: stage)
      try fm.createDirectory(
        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try file.bytes.write(to: target, options: .withoutOverwriting)
    }
    try copyLinkedAssets(to: stage)
    if !standalone { try copyPublicMedia(to: stage) }
    if !fm.fileExists(atPath: stage.appendingPathComponent("index.html").path) {
      let rootIndex = stage.appendingPathComponent("index.html")
      if !entry.contains("/") {
        try files[entry]!.bytes.write(to: rootIndex, options: .withoutOverwriting)
      } else {
        let url = Site.relative(entry, from: "index.html")
        let landing = """
          <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Open site</title><meta http-equiv="refresh" content="0;url=\(url)"></head><body><a href="\(url)">Open site</a></body></html>
          """
        try Data(landing.utf8).write(to: rootIndex, options: .withoutOverwriting)
      }
    }
    try fm.moveItem(at: stage, to: output)
  }
}

extension Site {
  static func mediaRange(_ header: String, length: Int) -> Range<Int>? {
    guard length > 0, header.hasPrefix("bytes=") else { return nil }
    let pieces = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
    guard pieces.count == 2, pieces.allSatisfy({ $0.allSatisfy({ $0.isASCII && $0.isNumber }) })
    else { return nil }
    if pieces[0].isEmpty {
      guard let suffix = Int(pieces[1]), suffix > 0 else { return nil }
      return (length - min(suffix, length))..<length
    }
    guard let start = Int(pieces[0]), start < length else { return nil }
    if pieces[1].isEmpty { return start..<length }
    guard let end = Int(pieces[1]), end >= start else { return nil }
    return start..<(min(end, length - 1) + 1)
  }
}
