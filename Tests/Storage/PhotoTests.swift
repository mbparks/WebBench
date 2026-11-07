import Foundation
import XCTest

@testable import BenchStorage

final class PhotoTests: XCTestCase {
  func testRotationAndMirrorUseDisplayedCoordinates() throws {
    // A B C on the first row, D E F on the second.
    let pixels: [UInt8] = (1...6).flatMap { index -> [UInt8] in [UInt8(index), 0, 0, 255] }
    let expected: [[UInt8]] = [
      [1, 2, 3, 4, 5, 6], [4, 1, 5, 2, 6, 3], [6, 5, 4, 3, 2, 1], [3, 6, 2, 5, 1, 4],
    ]
    var r = PhotoRecipe()
    for turn in 0..<4 {
      r.turns = turn
      let w = turn % 2 == 0 ? 3 : 2
      for mirror in [false, true] {
        r.mirror = mirror
        let rotated = try r.finish(pixels, width: 3, height: 2)
        let originalOrder = expected[turn]
        let order: [UInt8] = (0..<6).map { i in
          originalOrder[mirror ? (i / w) * w + w - 1 - (i % w) : i]
        }
        XCTAssertEqual(stride(from: 0, to: rotated.count, by: 4).map { rotated[$0] }, order)
      }
    }
  }
  func testCropBoundsSizeOrientationAndNoUpscaling() {
    var r = PhotoRecipe()
    r.crop = .centered(ratio: 1, imageWidth: 1200, imageHeight: 800)
    let box = r.crop.box(width: 1200, height: 800)
    XCTAssertEqual([box.x, box.y, box.w, box.h], [200, 0, 800, 800])
    r.crop = PhotoCrop(x: 0.25, y: 0, width: 0.5, height: 1)
    r.turns = 1
    let small = r.dimensions(width: 1200, height: 800, limit: 400)
    XCTAssertEqual([small.width, small.height], [400, 300])
    let full = r.dimensions(width: 1200, height: 800, limit: 4096)
    XCTAssertEqual([full.width, full.height], [800, 600])
    let corner = PhotoCrop(x: 1.2, y: 1, width: 0, height: 0).box(width: 12, height: 10)
    XCTAssertEqual([corner.x, corner.y, corner.w, corner.h], [11, 9, 1, 1])
  }
  func testFiltersKeepTransparentPixelsAndRespectPremultipliedAlpha() throws {
    let original: [UInt8] = [90, 35, 20, 128, 0, 0, 0, 0]
    var results = Set<[UInt8]>()
    for f in PhotoFilter.allCases {
      var r = PhotoRecipe()
      r.filter = f
      let result = try r.finish(original, width: 2, height: 1)
      XCTAssertEqual(Array(result[4..<8]), [0, 0, 0, 0])
      XCTAssertEqual(result[3], 128)
      XCTAssertTrue(result[0..<3].allSatisfy { $0 <= 128 })
      if f == .mono {
        XCTAssertEqual(result[0], result[1])
        XCTAssertEqual(result[1], result[2])
      }
      if f == .original { XCTAssertEqual(result, original) }
      results.insert(result)
    }
    XCTAssertEqual(results.count, PhotoFilter.allCases.count)
    var r = PhotoRecipe()
    r.brightness = 0.2
    r.saturation = 0
    r.contrast = 1.2
    let adjusted = try r.finish(original, width: 2, height: 1)
    XCTAssertEqual(adjusted[0], adjusted[1])
    XCTAssertEqual(adjusted[1], adjusted[2])
    XCTAssertGreaterThan(adjusted[0], original[2])
  }
  func testBordersDrawWithinFrameAndPreserveCenter() throws {
    let w = 30
    let h = 30
    let original = [UInt8](repeating: 0, count: w * h * 4)
    let edge: [UInt8] = [0x18, 0x42, 0x72, 255]
    for frame in PhotoBorder.allCases {
      var r = PhotoRecipe()
      r.border = frame
      r.borderRGB = 0x184272
      r.borderPercent = 10
      let output = try r.finish(original, width: w, height: h)
      func isFrame(_ x: Int, _ y: Int) -> Bool {
        let i = (w * y + x) * 4
        return Array(output[i..<i + 4]) == edge
      }
      XCTAssertEqual(isFrame(0, 0), frame != .none)
      XCTAssertFalse(isFrame(15, 15))
      XCTAssertEqual(isFrame(15, 2), [.mat, .line, .print].contains(frame))
      XCTAssertEqual(isFrame(15, 3), [.mat, .double].contains(frame))
      XCTAssertEqual(isFrame(15, 22), frame == .print)
    }
  }
  func testBudgetFallbackMakesProgressEvenWhenNearlyAtLimit() {
    for current in [2, 20, 1600, 4096] {
      for bytes in [1001, 2000, 100000] {
        let next = PhotoRecipe.smallerEdge(current, bytes: bytes, budget: 1000)
        XCTAssertLessThan(next, current)
        XCTAssertGreaterThanOrEqual(next, 1)
      }
    }
  }
}
