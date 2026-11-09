import DTHubPluginKit
import Foundation

/// The tools LoRA Advisor offers to agents (MCP clients) through DT Hub: what the tab does, without the tab. The app
/// lists them as `plugin__loraadvisor__<name>` while the plug-in is active, and sends `tool.call`. Whatever text comes back
/// (notes taken from web pages, the language model's reasons) is data for the agent, and the app marks it so.
enum LATools {
  static let maxNotes = 4000

  static let declarations: [DTHubTool] = [
    DTHubTool(
      name: "list_loras",
      description:
        "Lists the user's LoRAs. For each: the model family it belongs to, trigger word, weight (min, base = the weight it starts with, max; null = no limit), a summary (the user's notes: what the LoRA is for, trigger words, suggested weights; 'summaryIsRaw' true means raw text copied from its page, not yet summarised), the link of its page (read-only: open it to learn more, e.g. recommended settings) and whether it is already on the Generation tab. By default only those of the current model's family (the only ones usable with it); scope 'all' lists every family.",
      level: .read,
      parameters: [
        DTHubToolParameter(
          name: "scope", description: "current_family (default) or all families.", values: ["current_family", "all"]),
        DTHubToolParameter(name: "query", description: "Keep only LoRAs whose name, trigger word or notes contain this text."),
        DTHubToolParameter(name: "limit", type: "integer", description: "At most this many LoRAs (default 100, at most 300)."),
      ]),
    DTHubTool(
      name: "get_lora",
      description: "One LoRA in full: its whole summary, the link of its page, weights and limits.",
      level: .read,
      parameters: [DTHubToolParameter(name: "file", description: "The LoRA's file, as list_loras gives it.", required: true)]),
    DTHubTool(
      name: "advise",
      description:
        "Asks the local language model which LoRAs of the current family (at most three) suit a goal, each with a weight and a reason. Does not change the Generation tab: call apply_advice for that. Slow (the language model may have to load).",
      level: .read,
      parameters: [
        DTHubToolParameter(
          name: "goal", description: "What to generate or the look wanted. Default: the prompt of the Generation tab.")
      ],
      timeout: 300),
    DTHubTool(
      name: "apply_advice",
      description:
        "Puts the LoRAs of the last advice on the Generation tab with their suggested weights and trigger words (the fields turn teal in the app). Run advise first.",
      level: .edit,
      parameters: [
        DTHubToolParameter(
          name: "files", description: "Comma-separated files from the advice to apply. Default: all of them.")
      ]),
    DTHubTool(
      name: "set_notes",
      description: "Writes the notes of a LoRA (replaces them; an empty text clears them). Notes feed the advice.",
      level: .edit,
      parameters: [
        DTHubToolParameter(name: "file", description: "The LoRA's file.", required: true),
        DTHubToolParameter(name: "notes", description: "The new notes, up to \(maxNotes) characters.", required: true),
      ]),
    DTHubTool(
      name: "set_weight_limits",
      description:
        "Sets the lowest, default and highest weight the user wants for a LoRA (between -4 and 4; the ones you leave out stay as they are).",
      level: .edit,
      parameters: [
        DTHubToolParameter(name: "file", description: "The LoRA's file.", required: true),
        DTHubToolParameter(name: "min", type: "number", description: "The lowest weight."),
        DTHubToolParameter(name: "base", type: "number", description: "The weight the LoRA starts with."),
        DTHubToolParameter(name: "max", type: "number", description: "The highest weight."),
      ]),
  ]

  @MainActor
  static func handle(_ call: DTHubToolCall, state: LAState) async -> Data {
    do {
      switch call.tool {
      case "list_loras": return DTHubMessage.toolResult(try list(call, state))
      case "get_lora": return DTHubMessage.toolResult(try detail(call, state))
      case "advise": return DTHubMessage.toolResult(try await advise(call, state))
      case "apply_advice": return DTHubMessage.toolResult(try await apply(call, state))
      case "set_notes": return DTHubMessage.toolResult(try setNotes(call, state))
      case "set_weight_limits": return DTHubMessage.toolResult(try await setLimits(call, state))
      default: return DTHubMessage.bare("unsupported")
      }
    } catch let failure as Failure {
      return DTHubMessage.toolResult(failure.text, isError: true)
    } catch {
      return DTHubMessage.toolResult(error.localizedDescription, isError: true)
    }
  }

