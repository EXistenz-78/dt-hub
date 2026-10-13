import Foundation

/// Brings a LoRA's page into its entry (spec §6.3): the text into the notes, the first picture as the thumbnail.
@MainActor
struct LAImporter {
  let fetcher: any LAFetching
  let store: LAStore

  init(fetcher: any LAFetching, store: LAStore) {
    self.fetcher = fetcher
    self.store = store
  }

  /// What to do with notes the user wrote. Empty notes, and those that are still the raw text of a page, are always
  /// replaced.
  enum Notes {
    case keepUsers
    case replace
  }

  enum Outcome: Equatable {
    /// `noImage`: the page had no picture the plug-in could use; the thumbnail is as it was.
    case imported(noImage: Bool)
    case failed(LAFetchError)
  }

  func importPage(_ link: LALink, for file: String, notes: Notes) async -> Outcome {
    // The link is kept even when the page cannot be had: the user gave it.
    store.update(file) { $0.link = link.canonical }
    let page: LAPage
    do throws(LAFetchError) {
      page = try await self.page(link)
    } catch {
      return .failed(error)
    }
    let entry = store.entry(for: file)
    let usersNotes = !entry.notes.isEmpty && !entry.rawNotes
    if !usersNotes || notes == .replace {
      store.setPageText(page.text.isEmpty ? nil : page.text, for: file)
      store.update(file) {
        $0.notes = LAText.excerpt(page.text)
        $0.rawNotes = !page.text.isEmpty
      }
    }
    // A thumbnail the user chose stays.
    guard !entry.manualThumbnail else { return .imported(noImage: false) }
    guard let address = page.imageURL, let data = try? await fetcher.data(from: address, limit: LALimits.image),
      let jpeg = LAThumbnail.jpeg(from: data)
    else { return .imported(noImage: true) }
    store.setThumbnail(jpeg, manual: false, for: file)
    return .imported(noImage: false)
  }

  private func page(_ link: LALink) async throws(LAFetchError) -> LAPage {
    switch link {
    case .civitai(let model, let version):
      return try LACivitai.page(
        json: try await fetcher.data(from: LACivitai.modelURL(model), limit: LALimits.text), version: version)
    case .huggingFace(let repo):
      let api = try await fetcher.data(from: LAHuggingFace.apiURL(repo: repo), limit: LALimits.text)
      // A repository without a card still has its files.
      let readme = (try? await fetcher.data(from: LAHuggingFace.readmeURL(repo: repo), limit: LALimits.text))
        .flatMap { String(data: $0, encoding: .utf8) } ?? ""
      return LAHuggingFace.page(api: api, readme: readme, repo: repo)
    }
  }
}
