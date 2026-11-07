import Foundation
import XCTest

@testable import BenchStorage

final class StorageTests: XCTestCase {
  var temp: URL!
  var root: URL!
  var recovery: URL!
  var fixtures: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Fixtures")
  }
  override func setUpWithError() throws {
    temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    root = temp.appendingPathComponent("Site")
    recovery = temp.appendingPathComponent("Recovery")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixtures.appendingPathComponent("Site"), to: root)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: temp) }
  func data(_ path: String) throws -> Data {
    try Data(contentsOf: root.appendingPathComponent(path))
  }
  func testNoOpSiteAndSingleFilePreserveBytesAndModificationTime() throws {
    let single = temp.appendingPathComponent("instrument.html")
    try FileManager.default.copyItem(
      at: fixtures.appendingPathComponent("Field-Instrument.html"), to: single)
    for u in [root!, single] {
      var site = try Site.open(u)
      let original = site.files
      let times = try original.keys.map { p in
        try Site.safe(p, under: site.root).resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate
      }
      try site.save(recovery: recovery)
      let reopened = try Site.open(u)
      XCTAssertEqual(Set(original.keys), Set(reopened.files.keys))
      for (i, p) in original.keys.enumerated() {
        XCTAssertEqual(original[p]!.bytes, reopened.files[p]!.bytes)
        XCTAssertEqual(
          times[i],
          try Site.safe(p, under: site.root).resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)
      }
    }
  }
  func testSingleTargetChangeAndReopen() throws {
    var site = try Site.open(root)
    let original = site.files
    let f = try XCTUnwrap(site.files["index.html"])
    site.files["index.html"]!.bytes = try f.encoded(
      f.text!.replacingOccurrences(of: "left: 24px", with: "left: 41px"))
    try site.save(recovery: recovery)
    let reopened = try Site.open(root)
    for p in original.keys where p != "index.html" {
      XCTAssertEqual(original[p]!.bytes, reopened.files[p]!.bytes)
    }
    XCTAssertTrue(reopened.files["index.html"]!.text!.contains("left: 41px"))
    XCTAssertTrue(site.dirtyPaths.isEmpty)
  }
  func testUTF8BOMCRLFAndUnicodeRemainExact() throws {
    let u = root.appendingPathComponent("index.html")
    let old = Data([0xef, 0xbb, 0xbf]) + Data("<p>e\u{301} Ω</p>\r\n<!-- 🧰 -->\r\n".utf8)
    try old.write(to: u)
    var site = try Site.open(u)
    try site.save(recovery: recovery)
    XCTAssertEqual(try Data(contentsOf: u), old)
    let f = site.files["index.html"]!
    site.files["index.html"]!.bytes = try f.encoded(
      f.text!.replacingOccurrences(of: "Ω", with: "V"))
    try site.save(recovery: recovery)
    XCTAssertEqual(
      try Data(contentsOf: u),
      Data([0xef, 0xbb, 0xbf]) + Data("<p>e\u{301} V</p>\r\n<!-- 🧰 -->\r\n".utf8))
  }
  func testUTF16RetainsByteOrderAndBOM() throws {
    for little in [true, false] {
      let text = "<p>電圧</p>\r\n"
      let d =
        Data(little ? [0xff, 0xfe] : [0xfe, 0xff]) + text.data(
          using: little ? .utf16LittleEndian : .utf16BigEndian)!
      let f = SourceFile(path: "index.html", data: d)
      XCTAssertEqual(f.text, text)
      XCTAssertEqual(try f.encoded(text), d)
    }
  }
  func testConflictRecoversThreeVersionsAndBlocksOtherWrites() throws {
    var site = try Site.open(root)
    let path = "css/bench.css"
    let baseline = try data(path)
    let external = baseline + Data("\n/* external */".utf8)
    let local = baseline + Data("\n/* WebBench */".utf8)
    let html = try data("index.html")
    site.files[path]!.bytes = local
    site.files["index.html"]!.bytes.append(Data("<!-- pending -->".utf8))
    try external.write(to: root.appendingPathComponent(path))
    do {
      try site.save(recovery: recovery)
      XCTFail("Should conflict")
    } catch let c as Conflict {
      XCTAssertEqual(c.path, path)
      for (name, d) in [("WebBench", local), ("External", external), ("Baseline", baseline)] {
        XCTAssertEqual(
          try Data(contentsOf: c.recovery.appendingPathComponent(name + "-bench.css")), d)
      }
    }
    XCTAssertEqual(try data(path), external)
    XCTAssertEqual(try data("index.html"), html)
    XCTAssertEqual(site.dirtyPaths.count, 2)
  }
  func testDeletedStylesheetRecoversDraft() throws {
    let path = "css/bench.css"
    var s = try Site.open(root)
    s.files[path]!.bytes.append(10)
    try FileManager.default.removeItem(at: root.appendingPathComponent(path))
    XCTAssertThrowsError(try s.save(recovery: recovery)) { XCTAssertTrue($0 is Conflict) }
  }
  func testIncompleteBufferCanBeSavedExactly() throws {
    var s = try Site.open(root)
    let bytes = Data("<main>\r\n <but".utf8)
    s.files["index.html"]!.bytes = bytes
    try s.save(recovery: recovery)
    XCTAssertEqual(try Site.open(root).files["index.html"]?.bytes, bytes)
  }
  func testUnsafePathsAndSymlinks() throws {
    for p in ["../x", "/x", "a//x", ".git/config", "a/../x"] {
      XCTAssertThrowsError(try Site.safe(p, under: root))
    }
    let link = root.appendingPathComponent("linked.css")
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: root.appendingPathComponent("css/bench.css"))
    XCTAssertThrowsError(try Site.safe("linked.css", under: root))
    XCTAssertNil(try Site.open(root).files["linked.css"])
  }
  func testAssetNamingCollisionAndPortableURL() throws {
    var s = try Site.open(root)
    let p = try s.assetPath("meter 2.svg", data: Data([42]))
    XCTAssertEqual(p, "assets/meter-2.svg")
    s.files[p] = SourceFile(path: p, data: Data([42]), new: true)
    XCTAssertEqual(try s.assetPath("meter 2.svg", data: Data([42])), p)
    XCTAssertEqual(try s.assetPath("meter 2.svg", data: Data([43])), "assets/meter-2-1.svg")
    XCTAssertEqual(
      Site.relative("art/a #.svg", from: "pages/deep/home.html"), "../../art/a%20%23.svg")
    try s.save(recovery: recovery)
    XCTAssertEqual(try data(p), Data([42]))
  }
  func testCreatePortableFolderWithoutOverwriting() throws {
    let dest = temp.appendingPathComponent("New Site")
    let blank = try String(
      contentsOf: fixtures.deletingLastPathComponent().appendingPathComponent(
        "Resources/blank.html"), encoding: .utf8)
    try Site.createFolder(at: dest, blankPage: blank)
    let site = try Site.open(dest)
    XCTAssertEqual(site.pages, ["index.html"])
    XCTAssertTrue(site.files["index.html"]?.text?.contains("css/site.css") == true)
    XCTAssertTrue(site.files["css/site.css"]?.text?.contains("display: flex") == true)
    XCTAssertNotNil(site.files["js/site.js"])
    XCTAssertThrowsError(try Site.createFolder(at: dest, blankPage: blank))
  }
  func testSampleCopiesHaveIndependentBytesAndFreshBaselines() throws {
    let shelf = temp.appendingPathComponent("Samples")
    let source = fixtures.appendingPathComponent("Site")
    var first = try Site.copySample(from: source, into: shelf)
    let sourceBytes = try Site.open(source).files.mapValues(\.bytes)
    let second = try Site.copySample(from: source, into: shelf)
    XCTAssertNotEqual(first.root, second.root)
    XCTAssertEqual(first.files.mapValues(\.bytes), sourceBytes)
    XCTAssertTrue(first.dirtyPaths.isEmpty)
    first.files["index.html"]!.bytes.append(Data("<!-- local -->".utf8))
    try first.save(recovery: recovery)
    XCTAssertNotEqual(try Site.open(first.root).files.mapValues(\.bytes), sourceBytes)
    XCTAssertEqual(try Site.open(second.root).files.mapValues(\.bytes), sourceBytes)
    XCTAssertEqual(try Site.open(source).files.mapValues(\.bytes), sourceBytes)
  }
  func testInvalidSampleLeavesNoPartialProject() throws {
    let shelf = temp.appendingPathComponent("Samples")
    try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: false)
    XCTAssertThrowsError(
      try Site.copySample(
        from: fixtures.appendingPathComponent("Field-Instrument.html"), into: shelf))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shelf.path), [])
  }
  func testWebsiteSnapshotPublishesDraftsAndPublicMediaWithoutTouchingOriginals() throws {
    let fm = FileManager.default
    let pdf = Data([0, 25, 255])
    try pdf.write(to: root.appendingPathComponent("manual.pdf"))
    try pdf.write(to: root.appendingPathComponent(".hidden.pdf"))
    try fm.createSymbolicLink(
      at: root.appendingPathComponent("shortcut.pdf"),
      withDestinationURL: temp.appendingPathComponent("outside.pdf"))
    let deps = root.appendingPathComponent("node_modules")
    try fm.createDirectory(at: deps, withIntermediateDirectories: false)
    try pdf.write(to: deps.appendingPathComponent("ignore.pdf"))
    var site = try Site.open(root)
    let html = try data("index.html")
    site.files["index.html"]!.bytes = Data("<p>Draft</p>".utf8)
    let destination = temp.appendingPathComponent("Snapshot")
    try site.exportWebsite(to: destination, entry: "notes.html")
    XCTAssertEqual(try data("index.html"), html)
    let reopened = try Site.open(destination)
    for (path, file) in site.files { XCTAssertEqual(reopened.files[path]?.bytes, file.bytes) }
    XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("manual.pdf")), pdf)
    for name in [".hidden.pdf", "shortcut.pdf", "node_modules/ignore.pdf"] {
      XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent(name).path))
    }
    XCTAssertThrowsError(try site.exportWebsite(to: destination, entry: "index.html"))
    XCTAssertThrowsError(
      try site.exportWebsite(to: root.appendingPathComponent("Recursive"), entry: "index.html"))
  }

  func testSnapshotFromNestedPageEscapesLandingLinkAndCleansUpFailedOutput() throws {
    let fm = FileManager.default
    let nested = temp.appendingPathComponent("Nested")
    let sub = nested.appendingPathComponent("field notes")
    try fm.createDirectory(at: sub, withIntermediateDirectories: true)
    let entry = "field notes/gear&shaft.html"
    try Data("<p>Test</p>".utf8).write(to: nested.appendingPathComponent(entry))
    var site = try Site.open(nested)
    let destination = temp.appendingPathComponent("Published")
    try site.exportWebsite(to: destination, entry: entry)
    let landing = try String(
      contentsOf: destination.appendingPathComponent("index.html"), encoding: .utf8)
    XCTAssertTrue(landing.contains("field%20notes/gear%26shaft.html"))
    site.files["../escape.txt"] = SourceFile(path: "../escape.txt", data: Data())
    let failed = temp.appendingPathComponent("Failed")
    XCTAssertThrowsError(try site.exportWebsite(to: failed, entry: entry))
    XCTAssertFalse(fm.fileExists(atPath: failed.path))
    XCTAssertFalse(
      try fm.contentsOfDirectory(atPath: temp.path).contains {
        $0.hasPrefix("WebBench-export-") || $0 == "escape.txt"
      })
  }
}

