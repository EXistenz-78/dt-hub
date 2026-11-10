import CoreGraphics
import DTBridge
import Foundation
import HubCore
import HubKit

/// The folder of the open project, shared with the image store (which saves away from the main actor).
nonisolated final class ProjectFolderBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: URL?

  var folder: URL? {
    get { lock.withLock { value } }
    set { lock.withLock { value = newValue } }
  }
}

/// Saves into the open project's folder, as it is at the moment of saving; without a project nothing is saved.
struct ProjectImageStore: ImageStore {
  let box: ProjectFolderBox

  func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date, elapsed: TimeInterval?) throws -> URL {
    guard let folder = box.folder else { throw ImageStoreError.cannotWrite("no project") }
    // The layout of Draw Things, so the tools made for its pictures read DT Hub's too.
    return try PNGImageStore(
      folder: folder, metadata: DrawThingsMetadata.comment, description: DrawThingsMetadata.description)
      .save(image, job: job, index: index, date: date, elapsed: elapsed)
  }
}
