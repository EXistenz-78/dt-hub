import Foundation
import HubKit
import Observation

/// Enhance Prompt and Generate Prompt: asks the language model and returns the new prompt (and negative prompt).
/// The caller writes the result into its fields; the assistant knows nothing about them. One operation at a time.
@MainActor
@Observable
public final class PromptAssistant {
  public enum Kind: Equatable, Sendable { case enhance, describe }
  public enum Failure: Equatable, Sendable {
    case emptyPrompt, noImage, emptyAnswer
    case model(LanguageModelError)
  }

  /// The LLM chosen for an operation and what its folder says about it.
  public struct Choice: Sendable {
    public let model: LanguageModelDescriptor
    public let profile: LanguageModelProfile

    public init(model: LanguageModelDescriptor, profile: LanguageModelProfile) {
      self.model = model
      self.profile = profile
    }
  }

  /// Something worth saying about an operation that did work.
  public enum Note: Equatable, Sendable {
    /// Enhance went with the text only: no LLM for it reads images.
    case imagesNotSent
  }

  /// Picks the LLM for a task on a family (nil = unknown); the `Bool` is true when the request carries pictures,
  /// so the LLM must read them.
  public typealias Resolve = @MainActor (LanguageModelTask, String?, Bool) -> Result<Choice, LanguageModelError>
  public typealias Respond = @MainActor (String, [URL], LanguageModelOptions, LanguageModelDescriptor) async throws(
    LanguageModelError
  ) -> String

  @ObservationIgnored private let resolve: Resolve
  @ObservationIgnored private let respond: Respond
  /// What the fields held before the last successful operation, and what that operation wrote.
  private var undo: (before: PromptPair, written: PromptPair)?

  /// Nil = idle; the buttons are disabled while it is not.
  public private(set) var working: Kind?
  /// Of the last operation; every new operation clears it.
  public private(set) var failure: Failure?
  /// Of the last operation; every new operation clears it.
  public private(set) var note: Note?

  public init(resolve: @escaping Resolve, respond: @escaping Respond) {
    self.resolve = resolve
    self.respond = respond
  }

  /// With `images` (the start image and the Moodboard pictures that are on) they go to the LLM, numbered; when no LLM
  /// for Enhance reads images the text goes alone and `note` says so.
  public func enhance(_ current: PromptPair, family: String?, images: EnhanceImages = EnhanceImages()) async -> PromptPair? {
    guard working == nil else { return nil }
    guard !current.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      failure = .emptyPrompt
      return nil
    }
    return await run(.enhance, current: current, family: family, withImages: !images.isEmpty) { choice, withImages in
      let attached = withImages ? images : EnhanceImages()
      return choice.profile.systemPrompt(for: .enhance, withImages: withImages).map {
        PromptBrief.enhance(current, ownSystem: $0, generation: choice.profile.generation, images: attached)
      } ?? PromptBrief.enhance(current, family: family, images: attached)
    }
  }

  public func describe(imageAt url: URL?, current: PromptPair, family: String?) async -> PromptPair? {
    guard working == nil else { return nil }
    guard let url else {
      failure = .noImage
      return nil
    }
    return await run(.describe, current: current, family: family, withImages: true) { choice, _ in
      choice.profile.systemPrompt(for: .describe).map {
        PromptBrief.describe(imageAt: url, ownSystem: $0, generation: choice.profile.generation)
      } ?? PromptBrief.describe(imageAt: url, family: family)
    }
  }

  /// The text from before the last operation, only while the fields still hold what it wrote.
  public func undoOffer(current: PromptPair) -> PromptPair? {
    guard let undo, undo.written == current else { return nil }
    return undo.before
  }

  public func clearUndo() {
    undo = nil
  }

  private func run(
    _ kind: Kind, current: PromptPair, family: String?, withImages: Bool, request: (Choice, Bool) -> PromptRequest
  ) async -> PromptPair? {
    working = kind
    failure = nil
    note = nil
    defer { working = nil }
    let task: LanguageModelTask = kind == .enhance ? .enhance : .describe
    var withImages = withImages
    var found = resolve(task, family, withImages)
    // Enhance can do without the pictures; Generate cannot.
    var droppedImages = false
    if kind == .enhance, withImages, case .failure(.imagesNotSupported) = found {
      withImages = false
      droppedImages = true
      found = resolve(task, family, false)
    }
    let choice: Choice
    switch found {
    case .success(let chosen): choice = chosen
    case .failure(let error):
      failure = .model(error)
      return nil
    }
    if droppedImages { note = .imagesNotSent }
    let request = request(choice, withImages)
    let raw: String
    do {
      raw = try await respond(request.prompt, request.images, request.options, choice.model)
    } catch {
      failure = .model(error)
      return nil
    }
    guard let parsed = PromptBrief.parse(raw) else {
      failure = .emptyAnswer
      return nil
    }
    let usesNegative = PromptGuides.guide(for: family)?.usesNegative == true
    let result = PromptPair(
      prompt: parsed.prompt, negative: usesNegative && !parsed.negative.isEmpty ? parsed.negative : current.negative)
    undo = (before: current, written: result)
    return result
  }
}
