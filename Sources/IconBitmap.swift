import Foundation

/// Straight-alpha sRGB pixels, top row first. Each UInt32 is 0xRRGGBBAA.
struct IconBitmap: Equatable {
  static let sizes = [16, 32, 48, 64]
  let size: Int
  var pixels: [UInt32]
  init(size: Int = 32) {
    precondition(Self.sizes.contains(size))
    self.size = size
    self.pixels = Array(repeating: 0, count: size * size)
  }
  func scaled(to side: Int) -> IconBitmap {
    var result = IconBitmap(size: side)
    for y in 0..<side {
      for x in 0..<side {
        let fromX = (2 * x + 1) * size / (2 * side)
        let fromY = (2 * y + 1) * size / (2 * side)
        result.pixels[y * side + x] = pixels[fromY * size + fromX]
      }
    }
    return result
  }
  mutating func stroke(from a: (Int, Int), to b: (Int, Int), color: UInt32) {
    guard [a.0, a.1, b.0, b.1].allSatisfy({ (0..<size).contains($0) }) else { return }
    var x = a.0
    var y = a.1
    let dx = abs(b.0 - x)
    let dy = -abs(b.1 - y)
    let sx = x < b.0 ? 1 : -1
    let sy = y < b.1 ? 1 : -1
    var error = dx + dy
    while true {
      pixels[y * size + x] = color
      if x == b.0 && y == b.1 { break }
      let twice = 2 * error
      if twice >= dy {
        error += dy
        x += sx
      }
      if twice <= dx {
        error += dx
        y += sy
      }
    }
  }
  mutating func fill(x: Int, y: Int, color: UInt32) {
    guard (0..<size).contains(x), (0..<size).contains(y) else { return }
    let first = y * size + x
    let previous = pixels[first]
    guard previous != color else { return }
    pixels[first] = color
    var pending = [first]
    while let i = pending.popLast() {
      let col = i % size
      let row = i / size
      for (nx, ny) in [(col - 1, row), (col + 1, row), (col, row - 1), (col, row + 1)]
      where (0..<size).contains(nx) && (0..<size).contains(ny) {
        let j = ny * size + nx
        if pixels[j] == previous {
          pixels[j] = color
          pending.append(j)
        }
      }
    }
  }
  static func initials(_ label: String, size: Int, color: UInt32) throws -> IconBitmap {
    let text = label.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    // Five-column bitmap capitals and numerals stay legible at favicon sizes.
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    let shapes = [
      "0E11111F111111", "1E11111E11111E", "0F10101010100F", "1E11111111111E",
      "1F10101E10101F", "1F10101E101010", "0F10101711110F", "1111111F111111",
      "1F04040404041F", "0702020212120C", "11121418141211", "1010101010101F",
      "111B1515111111", "11191915131311", "0E11111111110E", "1E11111E101010",
      "0E11111115120D", "1E11111E141211", "0F10100E01011E", "1F040404040404",
      "1111111111110E", "11111111110A04", "1111111515150A", "11110A040A1111",
      "11110A04040404", "1F01020408101F", "0E11131519110E", "040C040404040E",
      "0E11010204081F", "1E01010E01011E", "02060A121F0202", "1F10101E01011E",
      "0E10101E11110E", "1F010204080808", "0E11110E11110E", "0E11110F01010E",
    ]
    guard (1...3).contains(text.count), text.allSatisfy({ alphabet.contains($0) }) else {
      throw BenchError("Enter one to three letters or digits.")
    }
    let width = 6 * text.count - 1
    guard width <= size else { throw BenchError("Choose a larger grid for three initials.") }
    let scale = max(1, min((size - 2) / width, (size - 2) / 7))
    let left = (size - width * scale) / 2
    let top = (size - 7 * scale) / 2
    var result = IconBitmap(size: size)
    for (index, letter) in text.enumerated() {
      let bytes = Array(shapes[alphabet.firstIndex(of: letter)!].utf8)
      for row in 0..<7 {
        let mask = Int(String(decoding: bytes[row * 2..<row * 2 + 2], as: UTF8.self), radix: 16)!
        for col in 0..<5 where mask & (1 << (4 - col)) != 0 {
          for dy in 0..<scale {
            for dx in 0..<scale {
              result.pixels[
                (top + row * scale + dy) * size + left + (index * 6 + col) * scale + dx] = color
            }
          }
        }
      }
    }
    return result
  }

  static func ico(images: [(side: Int, png: Data)]) throws -> Data {
    guard !images.isEmpty, images.count <= 4, Set(images.map(\.side)).count == images.count,
      images.allSatisfy({
        sizes.contains($0.side) && $0.png.count < 1_000_000
          && $0.png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
      })
    else { throw BenchError("Cannot assemble favicon sizes.") }
    var result = Data([0, 0, 1, 0, UInt8(images.count), 0])
    func little(_ value: Int) -> [UInt8] {
      (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }
    var offset = 6 + 16 * images.count
    for image in images {
      result.append(contentsOf: [UInt8(image.side), UInt8(image.side), 0, 0, 1, 0, 32, 0])
      result.append(contentsOf: little(image.png.count))
      result.append(contentsOf: little(offset))
      offset += image.png.count
    }
    for image in images { result.append(image.png) }
    return result
  }
}

struct IconLink: Decodable, Identifiable {
  let id: Int
  let href: String, sizes: String, media: String
  var label: String {
    let name =
      href.hasPrefix("data:")
      ? "Embedded icon" : (href.split(separator: "?").first.map(String.init) ?? href)
    return ([String(name.prefix(50)), sizes, media].filter { !$0.isEmpty }).joined(separator: " · ")
  }
}
struct IconLinks: Decodable { let base: String, links: [IconLink] }
