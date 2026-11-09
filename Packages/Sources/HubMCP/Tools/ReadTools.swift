import Foundation
import MCP

/// The tools that only read (spec §4): always listed.
enum ReadTools {
  struct Budget: Encodable {
    var usedImages: Int
    var imageLimit: Int
    var usedComputeUnits: Int
    var computeUnitLimit: Int?
    var sessionAuthorised: Bool
  }

  struct Envelope: Encodable {
    var state: AgentState
    var mode: String
    var budget: Budget
    var activeJob: JobStatus?
  }

  struct AdvancedView: Encodable {
    var values: [String: AgentValue]
    var appliesToCurrentModel: [String]
  }

  static var specs: [ToolSpec] {
    [
      ToolSpec(
        name: "get_app_state",
        description:
          "Read first. The Generation tab (model, prompt, parameters, LoRAs, Moodboard, start image), the access mode, the session budget and the running job.",
        level: .read
      ) { ctx, _ in
        let settings = ctx.settings()
        return [
          jsonText(
            Envelope(
              state: ctx.host.state(), mode: settings.mode.rawValue,
              budget: Budget(
                usedImages: ctx.ledger.usedImages, imageLimit: settings.imageBudget, usedComputeUnits: ctx.ledger.usedCU,
                computeUnitLimit: settings.cuBudget, sessionAuthorised: ctx.ledger.isConfirmed),
              activeJob: ctx.jobs.activeJobID.flatMap { ctx.jobs.status($0) }))
        ]
      },
      ToolSpec(name: "list_models", description: "The image models installed in Draw Things, with family and kind.", level: .read) {
        ctx, _ in [jsonText(ctx.host.models())]
      },
      ToolSpec(name: "list_loras", description: "The LoRA catalogue, with the model families each one suits.", level: .read) {
        ctx, _ in [jsonText(ctx.host.loras())]
      },
      ToolSpec(name: "list_presets", description: "The names of the saved presets.", level: .read) { ctx, _ in
        [jsonText(ctx.host.presetNames())]
      },
      ToolSpec(name: "list_pipelines", description: "The names of the saved pipelines.", level: .read) { ctx, _ in
        [jsonText(ctx.host.pipelineNames())]
      },
      ToolSpec(
        name: "get_prompt_guide",
        description:
          "How to write prompts for a model family: the family's rules, whether it uses a negative prompt, word limits. Use it to write prompts yourself.",
        schema: ToolSpec.schema([("family", "string", "The family key, as in get_app_state or list_models.")], required: ["family"]),
        level: .read
      ) { ctx, args in
        let family = try args.requiredString("family")
        guard let guide = ctx.host.promptGuide(family: family) else {
          throw ToolFailure("No prompt guide for family '\(family)'.")
        }
        return [.text(guide)]
      },
      ToolSpec(
        name: "list_results", description: "The most recent results of this project, newest first.",
        schema: ToolSpec.schema([("limit", "integer", "How many (default 20, at most 100).")]), level: .read
      ) { ctx, args in
        let limit = min(max(args.int("limit") ?? 20, 1), 100)
        return [jsonText(Array(ctx.host.results().prefix(limit)))]
      },
      ToolSpec(
        name: "get_results", description: "The results a job made.",
        schema: ToolSpec.schema([("job_id", "string", "The job_id a run returned.")], required: ["job_id"]), level: .read
      ) { ctx, args in
        let id = try args.requiredString("job_id")
        guard let job = ctx.jobs.status(id) else { throw ToolFailure("Unknown job '\(id)'.") }
        let wanted = Set(job.resultIDs)
        return [jsonText(ctx.host.results().filter { wanted.contains($0.id) })]
      },
      ToolSpec(
        name: "get_image",
        description: "A result as a picture, scaled down, so you can look at it and judge it.",
        schema: ToolSpec.schema(
          [("result_id", "string", "A result id from list_results or get_results."),
            ("max_side", "integer", "Longer side in pixels (default 768, 64 to 2048).")], required: ["result_id"]),
        level: .read
      ) { ctx, args in
        let id = try args.requiredString("result_id")
        let side = min(max(args.int("max_side") ?? 768, 64), 2048)
        guard let data = ctx.host.resultImage(id: id, maxSide: side) else {
          throw ToolFailure("Unknown result '\(id)'. Results ids are valid only for the pictures DT Hub still has; call list_results.")
        }
        return [.image(data, mimeType: "image/png")]
      },
      ToolSpec(name: "get_queue", description: "The entries of the queue and their status.", level: .read) { ctx, _ in
        [jsonText(ctx.host.queueEntries())]
      },
      ToolSpec(
        name: "get_job", description: "The state and progress of a job.",
        schema: ToolSpec.schema([("job_id", "string", "The job_id a run returned.")], required: ["job_id"]), level: .read
      ) { ctx, args in
        let id = try args.requiredString("job_id")
        guard let job = ctx.jobs.status(id) else { throw ToolFailure("Unknown job '\(id)'.") }
        return [jsonText(job)]
      },
      ToolSpec(
        name: "wait_for_job",
        description:
          "Waits until the job ends or the timeout passes, then returns its state (default 30 s: clients time out on longer waits). If it is still running, call it again; a long generation can take minutes.",
        schema: ToolSpec.schema(
          [("job_id", "string", "The job_id a run returned."), ("timeout_seconds", "integer", "Wait up to this long (default 30, at most 300).")],
          required: ["job_id"]),
        level: .read
      ) { ctx, args in
        let id = try args.requiredString("job_id")
        guard let job = await ctx.jobs.wait(id, timeoutSeconds: args.int("timeout_seconds") ?? JobTracker.defaultWaitSeconds) else {
          throw ToolFailure("Unknown job '\(id)'.")
        }
        return [jsonText(job)]
      },
      ToolSpec(
        name: "get_server_status",
        description:
          "Which image server DT Hub uses (managed = the CLI server DT Hub starts, attach = the Draw Things app), whether it answers, and whether switch_server can move to the other one.",
        level: .read
      ) { ctx, _ in [jsonText(ctx.host.serverStatus())] },
      ToolSpec(
        name: "get_advanced",
        description:
          "The values of the Advanced cards (refiner, hires fix, upscaler, guidance, text encoders, SDXL conditioning, tiled decoding and diffusion, TeaCache, output), and which groups apply to the current model. Change them with set_advanced.",
        level: .read
      ) { ctx, _ in [jsonText(AdvancedView(values: ctx.host.advancedValues(), appliesToCurrentModel: ctx.host.advancedApplicable()))] },
      ToolSpec(name: "list_projects", description: "The projects, and which one is open. Results, Control and the queue belong to the open project.", level: .read) {
        ctx, _ in [jsonText(ctx.host.projects())]
      },
      ToolSpec(
        name: "list_plugins", description: "The plug-ins installed in DT Hub, whether they are active, and why one is unavailable for the current model.",
        level: .read
      ) { ctx, _ in [jsonText(ctx.host.plugins())] },
    ]
  }
}
