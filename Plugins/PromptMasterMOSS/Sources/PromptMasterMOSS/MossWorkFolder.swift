import Foundation

/// La cartella di lavoro dell'LLM (spec §10): `llm/` accanto a `state.json`. Ogni scrittura sostituisce i tre file.
struct MossWorkFolder {
  let folder: URL

  var directory: URL { folder.appendingPathComponent("llm", isDirectory: true) }

  func write(request: String, answer: String, before: MossSnapshot?) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? request.write(to: directory.appendingPathComponent("request.md"), atomically: true, encoding: .utf8)
    try? answer.write(to: directory.appendingPathComponent("answer.md"), atomically: true, encoding: .utf8)
    if let before { try? before.markdown.write(to: directory.appendingPathComponent("before.md"), atomically: true, encoding: .utf8) }
  }
}
