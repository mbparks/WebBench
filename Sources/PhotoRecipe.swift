import Foundation

enum PhotoFilter: String, CaseIterable {
  case original = "Original"
  case mono = "Black & white"
  case sepia = "Sepia"
  case warm = "Warm"
  case cool = "Cool"
  case vivid = "Vivid"
}
enum PhotoBorder: String, CaseIterable {
  case none = "None"
  case line = "Solid"
  case double = "Double line"
  case mat = "Mat"
  case print = "Instant print"
}
struct PhotoCrop: Equatable {
  var x = 0.0, y = 0.0, width = 1.0, height = 1.0
  static func centered(ratio: Double, imageWidth: Int, imageHeight: Int) -> Self {
    let aspect = Double(imageWidth) / Double(imageHeight)
    let w = min(1, ratio / aspect)
    let h = min(1, aspect / ratio)
    return Self(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
  }
  func box(width w: Int, height h: Int) -> (x: Int, y: Int, w: Int, h: Int) {
    let l = max(0, min(w - 1, Int((x * Double(w)).rounded())))
    let t = max(0, min(h - 1, Int((y * Double(h)).rounded())))
    let r = min(w, max(l + 1, Int(((x + width) * Double(w)).rounded())))
    let b = min(h, max(t + 1, Int(((y + height) * Double(h)).rounded())))
    return (l, t, r - l, b - t)
  }
}
struct PhotoRecipe: Equatable {
  var crop = PhotoCrop()
  var turns = 0, mirror = false
  var edge = 1600, brightness = 0.0, contrast = 1.0, saturation = 1.0
  var filter = PhotoFilter.original, border = PhotoBorder.none, borderPercent = 3.0
  var borderRGB: UInt32 = 0xffffff
  func dimensions(width: Int, height: Int, limit: Int) -> (width: Int, height: Int) {
    let region = crop.box(width: width, height: height)
    let scale = min(1, Double(max(1, min(edge, limit))) / Double(max(region.w, region.h)))
    let w = max(1, Int((Double(region.w) * scale).rounded()))
    let h = max(1, Int((Double(region.h) * scale).rounded()))
    return turns % 2 == 0 ? (w, h) : (h, w)
  }
  /// Input and output are top-down, premultiplied sRGB. Scaling is performed by Core Graphics before this pass.
  func finish(_ input: [UInt8], width: Int, height: Int) throws -> [UInt8] {
    let turn = (turns % 4 + 4) % 4
    let w = turn % 2 == 0 ? width : height
    let h = turn % 2 == 0 ? height : width
    guard w > 0, h > 0, input.count == 4 * w * h else {
      throw BenchError("Invalid photo dimensions.")
    }
    if turn == 0 && !mirror && filter == .original && brightness == 0 && contrast == 1
      && saturation == 1 && border == .none
    {
      return input
    }
    var result = [UInt8](repeating: 0, count: input.count)
    let inset = max(1, Int((Double(min(w, h)) * borderPercent / 100).rounded()))
    let line = max(1, inset / 4)
    let red = UInt8((borderRGB >> 16) & 255)
    let green = UInt8((borderRGB >> 8) & 255)
    let blue = UInt8(borderRGB & 255)
    let adjust = filter != .original || brightness != 0 || contrast != 1 || saturation != 1
    for y in 0..<h {
      if y % 64 == 0 { try Task.checkCancellation() }
      for x in 0..<w {
        let out = (y * w + x) * 4
        let dist = min(min(x, w - 1 - x), min(y, h - 1 - y))
        let framed: Bool
        switch border {
        case .none: framed = false
        case .line: framed = dist < inset
        case .double: framed = dist < line || (dist >= inset && dist < inset + line)
        case .mat: framed = dist < inset * 2
        case .print: framed = dist < inset || h - 1 - y < inset * 3
        }
        if framed {
          result[out] = red
          result[out + 1] = green
          result[out + 2] = blue
          result[out + 3] = 255
          continue
        }
        let u = mirror ? w - 1 - x : x
        let i: Int
        switch turn {
        case 1: i = ((height - 1 - u) * width + y) * 4
        case 2: i = ((height - 1 - y) * width + width - 1 - u) * 4
        case 3: i = (u * width + width - 1 - y) * 4
        default: i = (y * width + u) * 4
        }
        let a = input[i + 3]
        result[out + 3] = a
        guard adjust && a > 0 else {
          result[out] = input[i]
          result[out + 1] = input[i + 1]
          result[out + 2] = input[i + 2]
          continue
        }
        let alpha = Double(a) / 255
        var r = Double(input[i]) / alpha
        var g = Double(input[i + 1]) / alpha
        var b = Double(input[i + 2]) / alpha
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        var sat = saturation
        var con = contrast
        switch filter {
        case .original: break
        case .mono:
          r = lum
          g = lum
          b = lum
        case .sepia:
          (r, g, b) = (
            0.393 * r + 0.769 * g + 0.189 * b, 0.349 * r + 0.686 * g + 0.168 * b,
            0.272 * r + 0.534 * g + 0.131 * b
          )
        case .warm:
          r *= 1.09
          b *= 0.89
        case .cool:
          r *= 0.91
          b *= 1.10
        case .vivid:
          sat *= 1.28
          con *= 1.12
        }
        let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
        func channel(_ v: Double) -> UInt8 {
          UInt8(
            (min(255, max(0, ((l + (v - l) * sat) - 127.5) * con + 127.5 + brightness * 255))
              * alpha).rounded())
        }
        result[out] = channel(r)
        result[out + 1] = channel(g)
        result[out + 2] = channel(b)
      }
    }
    return result
  }
  static func smallerEdge(_ edge: Int, bytes: Int, budget: Int) -> Int {
    let fraction = min(0.85, 0.92 * sqrt(Double(max(1, budget)) / Double(max(1, bytes))))
    return max(1, Int(Double(edge) * fraction))
  }
}
