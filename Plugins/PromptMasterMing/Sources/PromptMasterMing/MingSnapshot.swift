import Foundation

/// Il lavoro prima dell'ultima scrittura dell'LLM, composizione o importazione, per «Annulla» (solo l'ultima).
struct MingSnapshot: Codable, Equatable, Sendable {
  var idea: String
  var selection: Set<String>
  var imageStyle: String
  var ambientLighting: String
  var layers: [MingLayer]
  var nextLayerID: Int
}

extension MingSnapshot {
  static func take(from document: MingDocument) -> MingSnapshot {
    MingSnapshot(
      idea: document.idea, selection: document.selection, imageStyle: document.imageStyle,
      ambientLighting: document.ambientLighting, layers: document.layers, nextLayerID: document.nextLayerID)
  }

  /// Rimette tutto com'era e spegne Annulla.
  func restore(into document: inout MingDocument) {
    document.idea = idea
    document.selection = selection
    document.imageStyle = imageStyle
    document.ambientLighting = ambientLighting
    document.layers = layers
    document.nextLayerID = nextLayerID
    document.snapshot = nil
  }

  /// I testi in Markdown, leggibili a mano (`llm/before.md`).
  var markdown: String {
    var text = "## idea\n\(idea)\n\n## image_style\n\(imageStyle)\n\n## ambient_lighting\n\(ambientLighting)"
    for (index, layer) in layers.enumerated() {
      text += "\n\n## layer \(index + 1) (\(layer.kind.rawValue))\n\(layer.description)"
      if layer.kind == .text { text += "\ntext: \(layer.text)" }
      if !layer.relation.isEmpty { text += "\n\n## relation \(index + 1)\n\(layer.relation)" }
    }
    return text + "\n"
  }
}
