import Foundation

/// A term as the list shows it.
struct TermNode: Identifiable, Equatable {
  var id: String
  /// What the interface shows: the Italian or English name, or the text of a custom term.
  var title: String
  /// What the language model gets.
  var english: String
  var isCustom: Bool
}

struct CategoryNode: Identifiable, Equatable {
  var id: String
  var title: String
  var details: String?
  /// The terms are things to avoid.
  var isNegative: Bool
  var terms: [TermNode]
}

struct GroupNode: Identifiable, Equatable {
  var id: String
  var title: String
  var categories: [CategoryNode]
}

/// A term the user chose, with what the brief needs.
struct SelectedTerm: Identifiable, Equatable {
  var id: String
  var title: String
  var categoryTitle: String
  /// The English name of the category, which tells the language model how to use the term (a light, a palette, a genre).
  var categoryEnglish: String
  var english: String
  var isNegative: Bool
}

/// The list of the left card: groups → categories → terms, for one family (some categories are hidden), in one
/// language, with the user's own terms in their categories, and optionally narrowed by a search.
struct TermTree: Equatable {
  private(set) var groups: [GroupNode]
  /// The search narrowed the list: the groups and categories that are left are shown open.
  private(set) var isFiltered = false
  /// Every term id of each category, and every category id of each group, before any search: the counts of chosen
  /// terms do not change while one types.
  private var termIDsByCategory: [String: [String]]
  private var categoryIDsByGroup: [String: [String]]
  private var everyTerm: [String: SelectedTerm]
  private var order: [String]

  init(database: PromptDatabase, custom: [CustomTerm], hidden: Set<String>, italian: Bool) {
    var groups: [GroupNode] = []
    var termIDs: [String: [String]] = [:]
    var categoryIDs: [String: [String]] = [:]
    var every: [String: SelectedTerm] = [:]
    var order: [String] = []
    for group in database.groups {
      var categories: [CategoryNode] = []
      for category in database.categories where category.group == group.id && !hidden.contains(category.id) {
        let categoryTitle = italian ? category.it : category.en
        let isNegative = category.negative == true
        var terms = category.terms.map {
          TermNode(id: $0.id, title: italian ? $0.it : $0.en, english: $0.en, isCustom: false)
        }
        terms += custom.filter { $0.categoryID == category.id }.map {
          TermNode(id: $0.id, title: $0.text, english: $0.text, isCustom: true)
        }
        for term in terms {
          every[term.id] = SelectedTerm(
            id: term.id, title: term.title, categoryTitle: categoryTitle, categoryEnglish: category.en,
            english: term.english, isNegative: isNegative)
          order.append(term.id)
        }
        termIDs[category.id] = terms.map(\.id)
        categories.append(
          CategoryNode(
            id: category.id, title: categoryTitle, details: italian ? category.descIt : nil, isNegative: isNegative,
            terms: terms))
      }
      guard !categories.isEmpty else { continue }
      categoryIDs[group.id] = categories.map(\.id)
      groups.append(GroupNode(id: group.id, title: italian ? group.it : group.en, categories: categories))
    }
    (self.groups, termIDsByCategory, categoryIDsByGroup, everyTerm, self.order) = (groups, termIDs, categoryIDs, every, order)
  }

  // MARK: Search

  /// Lower case, without accents.
  static func fold(_ text: String) -> String { text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }

  /// The list narrowed by `query`: every word must be in the name (Italian or English, or a custom text). A group or
  /// category whose own name matches keeps everything below it. An empty query is the whole list.
  func filtered(by query: String, database: PromptDatabase, italian: Bool) -> TermTree {
    let words = Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return self }
    func matches(_ texts: [String]) -> Bool {
      let haystack = Self.fold(texts.joined(separator: " "))
      return words.allSatisfy { haystack.contains($0) }
    }
    var copy = self
    copy.isFiltered = true
    copy.groups = groups.compactMap { group in
      let source = database.groups.first { $0.id == group.id }
      if matches([source?.it ?? "", source?.en ?? ""]) { return group }
      let categories = group.categories.compactMap { category -> CategoryNode? in
        let source = database.categories.first { $0.id == category.id }
        if matches([source?.it ?? "", source?.en ?? ""]) { return category }
        var narrowed = category
        let all = Dictionary(uniqueKeysWithValues: (source?.terms ?? []).map { ($0.id, $0) })
        narrowed.terms = category.terms.filter { term in
          guard let known = all[term.id] else { return matches([term.title]) }  // a custom term
          return matches([known.it, known.en])
        }
        return narrowed.terms.isEmpty ? nil : narrowed
      }
      guard !categories.isEmpty else { return nil }
      var narrowed = group
      narrowed.categories = categories
      return narrowed
    }
    return copy
  }

  // MARK: Counts and choices

  func chosenCount(inCategory id: String, selection: Set<String>) -> Int {
    (termIDsByCategory[id] ?? []).filter(selection.contains).count
  }

  func chosenCount(inGroup id: String, selection: Set<String>) -> Int {
    (categoryIDsByGroup[id] ?? []).reduce(0) { $0 + chosenCount(inCategory: $1, selection: selection) }
  }

  /// The chosen terms in the order of the list (groups, categories, terms); an id the list no longer has is dropped.
  func selectedTerms(_ selection: Set<String>) -> [SelectedTerm] {
    order.filter(selection.contains).compactMap { everyTerm[$0] }
  }

  /// The selection without the ids this list does not have (a term of a hidden category, of an older database).
  func pruned(_ selection: Set<String>) -> Set<String> { selection.filter { everyTerm[$0] != nil } }
}
