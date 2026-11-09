import Foundation
import MCP

/// The tools that change the Generation tab (spec §4): listed from the "Modify the tab" mode up.
enum EditTools {
  enum FieldType { case string, int, double, bool }

  /// The fields `set_fields` accepts, with the type each one takes (the keys of the AI Assistant plug-in's action block).
  static let fieldTypes: [String: FieldType] = [
    "prompt": .string, "negativePrompt": .string, "width": .int, "height": .int, "steps": .int,
    "guidanceScale": .double, "shift": .double, "resolutionDependentShift": .bool, "cfgZeroStar": .bool,
    "cfgZeroInitSteps": .int, "highRes": .bool, "seed": .int, "randomSeed": .bool, "sampler": .string, "batchSize": .int, "batchCount": .int,
  ]

  static func convert(_ key: String, _ value: Value, as type: FieldType) throws -> AgentValue {
    switch (type, value) {
    case (.string, .string(let v)): return .string(v)
    case (.int, .int(let v)): return .int(v)
    case (.double, .double(let v)): return .double(v)
    case (.double, .int(let v)): return .double(Double(v))
    case (.bool, .bool(let v)): return .bool(v)
    default: throw ToolFailure("Field '\(key)' expects a \(type).")
    }
  }

  static var specs: [ToolSpec] {
    [
      ToolSpec(
        name: "set_fields",
        description:
          "Sets fields of the Generation tab. Fields: " + fieldTypes.keys.sorted().joined(separator: ", ")
          + ". Changed fields show in teal in the app.",
        schema: .object([
          "type": .string("object"),
          "properties": .object([
            "fields": .object(["type": .string("object"), "description": .string("Field name to value.")])
          ]), "required": .array([.string("fields")]),
        ]), level: .edit
      ) { ctx, args in
        guard case .object(let given)? = args["fields"], !given.isEmpty else { throw ToolFailure("Give a non-empty 'fields' object.") }
        var converted: [String: AgentValue] = [:]
        for (key, value) in given {
          guard let type = fieldTypes[key] else {
            throw ToolFailure("Unknown field '\(key)'. Valid fields: \(fieldTypes.keys.sorted().joined(separator: ", ")).")
          }
          converted[key] = try convert(key, value, as: type)
        }
        let applied = try ctx.host.setFields(converted)
        let skipped = converted.keys.filter { !applied.contains($0) }.sorted()
        var text = "Applied: \(applied.joined(separator: ", "))."
        if !skipped.isEmpty {
          text += " Not applied: \(skipped.joined(separator: ", ")) (a plug-in holds them; the user must decide in DT Hub)."
        }
        return [.text(text)]
      },
      ToolSpec(
        name: "add_lora", description: "Adds a LoRA to the tab (or sets the weight of one already there).",
        schema: ToolSpec.schema([("file", "string", "The LoRA file from list_loras."), ("weight", "number", "-4 to 4, default 1.")], required: ["file"]),
        level: .edit
      ) { ctx, args in
        let file = try args.requiredString("file")
        let weight = try loraWeight(args, default: 1.0)
        try ctx.host.addLoRA(file: file, weight: weight)
        return [.text("LoRA \(file) at weight \(weight).")]
      },
      ToolSpec(
        name: "set_lora_weight", description: "Changes the weight of a LoRA already on the tab.",
        schema: ToolSpec.schema([("file", "string", "The LoRA file."), ("weight", "number", "-4 to 4.")], required: ["file", "weight"]),
        level: .edit
      ) { ctx, args in
        let file = try args.requiredString("file")
        let weight = try loraWeight(args, default: nil)
        try ctx.host.setLoRAWeight(file: file, weight: weight)
        return [.text("LoRA \(file) now at weight \(weight).")]
      },
      ToolSpec(
        name: "remove_lora", description: "Takes a LoRA off the tab.",
        schema: ToolSpec.schema([("file", "string", "The LoRA file.")], required: ["file"]), level: .edit
      ) { ctx, args in
        try ctx.host.removeLoRA(file: try args.requiredString("file"))
        return [.text("Removed.")]
      },
      ToolSpec(
        name: "set_moodboard",
        description:
          "Adds pictures to the Moodboard, or replaces the whole Moodboard (replace: true). Each item gives a result_id (a picture DT Hub made) or a path (inside allowed folders). All Moodboard pictures use the same weight in this version; a weight, if given, is ignored.",
        schema: .object([
          "type": .string("object"),
          "properties": .object([
            "images": .object(["type": .string("array"), "items": .object(["type": .string("object")]),
              "description": .string("Items with result_id or path, and weight.")]),
            "replace": .object(["type": .string("boolean"), "description": .string("Replace the current Moodboard (default false).")]),
          ]), "required": .array([.string("images")]),
        ]), level: .edit
      ) { ctx, args in
        guard case .array(let items)? = args["images"], !items.isEmpty else { throw ToolFailure("Give a non-empty 'images' array.") }
        var images: [AgentImage] = []
        for item in items {
          guard case .object(let fields) = item else { throw ToolFailure("Each image must be an object with result_id or path.") }
          images.append(try ResultCatalog.image(from: fields, in: ctx))
        }
        let replace = args.bool("replace") ?? false
        let replaced = try await ctx.host.setMoodboard(images, replace: replace)
        if replace && replaced > 0 { return [.text("Replaced \(replaced) existing Moodboard picture(s) with \(images.count).")] }
        return [.text("Added \(images.count) picture(s) to the Moodboard.")]
      },
      ToolSpec(
        name: "set_start_image", description: "Sets the start image (image-to-image) from a result_id or an allowed path.",
        schema: ToolSpec.schema([("result_id", "string", "A result from list_results."), ("path", "string", "An allowed picture file.")]),
        level: .edit
      ) { ctx, args in
        try await ctx.host.setStartImage(try ResultCatalog.image(from: args, in: ctx))
        return [.text("Start image set.")]
      },
      ToolSpec(
        name: "set_incremental",
        description:
          "Turns incremental mode on or off. On, the result of each run becomes the start image of the next one (see get_app_state).",
        schema: ToolSpec.schema([("enabled", "boolean", "true or false.")], required: ["enabled"]), level: .edit
      ) { ctx, args in
        guard let on = args.bool("enabled") else { throw ToolFailure("Give 'enabled': true or false.") }
        ctx.host.setIncremental(on)
        return [.text("Incremental mode \(on ? "on" : "off").")]
      },
      ToolSpec(
        name: "set_advanced",
        description:
          "Changes Advanced values by name, with the type get_advanced shows (numbers, true/false, text). Use get_advanced first: only the groups it lists as applying to the model have an effect.",
        schema: .object([
          "type": .string("object"),
          "properties": .object(["values": .object(["type": .string("object"), "description": .string("Name to value, as in get_advanced.")])]),
          "required": .array([.string("values")]),
        ]), level: .edit
      ) { ctx, args in
        guard case .object(let given)? = args["values"], !given.isEmpty else { throw ToolFailure("Give a non-empty 'values' object.") }
        var converted: [String: AgentValue] = [:]
        for (key, value) in given {
          switch value {
          case .string(let v): converted[key] = .string(v)
          case .int(let v): converted[key] = .int(v)
          case .double(let v): converted[key] = .double(v)
          case .bool(let v): converted[key] = .bool(v)
          default: throw ToolFailure("Value of '\(key)' must be a number, true/false or text.")
          }
        }
        let applied = try ctx.host.setAdvanced(converted)
        return [.text("Applied: \(applied.joined(separator: ", ")).")]
      },
      ToolSpec(
        name: "clear_moodboard", description: "Takes every picture off the Moodboard. Use it to undo set_moodboard.", level: .edit
      ) { ctx, _ in
        let count = try ctx.host.clearMoodboard()
        return [.text("Removed \(count) picture(s) from the Moodboard.")]
      },
      ToolSpec(
        name: "clear_start_image", description: "Takes the start image off (back to text-to-image). Use it to undo set_start_image.", level: .edit
      ) { ctx, _ in
        try ctx.host.clearStartImage()
        return [.text("Start image removed.")]
      },
      ToolSpec(
        name: "clear_pipeline",
        description: "Deselects the pipeline in the app, so that run generates with the tab again.", level: .edit
      ) { ctx, _ in
        try ctx.host.clearPipeline()
        return [.text("Pipeline deselected.")]
      },
      ToolSpec(
        name: "select_pipeline",
        description: "Selects a saved pipeline (see list_pipelines) in the app. Then run_pipeline runs it; clear_pipeline deselects it.",
        schema: ToolSpec.schema([("name", "string", "A name from list_pipelines.")], required: ["name"]), level: .edit
      ) { ctx, args in
        let name = try args.requiredString("name")
        try ctx.host.selectPipeline(named: name)
        return [.text("Pipeline '\(name)' selected.")]
      },
      ToolSpec(
        name: "recall_from_result",
        description:
          "Puts back into the tab the prompt (and negative prompt) and/or the model and parameters (seed, steps, size, LoRAs) that made a result of this session. Use it to refine or repeat a picture.",
        schema: ToolSpec.schema([
          ("result_id", "string", "A result from list_results."),
          ("prompt", "boolean", "Recall the prompts (default true)."),
          ("parameters", "boolean", "Recall the model and parameters (default true)."),
        ], required: ["result_id"]), level: .edit
      ) { ctx, args in
        let id = try args.requiredString("result_id")
        let prompt = args.bool("prompt") ?? true
        let parameters = args.bool("parameters") ?? true
        guard prompt || parameters else { throw ToolFailure("Nothing to recall: 'prompt' and 'parameters' are both false.") }
        try ctx.host.recallResult(id: id, prompt: prompt, parameters: parameters)
        let what = [prompt ? "prompt" : nil, parameters ? "model and parameters" : nil].compactMap { $0 }.joined(separator: " and ")
        return [.text("Recalled the \(what) of result \(id).")]
      },
      ToolSpec(
        name: "set_strength", description: "How strongly the start image is changed, 0 to 1.",
        schema: ToolSpec.schema([("value", "number", "0 to 1.")], required: ["value"]), level: .edit
      ) { ctx, args in
        guard let value = args.double("value"), (0...1).contains(value) else { throw ToolFailure("'value' must be a number from 0 to 1.") }
        try ctx.host.setStrength(value)
        return [.text("Strength \(value).")]
      },
      ToolSpec(
        name: "load_preset", description: "Loads a saved preset into the tab (parameters, and its model when it names one).",
        schema: ToolSpec.schema([("name", "string", "A name from list_presets.")], required: ["name"]), level: .edit
      ) { ctx, args in
        let name = try args.requiredString("name")
        if let reason = ctx.host.loadPreset(named: name) { throw ToolFailure(reason) }
        return [.text("Preset '\(name)' loaded.")]
      },
      ToolSpec(
        name: "save_preset", description: "Saves the tab as a new preset. It never overwrites an existing preset.",
        schema: ToolSpec.schema([("name", "string", "A new name.")], required: ["name"]), level: .edit
      ) { ctx, args in
        let name = try args.requiredString("name")
        // The preset store trims names and ignores case and accents: so does this check.
        func key(_ text: String) -> String {
          text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        if ctx.host.presetNames().contains(where: { key($0) == key(name) }) {
          throw ToolFailure("A preset named '\(name)' already exists; choose another name.")
        }
        try ctx.host.savePreset(named: name)
        return [.text("Preset '\(name)' saved.")]
      },
    ]
  }

  static func loraWeight(_ args: [String: Value], default fallback: Double?) throws -> Double {
    guard let weight = args.double("weight") ?? fallback else { throw ToolFailure("Missing argument 'weight'.") }
    guard (-4.0...4.0).contains(weight) else { throw ToolFailure("'weight' must be between -4 and 4.") }
    return weight
  }
}
