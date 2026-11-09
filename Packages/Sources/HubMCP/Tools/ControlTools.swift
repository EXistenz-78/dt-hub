import Foundation
import MCP

/// The tools that start work or change the model (spec §4): listed only in "Full control" mode.
enum ControlTools {
  struct Started: Encodable {
    var job_id: String
    var images: Int
    var note = "Call wait_for_job with this job_id until it ends."
  }

  /// The one path every generation takes (spec §6, §7): take the single slot, ask the gate, reserve the budget, start.
  /// The slot is taken first so a second call cannot slip in while the first waits for a confirmation.
  @MainActor
  static func startJob(
    _ ctx: ToolContext, kind: JobKind, plan: AgentRunPlan, start: () throws(AgentError) -> Void
  ) async throws -> [ToolOutput] {
    let id = try ctx.jobs.begin(kind: kind, images: plan.images)
    // Do not ask the user about something that cannot start (a generation the user began by hand).
    if ctx.host.state().isGenerating {
      ctx.jobs.abort(id, reason: "A generation is already running.")
      throw AgentError.busy(jobID: nil)
    }
    let summary = plan.summary.isEmpty ? "\(plan.images) image(s)" : plan.summary
    if case .denied(let reason) = await ctx.gate.authorize(plan, summary: summary) {
      ctx.jobs.abort(id, reason: reason)
      throw ToolFailure(reason)
    }
    // The user may have stopped the agent while the question was open.
    guard ctx.jobs.acceptsNewJobs else {
      let reason = "The agent was stopped or disconnected while waiting for confirmation."
      ctx.jobs.abort(id, reason: reason)
      throw ToolFailure(reason)
    }
    if case .exhausted(let used, let limit, _) = ctx.ledger.reserve(images: plan.images, cu: plan.estimatedCU) {
      let reason = "Budget exhausted: \(used) of \(limit) used. Ask the user to raise the budget in DT Hub › Remote control."
      ctx.jobs.abort(id, reason: reason)
      throw ToolFailure(reason)
    }
    do {
      try start()
    } catch {
      ctx.ledger.refund(images: plan.images, cu: plan.estimatedCU)
      ctx.jobs.abort(id, reason: error.message)
      throw error
    }
    return [jsonText(Started(job_id: id, images: plan.images))]
  }

  @MainActor
  static func requireNoActiveJob(_ ctx: ToolContext) throws {
    if let active = ctx.jobs.activeJobID { throw AgentError.busy(jobID: active) }
    if ctx.host.state().isGenerating { throw AgentError.busy(jobID: nil) }
  }

  /// Switching server or project cannot happen under a running job: say how to proceed.
  @MainActor
  static func requireIdle(_ ctx: ToolContext, for action: String) throws {
    if ctx.jobs.activeJobID != nil || ctx.host.state().isGenerating {
      let which = ctx.jobs.activeJobID.map { " (\($0))" } ?? ""
      throw ToolFailure("A job is running\(which): wait for it, or call stop, before \(action).")
    }
  }

