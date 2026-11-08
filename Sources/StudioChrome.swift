import AppKit
import SwiftUI

enum StudioInk {
  static let forest = Color(red: 0.074, green: 0.176, blue: 0.153)
  static let lime = Color(red: 0.83, green: 0.93, blue: 0.57)

  private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(
          srgbRed: CGFloat(rgb >> 16) / 255, green: CGFloat(rgb >> 8 & 255) / 255,
          blue: CGFloat(rgb & 255) / 255, alpha: 1)
      })
  }
  static let paper = adaptive(0xF7F6F0, 0x232B29)
  static let card = adaptive(0xFFFDF8, 0x2B3431)
  static let mat = adaptive(0xD8DFD7, 0x151D1C)
  static let line = adaptive(0xCCD1C7, 0x49534D)
  static let green = adaptive(0x33634F, 0xA8D6AF)
  static let plum = adaptive(0x84506E, 0xDDAECB)
  static let blue = adaptive(0x416784, 0xA2C8E5)
  static let clay = adaptive(0x925638, 0xE7BA9D)
  static let gold = adaptive(0x776024, 0xDECF89)

  static func color(for group: String) -> Color {
    switch group {
    case "Text & lists": return plum
    case "Media & data": return blue
    case "Forms": return clay
    case "Landmarks": return gold
    default: return green
    }
  }
}

struct BenchMark: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8).fill(StudioInk.lime)
      Image(systemName: "square.3.layers.3d").font(.system(size: 18, weight: .bold))
        .foregroundStyle(StudioInk.forest)
    }.frame(width: 31, height: 31).accessibilityHidden(true)
  }
}

struct WorkMat: View {
  var body: some View {
    SwiftUI.Canvas { context, size in
      var dots = Path()
      for x in stride(from: 6.0, to: Double(size.width), by: 14) {
        for y in stride(from: 6.0, to: Double(size.height), by: 14) {
          dots.addEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
        }
      }
      context.fill(dots, with: .color(StudioInk.green.opacity(0.24)))
    }.background(StudioInk.mat).accessibilityHidden(true).allowsHitTesting(false)
  }
}

/// The AppKit button on top receives both accessibility activation and continuous native drags.
struct PartCard: View {
  let part: InsertElement
  @ObservedObject var model: Session
  @State private var hovering = false

  private var accent: Color {
    switch part.id {
    case "Heading", "Text box", "Paragraph": return StudioInk.plum
    case "Image": return StudioInk.blue
    case "Button": return StudioInk.clay
    default: return StudioInk.color(for: part.group)
    }
  }
  var body: some View {
    let armed = model.insertTool == part.id
    ZStack {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Group {
            if let shape = part.shape {
              PaletteSilhouette(geometry: shape).fill(accent).frame(width: 22, height: 18)
            } else if part.id == "Heading" {
              Text("Aa").font(.system(size: 22, weight: .medium, design: .serif))
            } else {
              Image(systemName: part.symbol).font(.system(size: 17, weight: .medium))
            }
          }.foregroundStyle(accent)
            .frame(minWidth: 30, minHeight: 24)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
          Spacer()
          if armed { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
        }.frame(height: 22)
        Text(part.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(7)
      .background(
        armed || hovering ? accent.opacity(0.12) : StudioInk.card,
        in: RoundedRectangle(cornerRadius: 7)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7).strokeBorder(
          armed || hovering ? accent : StudioInk.line,
          lineWidth: armed ? 2 : 1)
      )
      .accessibilityHidden(true).allowsHitTesting(false)
      PaletteTile(item: part.id, title: part.title, symbol: part.symbol, model: model)
    }
    .frame(height: 63).onHover { hovering = $0 }
  }
}

private struct PaletteSilhouette: Shape {
  let geometry: ShapeSilhouette

  func path(in bounds: CGRect) -> Path {
    let scale = min(bounds.width / geometry.width, bounds.height / geometry.height)
    let width = geometry.width * scale, height = max(1.5, geometry.height * scale)
    let rect = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    if geometry.ellipse == true { return Path(ellipseIn: rect) }
    if let vertices = geometry.points {
      var path = Path()
      for (i, vertex) in vertices.enumerated() {
        let point = CGPoint(x: rect.minX + width * vertex[0] / 100, y: rect.minY + height * vertex[1] / 100)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      path.closeSubpath()
      return path
    }
    let radius = min((geometry.radius ?? 0) * scale, min(width, height) / 2)
    return Path(roundedRect: rect, cornerRadius: radius, style: .circular)
  }
}

struct PanelTitle: View {
  let title: String
  var body: some View {
    Text(title).font(.system(size: 21, weight: .medium, design: .serif))
      .accessibilityAddTraits(.isHeader)
  }
}
