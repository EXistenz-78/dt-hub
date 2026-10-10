import Foundation

/// The block of actions at the end of an LLM answer: finding it, checking it and turning it into the body of a
/// `contribute` message. Pure, so it can be tested. The code that calls it decides whether a block may be used at all (the
/// command, `CommandGate`).
enum ActionBlock {
  enum Problem: Error, Equatable {
    case invalidJSON(String)
    case tooManySteps(Int)
    case empty
  }

  static let maxSteps = 20
  /// The keys of `fields` the app accepts, in the order the summary lists them.
  static let fieldKeys = [
    "prompt", "negativePrompt", "width", "height", "steps", "guidanceScale", "shift", "resolutionDependentShift",
    "cfgZeroStar", "cfgZeroInitSteps", "seed", "randomSeed", "sampler", "batchSize", "batchCount",
  ]
  private static let knownKeys = ["fields", "loras", "strength", "pipeline"]

  // MARK: Finding

  private struct Found {
    var json: String
    var range: Range<String.Index>
  }

  private static func locate(in reply: String) -> Found? {
    guard let regex = try? NSRegularExpression(pattern: "```([A-Za-z0-9_-]*)[ \\t]*\\n(.*?)```", options: [.dotMatchesLineSeparators])
    else { return nil }
    let whole = NSRange(reply.startIndex..., in: reply)
    var blocks: [(label: String, found: Found)] = []
    for match in regex.matches(in: reply, range: whole) {
      guard let all = Range(match.range, in: reply), let label = Range(match.range(at: 1), in: reply),
        let body = Range(match.range(at: 2), in: reply)
      else { continue }
      blocks.append((reply[label].lowercased(), Found(json: String(reply[body]), range: all)))
    }
    if let last = blocks.last(where: { $0.label == "dthub" }) { return last.found }
    // A small model may label the block wrongly: a json block that looks like actions will do.
    return blocks.last { block in
      guard block.label == "json", let object = object(block.found.json) else { return false }
      return knownKeys.contains { object[$0] != nil }
    }?.found
  }

  /// The JSON text of the block, or nil.
  static func find(in reply: String) -> String? { locate(in: reply)?.json }