  struct Failure: Error { var text: String }

  // MARK: Tools

  @MainActor
  private static func list(_ call: DTHubToolCall, _ state: LAState) throws -> String {
    try ready(state)
    let all = call.string("scope") == "all"
    let query = fold(call.string("query") ?? "")
    let limit = min(max(Int(call.number("limit") ?? 100), 1), 300)
    let family = state.context?.family
    let matching = state.catalog.filter { lora in
      (all || lora.family == nil || lora.family == family)
        && (query.isEmpty || [lora.name, lora.trigger, state.notes(for: lora.file)].contains { fold($0).contains(query) })
    }
    let rows = matching.prefix(limit).map { row($0, state, notes: 800) }
    return try json([
      "currentFamily": null(family), "scope": all ? "all" : "current_family", "total": matching.count, "shown": rows.count,
      "loras": rows,
    ])
  }

  @MainActor
  private static func detail(_ call: DTHubToolCall, _ state: LAState) throws -> String {
    let lora = try find(call, state)
    var object = row(lora, state, notes: maxNotes)
    object["hasThumbnail"] = state.thumbnailURL(for: lora.file) != nil
    return try json(object)
  }

  @MainActor
  private static func advise(_ call: DTHubToolCall, _ state: LAState) async throws -> String {
    try ready(state)
    guard state.context?.family != nil else { throw Failure(text: "DT Hub has not said which model family is in use.") }
    guard !state.isBusy else { throw Failure(text: "The plug-in is busy with another job: try again in a moment.") }
    guard state.hasLanguageModel else {
      throw Failure(text: "No language model is assigned to plug-ins (DT Hub › Settings › LLM).")
    }
    let goal = call.string("goal")?.trimmingCharacters(in: .whitespacesAndNewlines)
    let wanted = (goal?.isEmpty == false ? goal : nil) ?? state.request
    guard !wanted.isEmpty else { throw Failure(text: "Give a goal: the Generation tab's prompt is empty.") }
    guard !state.candidates(for: wanted).isEmpty else {
      throw Failure(text: "There are no LoRAs for the current model's family.")
    }
    await state.advise(for: wanted)
    if state.suggestions.isEmpty { throw Failure(text: state.adviceMessage ?? "No LoRA suits this goal.") }
    let suggestions = state.suggestions.map { suggestion -> [String: Any] in
      let lora = state.catalog.first { $0.file == suggestion.file }
      return [
        "file": suggestion.file, "name": lora?.name ?? suggestion.file, "weight": suggestion.weight, "why": suggestion.why,
        "trigger": lora?.trigger ?? "", "onTab": state.isOnTab(suggestion.file),
      ]
    }
    return try json(["goal": wanted, "suggestions": suggestions, "next": "apply_advice puts them on the Generation tab."])
  }

