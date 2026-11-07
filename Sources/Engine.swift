import Foundation
import JavaScriptCore

struct IndexedPage: Decodable { let html: String, error: String, nodes: [ElementRow] }
struct ScriptRange: Decodable { let src: String, start: Int, end: Int, javascript: Bool }
struct EditResult: Decodable {
  let text: String
  let focus: Int
  let range: [Int]?
  let css: String?
}
struct RuleInfo: Decodable {
  let selector: String, source: String, styleIndex: Int, path: [Int], media: String, value: String,
    priority: String, count: Int, examples: String
}
struct ClassInfo: Decodable { let name: String, count: Int, examples: String }
struct Inspection: Decodable {
  let id: Int, label: String, prop: String, text: String, classes: [ClassInfo], rules: [RuleInfo],
    winner: Int, limited: Bool, computed: String
  let textEditable: Bool
  let sheets: [String]
  let canResize: Bool, canStack: Bool, canLift: Bool, width: Double, height: Double, stack: Int,
    frontLevel: Int, backLevel: Int
  let position: String?
  let photoURL: String?, responsivePhoto: Bool?
  let hasImage: Bool?
  let fontFamily: String?
  let fill: String, ink: String, fontSize: String, align: String
  let canMove: Bool, x: Double, y: Double, display: String, attributes: [String: String]
}
enum Resources {
  static func string(_ name: String, _ ext: String, in directory: String? = nil) throws -> String {
    guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: directory) else {
      throw BenchError("Missing bundled resource: " + name + "." + ext)
    }
    return try String(contentsOf: url, encoding: .utf8)
  }
}
final class Engine {
  private let context = JSContext()!
  private let api: JSValue
  init() throws {
    context.evaluateScript(try Resources.string("source", "js"))
    context.evaluateScript(try Resources.string("workflows", "js"))
    guard let api = context.evaluateScript("WebBench"), !api.isUndefined else {
      throw BenchError("Source engine failed to load.")
    }
    self.api = api
  }
  func call<T: Decodable>(_ method: String, _ args: [Any], as type: T.Type) throws -> T {
    context.exception = nil
    let result = api.invokeMethod(method, withArguments: args)
    if let error = context.exception {
      throw BenchError(error.toString() ?? "Source mapping failed.")
    }
    guard let result else { throw BenchError("No source result.") }
    if T.self == String.self, let text = result.toString() as? T { return text }
    guard let object = result.toObject(), JSONSerialization.isValidJSONObject(object) else {
      throw BenchError("Invalid source mapping result.")
    }
    return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
  }
}
