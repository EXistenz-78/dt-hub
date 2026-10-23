import Foundation
import Testing

@testable import PromptMasterMOSS

struct WorkFolderTests {
  @Test func aWriteMakesTheThreeFilesAndTheNextOneReplacesThem() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("moss-work-\(UUID().uuidString)")
    let work = MossWorkFolder(folder: folder)
    let snapshot = MossSnapshot(description: "prima", selection: ["x"], freeMeta: ["m"], captions: [1: "uno"], tags: [1: "t"])
    work.write(request: "r1", answer: "a1", before: snapshot)
    for name in ["request.md", "answer.md", "before.md"] {
      #expect(FileManager.default.fileExists(atPath: work.directory.appendingPathComponent(name).path), Comment(rawValue: name))
    }
    work.write(request: "r2", answer: "a2", before: snapshot)
    #expect(try String(contentsOf: work.directory.appendingPathComponent("request.md"), encoding: .utf8) == "r2")
    #expect(try String(contentsOf: work.directory.appendingPathComponent("before.md"), encoding: .utf8).contains("## element 1"))
  }
}
