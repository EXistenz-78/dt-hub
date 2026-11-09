import Foundation
import MCP

/// Turns the picture an agent names (a result of this session, or a file) into something the app can take (spec §7, §6).
@MainActor
enum ResultCatalog {
  /// `args` carries either `result_id` or `path`; `weight` is read when present.
  static func image(from args: [String: Value], in ctx: ToolContext) throws -> AgentImage {
    let weight = args.double("weight")
    if let id = args.string("result_id") {
      guard ctx.host.results().contains(where: { $0.id == id }) else {
        throw ToolFailure("Unknown result '\(id)'. Call list_results for the pictures DT Hub has.")
      }
      return AgentImage(.result(id: id), weight: weight)
    }
    if let path = args.string("path") {
      guard let url = ctx.paths().resolve(path) else {
        throw ToolFailure("The path '\(path)' is not allowed: only pictures inside the project, output and Results folders (or folders the user allowed) can be used.")
      }
      return AgentImage(.path(url.path), weight: weight)
    }
    throw ToolFailure("Give either 'result_id' or 'path'.")
  }
}
