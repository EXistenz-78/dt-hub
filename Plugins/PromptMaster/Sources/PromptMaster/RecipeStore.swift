import Foundation

/// A saved brief: the chosen terms, the Shuffle mode, the booru switch and the description, under a name.
struct Recipe: Codable, Equatable, Identifiable {
  var name: String
  var selection: [String]
  var mode: StyleMode
  var booru: Bool
  var description: String
  var id: String { name.lowercased() }
}

/// The user's recipes, in `recipes.json` of the plug-in's folder. Global, not per project: a recipe is a reusable look,
/// and the user's own terms it may hold live in the same global folder. Same name (ignoring case) = overwrite.
struct RecipeStore {
  enum Failure: Error, Equatable {
    case empty
    case unreadableFile
    case cannotWrite
  }

  static let fileName = "recipes.json"
  static let maxNameLength = 60
  static let schema = 1

  var folder: URL = DataSource.defaultFolder.appendingPathComponent(PMData.pluginFolderName, isDirectory: true)

  private struct File: Codable {
    var schema: Int
    var recipes: [Recipe]
  }

  private var fileURL: URL { folder.appendingPathComponent(Self.fileName) }

  static func clean(_ name: String) -> String {
    String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
  }

  func load() -> [Recipe] { (try? read()) ?? [] }

  private func read() throws -> [Recipe] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(File.self, from: data),
      file.schema == Self.schema
    else { throw Failure.unreadableFile }
    return file.recipes
  }

  /// Saves a recipe; one with the same name (ignoring case) is replaced in place. Returns true if it replaced one.
  @discardableResult
  func save(_ recipe: Recipe) throws -> Bool {
    var recipe = recipe
    recipe.name = Self.clean(recipe.name)
    guard !recipe.name.isEmpty else { throw Failure.empty }
    var recipes = try read()
    let replaced: Bool
    if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
      recipes[index] = recipe
      replaced = true
    } else {
      recipes.append(recipe)
      replaced = false
    }
    try write(recipes)
    return replaced
  }

  func remove(name: String) throws {
    var recipes = try read()
    let key = Self.clean(name).lowercased()
    recipes.removeAll { $0.id == key }
    try write(recipes)
  }

  private func write(_ recipes: [Recipe]) throws {
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(File(schema: Self.schema, recipes: recipes)).write(to: fileURL, options: .atomic)
    } catch {
      throw Failure.cannotWrite
    }
  }
}
