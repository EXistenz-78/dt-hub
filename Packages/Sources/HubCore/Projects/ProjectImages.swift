import Foundation
import HubKit

/// The pictures a project holds, read back from its `yyyy-MM-dd` folders.
public enum ProjectImages {
  /// The newest picture: the latest day folder that has one, then the highest name in it (`HHmmss-<seed>…`).
  public static func latestImage(in project: Project) -> URL? {
    let fileManager = FileManager.default
    let days = ((try? fileManager.contentsOfDirectory(atPath: project.folder.path)) ?? [])
      .filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
      .sorted(by: >)
    for day in days {
      let folder = project.folder.appendingPathComponent(day, isDirectory: true)
      let names = ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [])
        .filter { $0.lowercased().hasSuffix(".png") }
        .sorted(by: >)
      if let name = names.first { return folder.appendingPathComponent(name) }
    }
    return nil
  }

  /// The job saved inside the newest picture. If that picture cannot be read the answer is nil: the newest one decides,
  /// not the first good one.
  public static func latestJob(in project: Project) -> GenerationJob? {
    latestImage(in: project).flatMap { PNGImageStore.job(in: $0) }
  }
}
