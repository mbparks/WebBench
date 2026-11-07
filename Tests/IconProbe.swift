// Adapter for the optional independent PNG/ICO decoder check.
import Foundation

@main enum IconProbe {
  static func main() throws {
    guard CommandLine.arguments.count == 3 else {
      throw BenchError("Expected mode and fixture directory.")
    }
    let mode = CommandLine.arguments[1]
    let dir = URL(fileURLWithPath: CommandLine.arguments[2])
    let sizes = [16, 32, 48]
    switch mode {
    case "paint":
      var mark = try IconBitmap.initials("GS", size: 32, color: 0x225B_48FF)
      mark.stroke(from: (0, 0), to: (3, 3), color: 0xCC33_44FF)
      mark.pixels[31] = 0x5599_DD80
      for n in sizes {
        let bytes = mark.scaled(to: n).pixels.flatMap { v in
          [
            UInt8(v >> 24), UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 8),
            UInt8(truncatingIfNeeded: v),
          ]
        }
        try Data(bytes).write(to: dir.appendingPathComponent("\(n).rgba"))
      }
    case "pack":
      let ico = try IconBitmap.ico(
        images: sizes.map { n in (n, try Data(contentsOf: dir.appendingPathComponent("\(n).png"))) }
      )
      try ico.write(to: dir.appendingPathComponent("favicon.ico"))
    default: throw BenchError("Unknown fixture action.")
    }
  }
}
