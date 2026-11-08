import Foundation

public enum JobKind: String, Sendable, Equatable, Codable { case run, queue, pipeline }
public enum JobState: String, Sendable, Equatable, Codable { case running, finished, failed, stopped }

public struct JobStatus: Equatable, Sendable, Codable {
  public var id: String
  public var kind: JobKind
  public var state: JobState
  public var done: Int
  public var total: Int
  public var pass: Int?
  public var passes: Int?
  public var resultIDs: [String]
  public var error: String?
}

/// The jobs an agent started (spec §7). Draw Things makes one thing at a time, so there is at most one running job.
@MainActor
public final class JobTracker {
  public private(set) var activeJobID: String?
  public private(set) var acceptsNewJobs = true
  private var jobs: [String: JobStatus] = [:]
  private var waiters: [UUID: (jobID: String, continuation: CheckedContinuation<JobStatus?, Never>)] = [:]
  private var counter = 0

  public init() {}

  public func begin(kind: JobKind, images: Int) throws(AgentError) -> String {
    guard acceptsNewJobs else {
      throw .unavailable("The client disconnected: no new job is started until it reconnects.")
    }
    if let activeJobID { throw .busy(jobID: activeJobID) }
    counter += 1
    let id = "job-\(counter)"
    jobs[id] = JobStatus(id: id, kind: kind, state: .running, done: 0, total: images, resultIDs: [])
    activeJobID = id
    return id
  }

  /// Ends a job that never started (refused by the budget, or the app could not start it).
  public func abort(_ id: String, reason: String) {
    guard var job = jobs[id], job.state == .running else { return }
    job.state = .failed
    job.error = reason
    jobs[id] = job
    finish(id)
  }

  public func apply(_ event: AgentJobEvent) {
    guard let id = activeJobID, var job = jobs[id] else { return }
    switch event {
    case .progress(let done, let total, let pass, let passes):
      job.done = done
      job.total = total
      job.pass = pass
      job.passes = passes
      jobs[id] = job
      return
    case .finished(let ids):
      job.state = .finished
      job.resultIDs = ids
      job.done = max(job.done, job.total)
    case .failed(let message):
      job.state = .failed
      job.error = message
    case .stopped:
      job.state = .stopped
    }
    jobs[id] = job
    finish(id)
  }

  public func status(_ id: String) -> JobStatus? { jobs[id] }

  public func effectiveTimeout(for seconds: Int) -> Int { min(max(seconds, 0), 300) }

  /// The status when the job ends, or at the timeout (the running state, not an error). nil for an unknown job.
  public func wait(_ id: String, timeoutSeconds: Int) async -> JobStatus? {
    guard let job = jobs[id] else { return nil }
    guard job.state == .running else { return job }
    let seconds = effectiveTimeout(for: timeoutSeconds)
    let key = UUID()
    return await withCheckedContinuation { continuation in
      waiters[key] = (id, continuation)
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(seconds))
        await self?.expire(key)
      }
    }
  }

  public func clientDisconnected() { acceptsNewJobs = false }
  public func clientConnected() { acceptsNewJobs = true }

  private func expire(_ key: UUID) {
    guard let waiter = waiters.removeValue(forKey: key) else { return }
    waiter.continuation.resume(returning: jobs[waiter.jobID])
  }

  private func finish(_ id: String) {
    if activeJobID == id { activeJobID = nil }
    for (key, waiter) in waiters where waiter.jobID == id {
      waiters.removeValue(forKey: key)
      waiter.continuation.resume(returning: jobs[id])
    }
  }
}