extension StorageTests {
  func testLargeOriginalsCanBeOpenedAndExportedWithoutRewritingThem() throws {
    let name = "art/camera.tiff"
    let original = Data(repeating: 0x61, count: 21 * 1024 * 1024)
    let url = root.appendingPathComponent(name)
    try original.write(to: url)
    var site = try Site.open(root)
    XCTAssertEqual(site.linkedAssets, [name])
    XCTAssertNil(site.files[name])
    XCTAssertTrue(site.workspacePaths.contains(name))
    try site.save(recovery: recovery)
    XCTAssertEqual(try Data(contentsOf: url), original)
    let snapshot = temp.appendingPathComponent("Exported")
    try site.exportWebsite(to: snapshot, entry: "index.html")
    XCTAssertEqual(try Data(contentsOf: snapshot.appendingPathComponent(name)), original)
    XCTAssertTrue(try Site.open(snapshot).linkedAssets.contains(name))
    let sample = try Site.copySample(from: root, into: temp)
    XCTAssertEqual(try Data(contentsOf: sample.root.appendingPathComponent(name)), original)
    try FileManager.default.removeItem(at: url)
    let failed = temp.appendingPathComponent("MissingPhoto")
    XCTAssertThrowsError(try site.exportWebsite(to: failed, entry: "index.html"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: failed.path))
  }
}
