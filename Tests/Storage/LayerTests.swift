import Foundation
import XCTest

@testable import BenchStorage

final class LayerTests: XCTestCase {
  private var order: LayerOrder {
    let tags = [
      ("body", -1, 0), ("section", 0, 1), ("div", 1, 2), ("p", 2, 3), ("button", 1, 2),
      ("aside", 0, 1), ("ul", 5, 2), ("li", 6, 3), ("p", 5, 2),
    ]
    let rows = tags.enumerated().map { i, v in
      ElementRow(
        id: i, parent: v.1, depth: v.2, tag: v.0, label: v.0, name: v.0, start: i, length: 1)
    }
    return LayerOrder(
      nodes: rows,
      layerParents: [
        "*": ["body", "section", "div", "aside", "li"], "body": [], "li": ["ul", "ol"],
      ])
  }
  func testThreeDropZonesAtNestedContainer() {
    XCTAssertEqual(order.slot(for: 4, at: 5, zone: .before), LayerSlot(parent: 0, before: 5))
    XCTAssertEqual(order.slot(for: 4, at: 5, zone: .inside), LayerSlot(parent: 5, before: nil))
    XCTAssertEqual(order.slot(for: 4, at: 5, zone: .after), LayerSlot(parent: 0, before: nil))
    XCTAssertEqual(order.slot(for: 8, at: 2, zone: .after), LayerSlot(parent: 1, before: 4))
  }
  func testKeyboardMovesUseSameSlotsAsDragging() {
    XCTAssertEqual(order.slot(for: 4, step: .up), order.slot(for: 4, at: 2, zone: .before))
    XCTAssertEqual(order.slot(for: 2, step: .down), order.slot(for: 2, at: 4, zone: .after))
    XCTAssertEqual(order.slot(for: 4, step: .indent), order.slot(for: 4, at: 2, zone: .inside))
    XCTAssertEqual(order.slot(for: 3, step: .outdent), LayerSlot(parent: 1, before: 4))
  }
  func testRootCycleNoOpAndContentModel() {
    XCTAssertNil(order.slot(for: 0, at: 5, zone: .after))
    XCTAssertNil(order.slot(for: 2, at: 3, zone: .inside))
    XCTAssertNil(order.slot(for: 2, at: 4, zone: .before))
    XCTAssertNil(order.slot(for: 3, step: .down))
    XCTAssertNil(order.slot(for: 4, at: 6, zone: .inside))
    XCTAssertNil(order.slot(for: 7, at: 1, zone: .inside))
    XCTAssertNil(order.slot(for: 4, at: 99, zone: .before))
  }
  func testMediaRangeBounds() {
    XCTAssertEqual(Site.mediaRange("bytes=0-1", length: 640), 0..<2)
    XCTAssertEqual(Site.mediaRange("bytes=-32", length: 640), 608..<640)
    XCTAssertEqual(Site.mediaRange("bytes=2-", length: 640), 2..<640)
    XCTAssertEqual(Site.mediaRange("bytes=2-999999", length: 640), 2..<640)
    for value in ["bytes=641-", "bytes=2-1", "bytes=-0", "foo", "bytes=-", "bytes=2-3,5-8"] {
      XCTAssertNil(Site.mediaRange(value, length: 640))
    }
  }
}