  @MainActor
  private static func apply(_ call: DTHubToolCall, _ state: LAState) async throws -> String {
    guard !state.suggestions.isEmpty else { throw Failure(text: "There is no advice to apply: call advise first.") }
    var only: Set<String>?
    if let list = call.string("files"), !list.trimmingCharacters(in: .whitespaces).isEmpty {
      let files = Set(list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
      let known = Set(state.suggestions.map(\.file))
      let unknown = files.subtracting(known)
      guard unknown.isEmpty else {
        throw Failure(text: "Not in the advice: \(unknown.sorted().joined(separator: ", ")).")
      }
      only = files
    }
    let applied = state.suggestions.filter { only?.contains($0.file) ?? true }
    guard await state.addAll(only: only) else {
      throw Failure(text: state.status ?? "DT Hub did not take the LoRAs.")
    }
    return try json([
      "applied": applied.map { ["file": $0.file, "weight": $0.weight] as [String: Any] }, "result": state.status ?? "",
    ])
  }

  @MainActor
  private static func setNotes(_ call: DTHubToolCall, _ state: LAState) throws -> String {
    let lora = try find(call, state)
    guard let notes = call.string("notes") else { throw Failure(text: "Missing argument 'notes'.") }
    guard notes.count <= maxNotes else { throw Failure(text: "The notes are longer than \(maxNotes) characters.") }
    state.flushNotes()
    state.store.setNotesByUser(notes, for: lora.file)
    state.objectWillChange.send()
    return try json(["file": lora.file, "notesLength": notes.count])
  }

  @MainActor
  private static func setLimits(_ call: DTHubToolCall, _ state: LAState) async throws -> String {
    let lora = try find(call, state)
    let given = ["min", "base", "max"].compactMap { key in call.number(key).map { (key, $0) } }
    guard !given.isEmpty else { throw Failure(text: "Give at least one of min, base, max.") }
    for (key, value) in given where !LAAdvice.weightRange.contains(value) {
      throw Failure(text: "'\(key)' must be between \(Int(LAAdvice.weightRange.lowerBound)) and \(Int(LAAdvice.weightRange.upperBound)).")
    }
    let values = Dictionary(uniqueKeysWithValues: given)
    await state.setWeights(
      min: values["min"] ?? lora.minWeight, base: values["base"] ?? lora.weight, max: values["max"] ?? lora.maxWeight, for: lora.file)
    if let message = state.weightsMessage { throw Failure(text: message) }
    let now = state.catalog.first { $0.file == lora.file } ?? lora
    return try json(["file": now.file, "min": null(now.minWeight), "base": now.weight, "max": null(now.maxWeight)])
  }

  // MARK: Helpers

  @MainActor
  private static func ready(_ state: LAState) throws {
    switch state.blocker {
    case .notActive: throw Failure(text: "LoRA Advisor is not active for the job.")
    case .oldApp: throw Failure(text: "This DT Hub is too old to list the LoRAs.")
    case .noLoRAs: throw Failure(text: "The server lists no LoRAs.")
    case nil:
      if state.context == nil { throw Failure(text: "DT Hub has not sent the plug-in its context yet: try again in a moment.") }
    }
  }

  @MainActor
  private static func find(_ call: DTHubToolCall, _ state: LAState) throws -> DTHubCatalogLoRA {
    try ready(state)
    guard let file = call.string("file"), !file.isEmpty else { throw Failure(text: "Missing argument 'file'.") }
    guard let lora = state.catalog.first(where: { $0.file == file }) else {
      throw Failure(text: "No LoRA with file '\(file)': use list_loras.")
    }
    return lora
  }

  @MainActor
  private static func row(_ lora: DTHubCatalogLoRA, _ state: LAState, notes limit: Int) -> [String: Any] {
    let notes = state.notes(for: lora.file)
    return [
      "file": lora.file, "name": lora.name, "family": null(lora.family), "trigger": lora.trigger, "weight": lora.weight,
      "minWeight": null(lora.minWeight), "maxWeight": null(lora.maxWeight),
      "summary": limit >= maxNotes ? notes : oneLine(notes, limit: limit), "summaryIsRaw": state.entry(for: lora.file).rawNotes,
      "link": null(state.entry(for: lora.file).link),
      "onTab": state.isOnTab(lora.file), "canAdd": state.canAdd(lora),
    ]
  }

  private static func oneLine(_ text: String, limit: Int) -> String {
    let line = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    return line.count > limit ? String(line.prefix(limit)) + "…" : line
  }

  private static func fold(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }

  private static func null(_ value: Any?) -> Any { value ?? NSNull() }

  private static func json(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    return String(decoding: data, as: UTF8.self)
  }
}
