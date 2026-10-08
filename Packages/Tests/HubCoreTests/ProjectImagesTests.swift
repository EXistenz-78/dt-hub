import Foundation
import HubKit
import Testing

@testable import HubCore

struct ProjectImagesTests {
  private func makeProject() throws -> (Project, URL) {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("pimg-\(UUID().uuidString)")
    return (try ProjectCatalog(outputFolder: output).create(named: "A"), output)
  }

  private func job(seed: Int) -> GenerationJob {
    GenerationJob(
      prompt: "prompt \(seed)", model: "m.ckpt", parameters: GenerationParameters(seed: UInt32(seed), randomSeed: false))
  }

  private let day = Date(timeIntervalSince1970: 1_790_000_000)

  private func save(_ seed: Int, at date: Date, in project: Project) throws -> URL {
    try PNGImageStore(folder: project.folder).save(testImage(), job: job(seed: seed), index: 0, date: date)
  }

  @Test func theLatestImageIsTheNewestByDayThenByName() throws {
    let (project, output) = try makeProject()
    defer { try? FileManager.default.removeItem(at: output) }
    _ = try save(1, at: day, in: project)
    _ = try save(2, at: day.addingTimeInterval(60), in: project)
    let newest = try save(3, at: day.addingTimeInterval(86_400 * 2), in: project)
    _ = try save(4, at: day.addingTimeInterval(86_400), in: project)
    #expect(ProjectImages.latestImage(in: project) == newest)
    #expect(ProjectImages.latestJob(in: project)?.parameters.seed == 3)
  }

  @Test func inTheSameDayTheLaterTimeWins() throws {
    let (project, output) = try makeProject()
    defer { try? FileManager.default.removeItem(at: output) }
    _ = try save(1, at: day, in: project)
    let later = try save(2, at: day.addingTimeInterval(120), in: project)
    #expect(ProjectImages.latestImage(in: project) == later)
    #expect(ProjectImages.latestJob(in: project)?.prompt == "prompt 2")
  }

  @Test func aProjectWithoutPicturesHasNone() throws {
    let (project, output) = try makeProject()
    defer { try? FileManager.default.removeItem(at: output) }
    #expect(ProjectImages.latestImage(in: project) == nil)
    #expect(ProjectImages.latestJob(in: project) == nil)
  }

  @Test func theStateFolderAndOtherFoldersAreNotScanned() throws {
    let (project, output) = try makeProject()
    defer { try? FileManager.default.removeItem(at: output) }
    let mine = try save(1, at: day, in: project)
    // A picture in the hidden state folder, and one in a folder that is not a day.
    try FileManager.default.createDirectory(at: project.folder.appendingPathComponent("zzz"), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: project.folder.appendingPathComponent("zzz/p.png"))
    try Data("x".utf8).write(to: project.controlFolder.appendingPathComponent("2099-01-01.png"))
    try Data("x".utf8).write(to: project.folder.appendingPathComponent("loose.png"))
    #expect(ProjectImages.latestImage(in: project) == mine)
  }

  @Test func aNewestPNGWithoutAReadableJobGivesNoJobNotTheOneBefore() throws {
    let (project, output) = try makeProject()
    defer { try? FileManager.default.removeItem(at: output) }
    _ = try save(1, at: day, in: project)
    let dayFolder = project.folder.appendingPathComponent(
      (try save(2, at: day.addingTimeInterval(86_400), in: project)).deletingLastPathComponent().lastPathComponent)
    let broken = dayFolder.appendingPathComponent("999999-0.png")
    try Data("not a png".utf8).write(to: broken)
    #expect(ProjectImages.latestImage(in: project) == broken)
    #expect(ProjectImages.latestJob(in: project) == nil)
  }

  @Test func anEmptyDayFolderIsSkipped() throws {
    let (project, output) = try makeProject()
    defer { try? FileManager.default.removeItem(at: output) }
    let mine = try save(1, at: day, in: project)
    try FileManager.default.createDirectory(
      at: project.folder.appendingPathComponent("2099-12-31"), withIntermediateDirectories: true)
    #expect(ProjectImages.latestImage(in: project) == mine)
  }
}
