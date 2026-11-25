import HubKit

/// The check a pass that tiles (`seamless`) passes right before it is sent: the same rule as a plug-in's proposal
/// (`ContributionStore.seamlessProblem`), asked again with the family of the model the pass runs with. The proposal was
/// checked when it arrived, but a pipeline can reach RUN without that check (a queue entry put back, a proposal parked as
/// a conflict and then chosen, a guided pass) and the server can change after it: a pass is never sent untiled while it
/// looks seamless.
public enum SeamlessPassCheck {
  /// Why the pass cannot be sent (the rule's own text); nil when it does not tile or the rule allows it. Without a rule
  /// (`check` nil) nothing is refused, as for a proposal.
  public static func problem(for step: PipelineStep, family: String?, check: ((String?) -> String?)?) -> String? {
    guard step.seamless != nil else { return nil }
    return check?(family)
  }
}

extension GenerationSession {
  /// Before a pass is sent: a pass whose tiling is refused fails the RUN with the refusal, and true says that nothing
  /// may be sent. False for a pass that may go.
  public func refusesSeamlessPass(_ step: PipelineStep, family: String?, check: ((String?) -> String?)?) -> Bool {
    guard let problem = SeamlessPassCheck.problem(for: step, family: family, check: check) else { return false }
    fail(with: .generationFailed(problem))
    return true
  }
}
