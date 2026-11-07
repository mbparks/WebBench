// Portable adapter for the production photo geometry, effects and asset store.
import Foundation

@main enum PhotoProbe {
  static func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    let work = URL(fileURLWithPath: args[1])
    func file(_ name: String) -> URL { work.appendingPathComponent(name) }
    let width = 3200
    let height = 2400
    var recipe = PhotoRecipe()
    recipe.crop = .centered(ratio: 16.0 / 9.0, imageWidth: width, imageHeight: height)
    recipe.edge = 640
    recipe.turns = 1
    recipe.mirror = true
    recipe.filter = .mono
    recipe.border = .print
    recipe.borderPercent = 5
    recipe.borderRGB = 0x245c49
    let box = recipe.crop.box(width: width, height: height)
    let dims = recipe.dimensions(width: width, height: height, limit: recipe.edge)
    switch args[0] {
    case "geometry": print(box.x, box.y, box.w, box.h, dims.width, dims.height)
    case "pixels":
      let rgba = try Data(contentsOf: file("input.rgba"))
      let edited = try recipe.finish(Array(rgba), width: dims.height, height: dims.width)
      try Data(edited).write(to: file("result.rgba"))
    case "publish":
      var site = try Site.open(file("Site"))
      let image = try Data(contentsOf: file("edited.png"))
      let asset = try site.assetPath("field-edited.png", data: image)
      guard asset == "assets/field-edited.png" else { throw BenchError("Unexpected asset path.") }
      site.files[asset] = SourceFile(path: asset, data: image)
      site.files[asset]?.original = nil
      guard let page = site.files["index.html"] else { throw BenchError("Missing page.") }
      site.files["index.html"]?.bytes = try page.encoded(
        String(contentsOf: file("patched.html"), encoding: .utf8))
      try site.save(recovery: file("Recovery"))
      try Site.open(file("Site")).exportWebsite(to: file("Published"), entry: "index.html")
      _ = try Site.open(file("Published"))
    default: throw BenchError("Unknown photo fixture command.")
    }
  }
}
