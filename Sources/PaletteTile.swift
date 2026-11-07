import AppKit
import SwiftUI

/// Tracks the entire mouse gesture in the originating control, including travel across the WebKit view.
struct PaletteTile: NSViewRepresentable {
  let item: String
  let title: String
  let symbol: String
  @ObservedObject var model: Session

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: Tile, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? 90, height: proposal.height ?? 63)
  }
  func makeNSView(context: Context) -> Tile {
    let tile = Tile(title: title, target: nil, action: nil)
    tile.isBordered = false
    tile.imagePosition = .imageLeading
    tile.alignment = .left
    tile.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    tile.toolTip = "Drag onto the page, or click and then choose a position."
    tile.setAccessibilityLabel("Insert " + title)
    tile.identifier = NSUserInterfaceItemIdentifier("insert-" + item)
    tile.target = tile
    tile.action = #selector(Tile.arm)
    return tile
  }
  func updateNSView(_ tile: Tile, context: Context) {
    tile.model = model
    tile.item = item
    tile.title = title
    tile.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    if let parent = tile.insertionParent {
      tile.toolTip = "Click to add inside " + parent.label + ", or drag to another location."
    } else {
      tile.toolTip = "Drag onto the page, or click and then choose a position."
    }
    tile.state = model.insertTool == item ? .on : .off
    tile.isEnabled = !model.running && !model.busy
  }

  final class Tile: NSButton {
    override func draw(_ dirtyRect: NSRect) {
      // PartCard draws the face. Retain a visible keyboard focus ring on the native control.
      if window?.firstResponder === self {
        NSColor.keyboardFocusIndicatorColor.setStroke()
        let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
        ring.lineWidth = 2
        ring.stroke()
      }
    }
    weak var model: Session?
    var item = ""
    private var down: NSPoint?
    private var dragging = false
    private weak var canvas: Canvas.Coordinator?
    private var monitor: Any?
    var insertionParent: ElementRow? {
      guard let model, !model.dropOnPage, let parent = model.selectedContainer,
        parent.tag != "body",
        let entry = model.elements.first(where: { $0.id == item }),
        model.accepts(entry.tag, in: parent)
      else { return nil }
      return parent
    }
    @objc func arm() {
      guard let model else { return }
      if let parent = insertionParent, let entry = model.elements.first(where: { $0.id == item }) {
        model.insertChild(entry, in: parent.id)
        return
      }
      model.afterWriting {
        model.setWriting(false)
        model.arm(self.item)
      }
    }
    override func resetCursorRects() {
      super.resetCursorRects()
      addCursorRect(bounds, cursor: .openHand)
    }
    override func mouseDown(with event: NSEvent) {
      guard isEnabled else { return }
      down = event.locationInWindow
      highlight(true)
    }
    override func mouseDragged(with event: NSEvent) {
      guard let down, let model, let window else { return }
      let p = event.locationInWindow
      if !dragging {
        guard hypot(p.x - down.x, p.y - down.y) >= 3 else { return }
        canvas = model.writing ? model.writer : model.designer
        guard canvas?.ready == true else { return }
        dragging = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
          if e.keyCode == 53, let self {
            self.finish(cancel: true)
            return nil
          }
          return e
        }
      }
      canvas?.palette(
        item, phase: "hover", screen: window.convertPoint(toScreen: p),
        snap: model.snap && !event.modifierFlags.contains(.option))
    }
    override func mouseUp(with event: NSEvent) {
      guard down != nil else { return }
      if dragging, let window {
        canvas?.palette(
          item, phase: "drop", screen: window.convertPoint(toScreen: event.locationInWindow),
          snap: model?.snap == true && !event.modifierFlags.contains(.option))
      } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
        arm()
      }
      finish(cancel: false)
    }
    private func finish(cancel: Bool) {
      if cancel { canvas?.palette(item, phase: "cancel", screen: .zero, snap: false) }
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      canvas = nil
      dragging = false
      down = nil
      highlight(false)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if newWindow == nil { finish(cancel: true) }
      super.viewWillMove(toWindow: newWindow)
    }
  }
}
