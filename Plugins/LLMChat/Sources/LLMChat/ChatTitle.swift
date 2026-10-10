import Foundation

enum ChatTitle {
  static let maxLength = 40

  /// The first line of the first message, without the command, at most 40 characters ("…" when cut); for a message
  /// with no text, "Chat of Oct 10, 14:32".
  static func make(
    from text: String, date: Date, italian: Bool, timeZone: TimeZone = .current
  ) -> String {
    let cleaned = text.replacingOccurrences(of: "<INVIA>", with: "").replacingOccurrences(of: "<SEND>", with: "")
    let first = cleaned.split(separator: "\n", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    if let first {
      return first.count > maxLength ? String(first.prefix(maxLength)) + "…" : first
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: italian ? "it_IT" : "en_US")
    formatter.timeZone = timeZone
    formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
    return (italian ? "Chat del " : "Chat of ") + formatter.string(from: date)
  }
}
