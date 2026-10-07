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

  public typealias Respond = @MainActor (String, [URL], LanguageModelOptions) async throws(LanguageModelError) ->
    String

  @ObservationIgnored private let respond: Respond
  /// What the fields held before the last successful operation, and what that operation wrote.
  private var undo: (before: PromptPair, written: PromptPair)?

  /// Nil = idle; the buttons are disabled while it is not.
  public private(set) var working: Kind?
  /// Of the last operation; every new operation clears it.
  public private(set) var failure: Failure?

  public init(respond: @escaping Respond) {
    self.respond = respond
  }

  public func enhance(_ current: PromptPair, family: String?) async -> PromptPair? {
    guard working == nil else { return nil }
    guard !current.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      failure = .emptyPrompt
      return nil
    }
    return await run(.enhance, PromptBrief.enhance(current, family: family), current: current, family: family)
  }

  public func describe(imageAt url: URL?, current: PromptPair, family: String?) async -> PromptPair? {
    guard working == nil else { return nil }
    guard let url else {
      failure = .noImage
      return nil
    }
    return await run(.describe, PromptBrief.describe(imageAt: url, family: family), current: current, family: family)
  }

  /// The text from before the last operation, only while the fields still hold what it wrote.
  public func undoOffer(current: PromptPair) -> PromptPair? {
    guard let undo, undo.written == current else { return nil }
    return undo.before
  }

  public func clearUndo() {
    undo = nil
  }

  private func run(_ kind: Kind, _ request: PromptRequest, current: PromptPair, family: String?) async -> PromptPair? {
    working = kind
    failure = nil
    defer { working = nil }
    let raw: String
    do {
      raw = try await respond(request.prompt, request.images, request.options)
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
