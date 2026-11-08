import AppKit
import SwiftUI

/// The native control handles clicks and hands palette drags to AppKit.
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

  final class Tile: NSButton, NSDraggingSource {
    static let partType = NSPasteboard.PasteboardType("com.greenshoegarage.webbench.palette-part")
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
    private var dragToken: String?
    var insertionParent: ElementRow? {
      guard let model, !model.targetsPage, let parent = model.selectedContainer,
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
      dragToken = model?.preview?.token
      down = event.locationInWindow
      highlight(true)
    }
    override func mouseDragged(with event: NSEvent) {
      guard let down, let token = dragToken,
        hypot(event.locationInWindow.x - down.x, event.locationInWindow.y - down.y) >= 3
      else { return }
      self.down = nil
      highlight(false)
      let paste = NSPasteboardItem()
      paste.setPropertyList(["token": token, "item": item], forType: Self.partType)
      let part = NSDraggingItem(pasteboardWriter: paste)
      let size = NSSize(width: max(88, (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + 28), height: 32)
      let label = title as NSString
      let badge = NSImage(size: size, flipped: false) { rect in
        NSColor(calibratedRed: 0.09, green: 0.30, blue: 0.23, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        label.draw(at: NSPoint(x: 12, y: 8), withAttributes: [
          .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white
        ])
        return true
      }
      let pt = convert(event.locationInWindow, from: nil)
      part.setDraggingFrame(NSRect(x: pt.x - 12, y: pt.y - 16, width: size.width, height: size.height), contents: badge)
      beginDraggingSession(with: [part], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
      context == .withinApplication ? .copy : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
      if let model, let token = dragToken {
        let canvas = model.writing ? model.writer : model.designer
        if canvas?.state.token == token {
          canvas?.palette(item, phase: "cancel", screen: screenPoint, snap: false)
        }
      }
      dragToken = nil
    }
    override func mouseUp(with event: NSEvent) {
      guard down != nil else { return }
      down = nil
      dragToken = nil
      highlight(false)
      if bounds.contains(convert(event.locationInWindow, from: nil)) { arm() }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if newWindow == nil { down = nil; dragToken = nil }
      super.viewWillMove(toWindow: newWindow)
    }
  }
}