  /// The answer without the block.
  static func strip(_ reply: String) -> String {
    guard let found = locate(in: reply) else { return reply.trimmingCharacters(in: .whitespacesAndNewlines) }
    var text = reply
    text.removeSubrange(found.range)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func object(_ json: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
  }

  // MARK: The body of `contribute`

  static func body(from json: String, italian: Bool = L.systemIsItalian) -> Result<[String: Any], Problem> {
    let parsed: Any
    do {
      parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
    } catch {
      return .failure(.invalidJSON(error.localizedDescription))
    }
    guard let root = parsed as? [String: Any] else { return .failure(.invalidJSON("not an object")) }

    // A pipeline that is too long stops everything, the fields of the same block included.
    // The steps are `{"pipeline":{"steps":[…]}}`; a small model often writes the bare list, `{"pipeline":[…]}`, which is read the same.
    var pipelineSteps: [[String: Any]] = []
    let rawSteps: [Any]? =
      (root["pipeline"] as? [String: Any])?["steps"] as? [Any] ?? root["pipeline"] as? [Any]
    if let steps = rawSteps {
      if steps.count > maxSteps { return .failure(.tooManySteps(steps.count)) }
      pipelineSteps = steps.compactMap { $0 as? [String: Any] }
    }

    var body: [String: Any] = [:]
    let fields = cleanFields(root["fields"], allowSize: true)
    if !fields.isEmpty { body["fields"] = fields }
    let loras = cleanLoRAs(root["loras"])
    if !loras.isEmpty { body["loras"] = loras }
    if let strength = number(root["strength"]) { body["strength"] = strength }
    if !pipelineSteps.isEmpty {
      var steps: [[String: Any]] = []
      for (index, raw) in pipelineSteps.enumerated() {
        var step: [String: Any] = [:]
        let title = (raw["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        step["title"] = title.isEmpty ? L.format(.pass, index + 1, italian: italian) : title
        let stepFields = cleanFields(raw["fields"], allowSize: false)
        if !stepFields.isEmpty { step["fields"] = stepFields }
        let stepLoRAs = cleanLoRAs(raw["loras"])
        if !stepLoRAs.isEmpty { step["loras"] = stepLoRAs }
        if let flag = raw["useOutputAsStart"] as? Bool { step["useOutputAsStart"] = flag }
        steps.append(step)
      }
      body["pipeline"] = ["name": L.text(.pipelineName, italian: italian), "steps": steps] as [String: Any]
    }
    return body.isEmpty ? .failure(.empty) : .success(body)
  }

  private static func number(_ value: Any?) -> Double? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
  }

  private static func cleanFields(_ value: Any?, allowSize: Bool) -> [String: Any] {
    guard let raw = value as? [String: Any] else { return [:] }
    var result: [String: Any] = [:]
    for key in fieldKeys where raw[key] != nil {
      if !allowSize, key == "width" || key == "height" { continue }
      result[key] = raw[key]
    }
    return result
  }

  private static func cleanLoRAs(_ value: Any?) -> [[String: Any]] {
    guard let list = value as? [Any] else { return [] }
    return list.compactMap { item in
      guard let entry = item as? [String: Any], let file = entry["file"] as? String, !file.isEmpty else { return nil }
      var lora: [String: Any] = ["file": file]
      if let weight = number(entry["weight"]) { lora["weight"] = weight }
      return lora
    }
  }

  // MARK: What was sent

  /// The line for the chat after a send: what went, the conflicts, the problems; an error of the app as an error.
  static func summary(of body: [String: Any], answer: [String: Any]?, italian: Bool) -> (text: String, isError: Bool) {
    guard let answer else { return (L.text(.noAnswer, italian: italian), true) }
    if answer["type"] as? String == "error" {
      return (answer["text"] as? String ?? L.text(.noAnswer, italian: italian), true)
    }
    var parts: [String] = []
    if let fields = body["fields"] as? [String: Any] {
      for key in fieldKeys where fields[key] != nil { parts.append(label(key, italian: italian)) }
    }
    if let loras = body["loras"] as? [[String: Any]] {
      parts.append("\(L.text(.fLoras, italian: italian)) (\(loras.count))")
    }
    if body["strength"] != nil { parts.append(L.text(.fStrength, italian: italian)) }
    if let pipeline = body["pipeline"] as? [String: Any], let steps = pipeline["steps"] as? [Any] {
      parts.append("\(L.text(.fPipeline, italian: italian)) (\(steps.count) \(L.text(.passesWord, italian: italian)))")
    }
    var text = L.format(.sent, parts.joined(separator: ", "), italian: italian)
    var isError = false
    if let conflicts = answer["conflicts"] as? Int, conflicts > 0 {
      text += L.format(.sentConflicts, conflicts, italian: italian)
    }
    if let problems = answer["problems"] as? [String], !problems.isEmpty {
      text += L.format(.sentProblems, problems.joined(separator: " "), italian: italian)
      isError = true
    }
    return (text, isError)
  }

  private static func label(_ key: String, italian: Bool) -> String {
    let word: L.Key =
      switch key {
      case "prompt": .fPrompt
      case "negativePrompt": .fNegative
      case "width": .fWidth
      case "height": .fHeight
      case "steps": .fSteps
      case "guidanceScale": .fGuidance
      case "shift": .fShift
      case "resolutionDependentShift": .fAutoShift
      case "cfgZeroStar": .fCfgZero
      case "cfgZeroInitSteps": .fCfgZeroSteps
      case "seed": .fSeed
      case "randomSeed": .fRandomSeed
      case "sampler": .fSampler
      case "batchSize": .fBatchSize
      default: .fBatchCount
      }
    return L.text(word, italian: italian)
  }
}
