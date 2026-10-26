import CoreGraphics
import Foundation

extension PSState {
  /// Why «Correggi giunzione» is off; nil when it is on. It looks at the real size of the last result's file, not at the (reduced) picture shown.
  var seamReason: PSSeamReason? {
    guard let path = lastResultPath else { return .noResult }
    guard let size = patchSize(URL(fileURLWithPath: path)) else { return .unreadable }
    if case .failure(let reason) = PSSeam.plan(width: size.0, height: size.1) { return reason }
    return nil
  }

  func seamReasonText(_ reason: PSSeamReason) -> String {
    switch reason {
    case .noResult: text(.seamNoResult)
    case .unreadable: text(.seamUnreadable)
    case .notTwoToOne: text(.seamNotTwoToOne)
    case .heightNotMultipleOf64: text(.seamHeight)
    case .tooBig: text(.seamTooBig)
    }
  }

  /// Prepares the correction and proposes the guided pipeline to the app; the user then presses RUN.
  func prepareSeamCorrection(contribute: PSContribute) async {
    error = nil
    notice = nil
    if let reason = seamReason {
      error = seamReasonText(reason)
      return
    }
    guard let path = lastResultPath, let panorama = PSResultLoader.load(URL(fileURLWithPath: path), maxSide: nil),
      case .success(let plan) = PSSeam.plan(width: panorama.width, height: panorama.height)
    else {
      error = text(.seamUnreadable)
      return
    }
    let session = PSSeamSession(panorama: panorama, plan: plan, folder: exchangeFolder, italian: italian)
    let pipeline: [String: Any] = ["name": text(.seamPipelineName), "guided": true, "passes": 1, "estimate": session.estimate()]
    if let message = problem(in: await contribute(["pipeline": pipeline])) {
      error = message
      return
    }
    seamSession = session
    isSeamPrepared = true
    notice = text(.seamReady)
  }

  /// `session.next`: the pass, or `{"done":true}` when there is none to give.
  func seamNext(_ message: Data) -> Data {
    let done = Data(#"{"done":true}"#.utf8)
    guard let object = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any], let index = object["index"] as? Int,
      let session = seamSession
    else { return done }
    let answer = session.next(index: index, count: object["count"] as? Int ?? 1)
    return (try? JSONSerialization.data(withJSONObject: answer)) ?? done
  }

  /// `session.end`: the corrected panorama goes to the Results, or nothing does and the reason is shown.
  func seamEnded(_ message: Data, contribute: PSContribute) async {
    guard let session = seamSession else { return }
    seamSession = nil
    isSeamPrepared = false
    error = nil
    notice = nil
    let object = (try? JSONSerialization.jsonObject(with: message)) as? [String: Any]
    var previous: (path: String, width: Int, height: Int)?
    if let box = object?["previous"] as? [String: Any], let path = box["path"] as? String, let width = box["width"] as? Int,
      let height = box["height"] as? Int
    {
      previous = (path, width, height)
    }
    let reason = object?["reason"] as? String ?? "closed"
    let outcome = await Task.detached(priority: .userInitiated) { session.end(reason: reason, previous: previous) }.value
    switch outcome {
    case .nothing(let why):
      switch why {
      case .stopped: notice = text(.seamStopped)
      case .closed: notice = text(.seamClosed)
      case .failed: error = text(.seamFailed)
      case .noPicture: error = text(.seamNoPicture)
      case .wrongSize: error = text(.seamWrongSize)
      case .unreadable: error = text(.seamUnreadablePicture)
      }
    case .montage(let image, let description):
      do {
        let file = try writeTemporary(image, prefix: "panorama-360-seam")
        if let message = problem(in: await contribute(PSCutoutActions.montageBody(file: file, description: description))) {
          error = message
        } else {
          notice = text(.seamDone)
        }
      } catch {
        self.error = text(.sendFailed)
      }
    }
  }
}
