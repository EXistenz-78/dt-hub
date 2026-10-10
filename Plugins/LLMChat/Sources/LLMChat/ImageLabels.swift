import Foundation

/// The numbered list of the pictures that go with a message, as Draw Things numbers them (the start image is 1 when there is
/// one, then the Moodboard pictures). The same text the app's Enhance Prompt sends.
enum ImageLabels {
  static func lines(hasStart: Bool, references: Int) -> [String] {
    var labels: [String] = []
    if hasStart { labels.append("Image 1: the start image (the picture being edited).") }
    for index in 0..<max(references, 0) {
      labels.append("Image \(labels.count + 1): reference image \(index + 1).")
    }
    return labels
  }

  /// The block put in front of the user's text; nil without pictures.
  static func block(hasStart: Bool, references: Int) -> String? {
    let labels = lines(hasStart: hasStart, references: references)
    guard !labels.isEmpty else { return nil }
    return "Attached images:\n" + labels.map { "- " + $0 }.joined(separator: "\n")
      + "\n\nThe prompt refers to these images. Look at them to make the description concrete and accurate, and keep every reference to an image (image 1, image 2…) exactly as written.\n\n"
  }
}
