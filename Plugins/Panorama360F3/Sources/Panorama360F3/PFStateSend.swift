import CoreGraphics
import Foundation

extension PFState {
  /// What the app answered in `problems`, or its error: the words to show; nil when it took the contribution.
  func problem(in answer: [String: Any]?) -> String? {
    guard let answer else { return text(.noAnswerFromApp) }
    if answer["type"] as? String == "error" { return answer["text"] as? String ?? text(.noAnswerFromApp) }
    if let problems = answer["problems"] as? [String], !problems.isEmpty { return problems.joined(separator: "\n") }
    return nil
  }

  /// Proposes the guided pipeline (panorama, then Seamfix) to the app; the user then presses RUN.
  func send(contribute: PFContribute) async {
    error = nil
    notice = nil
    guard let projectFolder else {
      error = text(.openProjectFirst)
      return
    }
    let visible = visibleImages
    guard !visible.isEmpty else {
      error = text(.noVisibleImage)
      return
    }
    var urls: [URL] = []
    for image in visible {
      let url = projectFolder.appendingPathComponent(image.file)
      guard FileManager.default.fileExists(atPath: url.path) else {
        error = text(.imageMissing, image.name)
        return
      }
      urls.append(url)
    }
    guard !isSending else { return }
    isSending = true
    defer { isSending = false }
    let made = PFSession(kind: .generate(images: urls, description: doc.description, size: doc.size), folder: exchangeFolder)
    let pipeline: [String: Any] = ["name": text(.pipelineName), "guided": true, "passes": made.passCount, "estimate": made.estimate()]
    if let message = problem(in: await contribute(["pipeline": pipeline])) {
      error = message
      return
    }
    session = made
    notice = readyNote()
  }

  /// «Ready» or, when the model of the presets is not the one in the header, which one to choose.
  func readyNote() -> String {
    if let model = presetModel(), model != modelFile { return text(.modelNote, model.replacingOccurrences(of: ".ckpt", with: "")) }
    return text(.pipelineReady)
  }

  private func presetModel() -> String? {
    guard let data = try? Data(contentsOf: presetsFolder.appendingPathComponent("\(PFPresets.panoName).json")),
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let model = object["model"] as? String, !model.isEmpty
    else { return nil }
    return model
  }

  // MARK: the app drives the run

  private func previous(in object: [String: Any]?) -> PFSession.Previous? {
    guard let box = object?["previous"] as? [String: Any], let path = box["path"] as? String, let width = box["width"] as? Int,
      let height = box["height"] as? Int
    else { return nil }
    return (path, width, height)
  }

  /// `session.next`: the pass, or `{"done":true}` when there is none to give.
  func sessionNext(_ message: Data) async -> Data {
    let done = Data(#"{"done":true}"#.utf8)
    guard let object = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any], let index = object["index"] as? Int, let session
    else { return done }
    let previous = previous(in: object)
    return await Task.detached(priority: .userInitiated) {
      (try? JSONSerialization.data(withJSONObject: session.next(index: index, previous: previous))) ?? done
    }.value
  }

  /// `session.end`: the panorama goes to the Results, or nothing does and the reason is shown.
  func sessionEnded(_ message: Data, contribute: PFContribute) async {
    guard let session else { return }
    self.session = nil
    error = nil
    notice = nil
    let object = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any]
    let previous = previous(in: object)
    let reason = object?["reason"] as? String ?? "closed"
    let outcome = await Task.detached(priority: .userInitiated) { session.end(reason: reason, previous: previous) }.value
    switch outcome {
    case .nothing(let why):
      switch why {
      case .stopped: notice = text(.runStopped)
      case .closed: notice = text(.runClosed)
      case .failed: error = text(.runFailed)
      case .noPicture: error = text(.runNoPicture)
      case .wrongSize: error = text(.runWrongSize)
      case .unreadable: error = text(.runUnreadable)
      }
    case .panorama(let image, let corrected):
      guard let url = writeResult(image) else {
        error = text(.sendFailed)
        return
      }
      let description = text(corrected ? .resultCorrected : .resultRaw)
      let body: [String: Any] = ["result": ["path": url.path, "name": url.lastPathComponent, "description": description]]
      if let message = problem(in: await contribute(body)) {
        error = message
      } else {
        notice = text(.runDone)
        if !doc.viewerOpen { mutate { $0.viewerOpen = true } }
      }
    }
  }

  private func writeResult(_ image: CGImage) -> URL? {
    guard let data = PFPixels.pngData(image) else { return nil }
    let url = exchangeFolder.appendingPathComponent("pano-360-f3-\(UUID().uuidString).png")
    do {
      try FileManager.default.createDirectory(at: exchangeFolder, withIntermediateDirectories: true)
      try data.write(to: url)
      return url
    } catch {
      return nil
    }
  }
}
