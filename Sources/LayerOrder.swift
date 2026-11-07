import Foundation

struct ElementRow: Identifiable, Decodable {
  let id: Int, parent: Int, depth: Int, tag: String, label: String, name: String, start: Int,
    length: Int
}
enum LayerZone: String { case before, inside, after }
enum LayerStep: String, CaseIterable {
  case up = "Move up"
  case down = "Move down"
  case indent = "Nest in previous layer"
  case outdent = "Move out one level"
}
struct LayerSlot: Equatable {
  let parent: Int, before: Int?
}
struct LayerOrder {
  let nodes: [ElementRow], layerParents: [String: [String]]
  func accepts(_ tag: String, in parent: ElementRow) -> Bool {
    (layerParents[tag] ?? layerParents["*"] ?? []).contains(parent.tag)
  }
  func movableLayer(_ id: Int) -> Bool {
    guard nodes.indices.contains(id), nodes[id].parent >= 0 else { return false }
    return !(layerParents[nodes[id].tag] ?? layerParents["*"] ?? []).isEmpty
  }
  func slot(for child: Int, at target: Int, zone: LayerZone) -> LayerSlot? {
    guard movableLayer(child), nodes.indices.contains(target), child != target else {
      return nil
    }
    let row = nodes[target]
    let parent = zone == .inside ? target : row.parent
    guard nodes.indices.contains(parent), accepts(nodes[child].tag, in: nodes[parent]) else {
      return nil
    }
    var ancestor = parent
    while nodes.indices.contains(ancestor) {
      if ancestor == child { return nil }
      ancestor = nodes[ancestor].parent
    }
    let before: Int?
    switch zone {
    case .inside: before = nil
    case .before: before = target
    case .after:
      before = nodes.dropFirst(target + 1).first { $0.depth <= row.depth }.flatMap {
        $0.parent == parent ? $0.id : nil
      }
    }
    if nodes[child].parent == parent {
      let next = nodes.dropFirst(child + 1).first { $0.depth <= nodes[child].depth }
      if before == child || before == (next?.parent == parent ? next?.id : nil) { return nil }
    }
    return LayerSlot(parent: parent, before: before)
  }
  func slot(for child: Int, step: LayerStep) -> LayerSlot? {
    guard movableLayer(child) else { return nil }
    let row = nodes[child]
    if step == .outdent { return slot(for: child, at: row.parent, zone: .after) }
    let neighbor: ElementRow?
    if step == .down {
      neighbor = nodes.dropFirst(child + 1).first { $0.depth <= row.depth }
    } else {
      neighbor = nodes[..<child].last { $0.depth <= row.depth }
    }
    guard let neighbor, neighbor.parent == row.parent else { return nil }
    return slot(
      for: child, at: neighbor.id, zone: step == .indent ? .inside : step == .up ? .before : .after)
  }
}
