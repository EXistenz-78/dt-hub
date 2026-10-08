import Foundation

public enum ProjectNameError: Error, Equatable, Sendable {
  case empty, forbiddenCharacter, leadingDot, tooLong, looksLikeADate, alreadyExists
}

/// The rules for the name of a project (spec §4): it becomes a folder name.
public enum ProjectName {
  public static let maxLength = 120

  /// Success is the name without its outer spaces. `existing` are the names already used in the output folder (projects
  /// and other folders): case and accents do not tell two names apart.
  public static func validate(_ raw: String, existing: [String]) -> Result<String, ProjectNameError> {
    let name = raw.trimmingCharacters(in: .whitespaces)
    if name.isEmpty { return .failure(.empty) }
    if name.contains("/") || name.contains(":") { return .failure(.forbiddenCharacter) }
    if name.hasPrefix(".") { return .failure(.leadingDot) }
    if name.count > maxLength { return .failure(.tooLong) }
    // A folder named like a day would be mistaken for the folders the pictures go in.
    if name.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { return .failure(.looksLikeADate) }
    let key = fold(name)
    if existing.contains(where: { fold($0) == key }) { return .failure(.alreadyExists) }
    return .success(name)
  }

  private static func fold(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }
}
