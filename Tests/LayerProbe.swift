// Adapter that drives the same Layers destination calculation used by the native sidebar.
import Foundation

@main enum LayerProbe {
  struct Request: Decodable {
    let nodes: [ElementRow], rules: [String: [String]], child: Int, target: Int, zone: String
  }
  static func main() throws {
    let request = try JSONDecoder().decode(
      Request.self, from: FileHandle.standardInput.readDataToEndOfFile())
    let order = LayerOrder(nodes: request.nodes, layerParents: request.rules)
    guard let zone = LayerZone(rawValue: request.zone),
      let slot = order.slot(for: request.child, at: request.target, zone: zone)
    else { throw BenchError("Invalid layer destination.") }
    let op: [String: Any] = [
      "kind": "relocate", "child": request.child, "before": slot.before as Any? ?? NSNull(),
    ]
    FileHandle.standardOutput.write(
      try JSONSerialization.data(withJSONObject: ["parent": slot.parent, "op": op]))
  }
}
