import DTHubPluginKit
import Foundation

/// The master prompt of «Improve prompt» (a Markdown file in `Data/panorama-360/`, with the user's own in `custom/`) and the checks on what the
/// language model answers. The prompt it writes is only the description of the place: the LoRA's trigger phrase is added by DT Hub.
enum PSPrompt {
  static let masterPath = "master-prompt.md"
  static let folderName = "panorama-360"
  static let options = DTHubLLMOptions(temperature: 0.6, maxTokens: 1024, thinking: false, timeout: 300)

  static var defaultDataFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true).appendingPathComponent("Data", isDirectory: true)
  }

  static func folder(dataFolder: URL = defaultDataFolder) -> DTHubPromptFolder {
    DTHubPromptFolder(folder: dataFolder.appendingPathComponent(folderName, isDirectory: true))
  }

  /// At launch: writes the master prompt when it is missing or older than the built-in one, and makes `custom/`.
  static func install(dataFolder: URL = defaultDataFolder) {
    folder(dataFolder: dataFolder).install([masterPath: PSEmbedded.masterPrompt])
  }

  /// The system prompt: the master prompt (the file when valid and not older than the built-in copy), then the user's own after the priority line.
  static func system(in folder: DTHubPromptFolder = folder()) -> String {
    let master = folder.base(masterPath, embedded: PSEmbedded.masterPrompt).file.body
    return folder.assemble(rules: master, family: "", extras: [], customName: masterPath, label: "Panorama 360")
  }

  static let englishReminder = "Reply in English only: the previous reply was not in English."

  /// With `withPicture` the canvas goes along as a picture, and the request says what it is and what is asked of the model.
  static let pictureNote = """
    TASK CONTEXT. The attached picture is the starting canvas of an image model. It is a 2:1 equirectangular layout: the whole 360° \
    surroundings of a viewer, unrolled flat. Some pieces of the scene are already placed on it, each in the position where it will stay; \
    everything else is flat solid green. The image model will paint over the green so that the pieces are extended and joined into one \
    continuous scene, and the final result will be a complete 360° equirectangular panorama.

    YOUR JOB. Look only at the parts that are not flat green: what they show, where they are on the canvas, their light, colours and style. \
    Then describe what must fill the green around them, so that the whole panorama is one coherent place: what continues from each piece, \
    what surrounds it, what lies in the empty regions.
    """

  static func request(description: String, reminder: Bool = false, withPicture: Bool = false, in folder: DTHubPromptFolder = folder()) -> (prompt: String, system: String) {
    let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
    var prompt: String
    if withPicture {
      // With the picture the text is a guide for the description to write, and it may be missing.
      prompt = pictureNote + "\n\n" + (text.isEmpty ? "The user wrote no text: write the description from the picture alone." : "Use this text from the user as the guide for the description you write:\n\n" + text)
    } else {
      prompt = "Rewrite this description:\n\n" + text
    }
    if reminder { prompt += "\n\n" + englishReminder }
    return (prompt, system(in: folder))
  }

  /// The answer without the quotes, code fences or blank lines a model sometimes puts around it.
  static func clean(_ answer: String) -> String {
    var text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```") {
      text = text.drop { $0 != "\n" }.dropFirst().description
      if let end = text.range(of: "```", options: .backwards) { text = String(text[..<end.lowerBound]) }
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    for (open, close) in [("\"", "\""), ("“", "”"), ("'", "'")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > 1 {
      text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text
  }

  /// True when the text holds a piece of the LoRA's trigger phrase, which must never be in the prompt.
  static func containsTrigger(_ text: String) -> Bool {
    let lower = text.lowercased()
    return ["fill the green spaces", "outpaint as a seamless", "match left and right edges"].contains { lower.contains($0) }
  }

  private static let italian: Set<String> = [
    "il", "lo", "la", "le", "gli", "un", "una", "uno", "di", "del", "dello", "della", "dei", "delle", "degli", "che", "con", "su", "sul",
    "sulla", "sui", "tra", "fra", "per", "e", "è", "sono", "si", "nel", "nella", "nei", "al", "alla", "alle", "da", "dal", "dalla", "dentro",
    "sullo", "sfondo", "ma", "non", "anche", "molto", "più",
  ]
  private static let english: Set<String> = [
    "the", "a", "an", "of", "with", "and", "in", "on", "at", "is", "are", "to", "by", "from", "its", "their", "under", "over", "into", "behind",
    "next", "that", "which", "while",
  ]

  /// A coarse check, for Italian only (the user's language): a text the model should have written in English and left in Italian.
  static func looksItalian(_ text: String) -> Bool {
    let words = text.lowercased().split { !$0.isLetter }.map(String.init)
    let (it, en) = (words.filter { italian.contains($0) }.count, words.filter { english.contains($0) }.count)
    return it >= 2 && it > en
  }
}