  static var specs: [ToolSpec] {
    [
      ToolSpec(
        name: "open_project",
        description:
          "Opens another project (see list_projects). Results, Control and the queue change with it. Refused while a job runs.",
        schema: ToolSpec.schema([("name", "string", "A project name from list_projects.")], required: ["name"]), level: .control
      ) { ctx, args in
        let name = try args.requiredString("name")
        try requireIdle(ctx, for: "changing project")
        try await ctx.host.openProject(name: name)
        ctx.agentQueueEntries.removeAll()
        ctx.onHostChanged?()
        return [.text("Project '\(name)' is open.")]
      },
      ToolSpec(
        name: "create_project",
        description: "Makes a new project and opens it. Refused while a job runs.",
        schema: ToolSpec.schema([("name", "string", "The new project's name.")], required: ["name"]), level: .control
      ) { ctx, args in
        let name = try args.requiredString("name")
        try requireIdle(ctx, for: "creating a project")
        try await ctx.host.createProject(name: name)
        ctx.agentQueueEntries.removeAll()
        ctx.onHostChanged?()
        return [.text("Project '\(name)' created and open.")]
      },
      ToolSpec(
        name: "set_model", description: "Chooses the image model (a file from list_models). Refused while a job runs.",
        schema: ToolSpec.schema([("file", "string", "The model file from list_models.")], required: ["file"]), level: .control
      ) { ctx, args in
        let file = try args.requiredString("file")
        try requireNoActiveJob(ctx)
        guard ctx.host.models().contains(where: { $0.file == file }) else {
          throw ToolFailure("Unknown model '\(file)'. Use a file from list_models.")
        }
        try ctx.host.setModel(file: file)
        ctx.onHostChanged?()
        // LoRAs stay on the tab when the model changes; one made for another family does not suit the new model.
        var text = "Model set to \(file)."
        if let family = ctx.host.currentFamily {
          let catalog = Dictionary(ctx.host.loras().map { ($0.file, $0.families) }, uniquingKeysWith: { first, _ in first })
          let misfits = ctx.host.state().loras.map(\.file).filter { file in
            guard let families = catalog[file], !families.isEmpty else { return false }
            return !families.contains(family)
          }
          if !misfits.isEmpty {
            text += " Warning: these LoRAs on the tab are for another family than \(family): \(misfits.joined(separator: ", ")). Remove them with remove_lora."
          }
        }
        return [.text(text)]
      },
      ToolSpec(
        name: "switch_server",
        description:
          "Switches DT Hub to the other image server (the CLI server DT Hub starts, or the Draw Things app) and waits until it answers. Use it when the current server stops answering. Refused while a job runs: stop it first.",
        level: .control
      ) { ctx, _ in
        try requireIdle(ctx, for: "switching server")
        let status = try await ctx.host.switchServer()
        ctx.onHostChanged?()
        return [jsonText(status)]
      },
      ToolSpec(
        name: "run",
        description:
          "Generates with the tab as it is now (refused while a pipeline is selected: use run_pipeline or clear_pipeline). Returns a job_id at once; follow it with wait_for_job. One job at a time; counts against the session budget.",
        level: .control
      ) { ctx, _ in
        if let pipeline = ctx.host.state().selectedPipeline {
          throw ToolFailure(
            "The pipeline '\(pipeline)' is selected in the app and a plain run would execute it. Use run_pipeline to run a saved pipeline, the tool of the plug-in that prepared it (e.g. plugin__tiledupscale__upscale with no arguments), or clear_pipeline to generate with the tab.")
        }
        return try await startJob(ctx, kind: .run, plan: ctx.host.planRun()) { () throws(AgentError) in try ctx.host.startRun() }
      },
      ToolSpec(name: "stop", description: "Stops the running generation.", level: .control) { ctx, _ in
        ctx.host.stop()
        if ctx.jobs.activeJobID != nil { ctx.jobs.apply(.stopped) }
        return [.text("Stopped.")]
      },
      ToolSpec(
        name: "run_pipeline", description: "Runs a saved pipeline (list_pipelines) or one made with define_pipeline. Returns a job_id.",
        schema: ToolSpec.schema([("name", "string", "The pipeline name.")], required: ["name"]), level: .control
      ) { ctx, args in
        let name = try args.requiredString("name")
        let plan = try ctx.host.planPipeline(named: name)
        return try await startJob(ctx, kind: .pipeline, plan: plan) { () throws(AgentError) in try ctx.host.startPipeline(named: name) }
      },
      ToolSpec(
        name: "define_pipeline",
        description:
          "Makes a temporary pipeline of up to 20 steps; each step may set prompt, negativePrompt and fields (as in set_fields). Returns its name for run_pipeline.",
        schema: .object([
          "type": .string("object"),
          "properties": .object(["steps": .object(["type": .string("array"), "items": .object(["type": .string("object")])])]),
          "required": .array([.string("steps")]),
        ]), level: .control
      ) { ctx, args in
        guard case .array(let items)? = args["steps"], !items.isEmpty else { throw ToolFailure("Give a non-empty 'steps' array.") }
        guard items.count <= 20 else { throw ToolFailure("A pipeline has at most 20 steps; you gave \(items.count).") }
        var steps: [AgentPipelineStep] = []
        for item in items {
          guard case .object(let object) = item else { throw ToolFailure("Each step must be an object.") }
          var fields: [String: AgentValue] = [:]
          if case .object(let given)? = object["fields"] {
            for (key, value) in given {
              guard let type = EditTools.fieldTypes[key] else { throw ToolFailure("Unknown field '\(key)' in a step.") }
              fields[key] = try EditTools.convert(key, value, as: type)
            }
          }
          steps.append(AgentPipelineStep(prompt: object.string("prompt"), negativePrompt: object.string("negativePrompt"), fields: fields))
        }
        return [.text(try ctx.host.definePipeline(steps: steps))]
      },
      ToolSpec(
        name: "queue_add",
        description: "Adds the tab as it is now to the queue. Returns the entry id. Refused while the queue is running (the running queue would take the entry without the budget being charged).",
        level: .control
      ) { ctx, _ in
        if let active = ctx.jobs.activeJobID, ctx.jobs.status(active)?.kind == .queue { throw AgentError.busy(jobID: active) }
        let id = try await ctx.host.queueAdd()
        ctx.agentQueueEntries.insert(id)
        return [.text(id.uuidString)]
      },
      ToolSpec(
        name: "queue_start", description: "Runs the queue. Returns a job_id; counts every pending entry against the session budget.",
        level: .control
      ) { ctx, _ in
        try await startJob(ctx, kind: .queue, plan: ctx.host.planQueue()) { () throws(AgentError) in try ctx.host.startQueue() }
      },
      ToolSpec(name: "queue_stop", description: "Stops the queue.", level: .control) { ctx, _ in
        ctx.host.stopQueue()
        if let id = ctx.jobs.activeJobID, ctx.jobs.status(id)?.kind == .queue { ctx.jobs.apply(.stopped) }
        return [.text("Queue stopped.")]
      },
      ToolSpec(
        name: "queue_remove", description: "Removes a queue entry that you added in this session.",
        schema: ToolSpec.schema([("id", "string", "The entry id queue_add returned.")], required: ["id"]), level: .control
      ) { ctx, args in
        guard let id = UUID(uuidString: try args.requiredString("id")) else { throw ToolFailure("'id' is not a valid entry id.") }
        guard ctx.agentQueueEntries.contains(id) else {
          throw ToolFailure("You can remove only queue entries you added in this session.")
        }
        try ctx.host.queueRemove(id: id)
        ctx.agentQueueEntries.remove(id)
        return [.text("Removed.")]
      },
      ToolSpec(
        name: "enhance_prompt",
        description: "Improves the prompt with the specialist language model of this model's family (it runs locally).",
        level: .control, requiresSpecialist: true
      ) { ctx, _ in [.text(try await ctx.host.enhancePrompt())] },
      ToolSpec(
        name: "prompt_from_image",
        description: "Writes a prompt from the start image with the specialist language model of this model's family.",
        level: .control, requiresSpecialist: true
      ) { ctx, _ in [.text(try await ctx.host.promptFromImage())] },
    ]
  }
}
