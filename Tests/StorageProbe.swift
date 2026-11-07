// Command-line adapter used by the optional browser fixture harness.
import Foundation

@main enum StorageProbe {
  static func main() throws {
    let a = CommandLine.arguments
    if a.count == 6 && a[1] == "--snapshot" {
      var site = try Site.open(URL(fileURLWithPath: a[2]))
      let entry = a[3]
      guard let file = site.files[entry] else { throw BenchError("Missing fixture entry") }
      let bytes = try file.encoded(String(contentsOfFile: a[4], encoding: .utf8))
      site.files[entry]!.bytes = bytes
      let dest = URL(fileURLWithPath: a[5])
      try site.exportWebsite(to: dest, entry: entry)
      guard try Site.open(dest).files[entry]?.bytes == bytes else {
        throw BenchError("Snapshot changed")
      }
      return
    }
    guard a.count >= 2, (a.count - 2).isMultiple(of: 2) else {
      throw BenchError("Usage: storage-probe project [relative-path UTF8-staged-file]...")
    }
    var site = try Site.open(URL(fileURLWithPath: a[1]))
    for i in stride(from: 2, to: a.count, by: 2) {
      guard let f = site.files[a[i]] else { throw BenchError("Fixture file missing") }
      site.files[a[i]]!.bytes = try f.encoded(String(contentsOfFile: a[i + 1], encoding: .utf8))
    }
    try site.save(
      recovery: FileManager.default.temporaryDirectory.appendingPathComponent(
        "WebBench-Probe-Recovery"))
    _ = try Site.open(URL(fileURLWithPath: a[1]))
  }
}
