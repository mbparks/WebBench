import Foundation
import XCTest

@testable import BenchStorage

final class IconTests: XCTestCase {
  func testPencilStrokeConnectsSparseSamplesAndFillStopsAtBoundaries() {
    var icon = IconBitmap(size: 16)
    icon.stroke(from: (4, 0), to: (4, 15), color: 0xAA00_22FF)
    icon.fill(x: 0, y: 8, color: 0x66BB_7780)
    for row in 0..<16 {
      XCTAssertEqual(
        Array(icon.pixels[row * 16..<row * 16 + 4]), Array(repeating: 0x66BB_7780, count: 4))
      XCTAssertEqual(icon.pixels[row * 16 + 4], 0xAA00_22FF)
      XCTAssertEqual(icon.pixels[row * 16 + 5], 0)
    }
    let copy = icon
    icon.stroke(from: (-1, 2), to: (5, 6), color: 1)
    icon.fill(x: 16, y: 0, color: 0)
    XCTAssertEqual(icon, copy)
    icon.stroke(from: (4, 0), to: (4, 15), color: 0)
    XCTAssertEqual(icon.pixels[4], 0)
  }
  func testScalingAndMonogramsRetainCornersAndTransparency() throws {
    let mark = try IconBitmap.initials("gsg", size: 32, color: 0x225B_48FF)
    XCTAssertEqual(Set(mark.pixels), [0, 0x225B_48FF])
    XCTAssertEqual(mark, try IconBitmap.initials("GSG", size: 32, color: 0x225B_48FF))
    XCTAssertTrue([0, 31, 992, 1023].allSatisfy { mark.pixels[$0] == 0 })
    for a in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
      let i = try IconBitmap.initials(String(a), size: 16, color: 0xFF)
      XCTAssertEqual(Set(i.pixels), [0, 0xFF])
    }
    XCTAssertThrowsError(try IconBitmap.initials("GSG", size: 16, color: 1))
    XCTAssertThrowsError(try IconBitmap.initials("!", size: 32, color: 1))
    var icon = IconBitmap(size: 16)
    icon.pixels[0] = 1
    icon.pixels[255] = 2
    let large = icon.scaled(to: 32)
    XCTAssertEqual(large.pixels[33], 1)
    XCTAssertEqual(large.pixels.last, 2)
    XCTAssertEqual(large.scaled(to: 16), icon)
  }
  func testICOImageOffsetsAndSizes() throws {
    let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3])
    let data = try IconBitmap.ico(images: [(16, png), (32, png), (48, png)])
    XCTAssertEqual(Array(data[0..<6]), [0, 0, 1, 0, 3, 0])
    for (i, size) in [16, 32, 48].enumerated() {
      let row = 6 + 16 * i
      let offset = 54 + i * png.count
      XCTAssertEqual(data[row], UInt8(size))
      XCTAssertEqual(data[row + 1], UInt8(size))
      XCTAssertEqual(data[row + 8], UInt8(png.count))
      XCTAssertEqual(data[row + 12], UInt8(offset))
      XCTAssertEqual(data.subdata(in: offset..<offset + png.count), png)
    }
    XCTAssertThrowsError(try IconBitmap.ico(images: [(32, png), (32, png)]))
  }
  func testSharedArtworkUntouchedAndStandaloneIconEmbedded() throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: tmp) }
    try fm.createDirectory(
      at: tmp.appendingPathComponent("assets"), withIntermediateDirectories: true)
    let page = tmp.appendingPathComponent("assets/notes.html")
    try Data("<html><head></head><body></body></html>".utf8).write(to: page)
    let old = Data([1, 2, 3])
    let fresh = Data([4, 5, 6])
    try old.write(to: tmp.appendingPathComponent("assets/favicon.png"))
    var project = try Site.open(tmp)
    let next = try project.faviconAsset(fresh, from: "assets/notes.html", hasBase: false)
    XCTAssertEqual(next.url, "favicon-1.png")
    XCTAssertEqual(next.newPath, "assets/favicon-1.png")
    project.files[next.newPath!] = SourceFile(path: next.newPath!, data: fresh, new: true)
    XCTAssertNil(try project.faviconAsset(fresh, from: "assets/notes.html", hasBase: false).newPath)
    XCTAssertEqual(try Data(contentsOf: tmp.appendingPathComponent("assets/favicon.png")), old)
    XCTAssertEqual(
      try project.faviconAsset(fresh, from: "assets/notes.html", hasBase: true).url,
      "data:image/png;base64,BAUG")
    XCTAssertEqual(
      try Site.open(page).faviconAsset(fresh, from: "notes.html", hasBase: false).url,
      "data:image/png;base64,BAUG")
  }
}
