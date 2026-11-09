import Testing

@testable import HubMCP

@MainActor
struct JobTrackerTests {
  @Test func beginWhileActiveThrowsBusyWithCurrentID() throws {
    let t = JobTracker()
    let first = try t.begin(kind: .run, images: 2)
    do {
      _ = try t.begin(kind: .run, images: 1)
      Issue.record("expected busy")
    } catch {
      #expect(error.kind == .busy(jobID: first))
    }
  }

  @Test func progressEventsUpdateDoneAndTotal() throws {
    let t = JobTracker()
    let id = try t.begin(kind: .queue, images: 6)
    t.apply(.progress(done: 2, total: 6, pass: nil, passes: nil))
    let s = try #require(t.status(id))
    #expect(s.done == 2 && s.total == 6 && s.state == .running)
  }

  @Test func finishedEventStoresResultIDsAndFreesTheSlot() throws {
    let t = JobTracker()
    let id = try t.begin(kind: .run, images: 1)
    t.apply(.finished(resultIDs: ["r1"]))
    #expect(t.status(id)?.state == .finished)
    #expect(t.status(id)?.resultIDs == ["r1"])
    #expect(t.activeJobID == nil)
    _ = try t.begin(kind: .run, images: 1)
  }

  @Test func failedAndStoppedEvents() throws {
    let t = JobTracker()
    let a = try t.begin(kind: .run, images: 1)
    t.apply(.failed("boom"))
    #expect(t.status(a)?.state == .failed && t.status(a)?.error == "boom")
    let b = try t.begin(kind: .run, images: 1)
    t.apply(.stopped)
    #expect(t.status(b)?.state == .stopped)
  }

  @Test func abortFreesTheSlotAndMarksFailed() throws {
    let t = JobTracker()
    let id = try t.begin(kind: .run, images: 5)
    t.abort(id, reason: "Budget exhausted")
    #expect(t.status(id)?.state == .failed)
    #expect(t.activeJobID == nil)
  }

  @Test func waitReturnsAsSoonAsJobFinishes() async throws {
    let t = JobTracker()
    let id = try t.begin(kind: .run, images: 1)
    let waiter = Task { @MainActor in await t.wait(id, timeoutSeconds: 30) }
    await Task.yield()
    t.apply(.finished(resultIDs: ["r"]))
    #expect(await waiter.value?.state == .finished)
  }

  @Test func waitReturnsRunningStateAtTimeoutNotAnError() async throws {
    let t = JobTracker()
    let id = try t.begin(kind: .run, images: 1)
    let s = await t.wait(id, timeoutSeconds: 0)
    #expect(s?.state == .running)
  }

  @Test func defaultWaitIs30SecondsBecauseClientsTimeOutOnLongerOnes() {
    #expect(JobTracker.defaultWaitSeconds == 30)
  }

  @Test func waitCapsAt300Seconds() {
    let t = JobTracker()
    #expect(t.effectiveTimeout(for: 9999) == 300)
    #expect(t.effectiveTimeout(for: -5) == 0)
    #expect(t.effectiveTimeout(for: 42) == 42)
  }

  @Test func disconnectLetsRunningJobFinishButBlocksNewOnes() throws {
    let t = JobTracker()
    let id = try t.begin(kind: .run, images: 3)
    t.clientDisconnected()
    #expect(t.acceptsNewJobs == false)
    t.apply(.finished(resultIDs: ["x"]))
    #expect(t.status(id)?.state == .finished)
    do {
      _ = try t.begin(kind: .run, images: 1)
      Issue.record("expected refusal")
    } catch {
      #expect(error.kind == .unavailable)
    }
    t.clientConnected()
    #expect(t.acceptsNewJobs)
  }

  @Test func unknownJobIsNil() async {
    let t = JobTracker()
    #expect(t.status("nope") == nil)
    #expect(await t.wait("nope", timeoutSeconds: 0) == nil)
  }
}
