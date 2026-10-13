import Foundation
import Testing

@testable import LoRAAdvisor

@Suite(.serialized)
struct LAFetcherTests {
  let fetcher: LAFetcher = {
    let configuration = LAFetcher.configuration
    configuration.protocolClasses = [StubProtocol.self]
    return LAFetcher(configuration: configuration)
  }()

  func fetch(_ url: String, limit: Int = 1000) async -> Result<Data, LAFetchError> {
    do throws(LAFetchError) {
      return .success(try await fetcher.data(from: URL(string: url)!, limit: limit))
    } catch {
      return .failure(error)
    }
  }

  @Test func anAnswerWithinTheLimitComesBack() async {
    StubProtocol.set("https://civitai.com/ok", .init(body: Data("hello".utf8)))
    #expect(await fetch("https://civitai.com/ok") == .success(Data("hello".utf8)))
  }

  @Test func aBodyBeyondTheLimitIsRefused() async {
    StubProtocol.set("https://civitai.com/big", .init(body: Data(count: 6_000_000)))
    #expect(await fetch("https://civitai.com/big", limit: LALimits.text) == .failure(.tooLarge))
  }

  @Test func aRedirectOutOfTheAllowedHostsIsRefused() async {
    StubProtocol.set("https://civitai.com/out", .init(status: 302, headers: ["Location": "https://example.com/stolen"]))
    StubProtocol.set("https://example.com/stolen", .init(body: Data("x".utf8)))
    #expect(await fetch("https://civitai.com/out") == .failure(.notAllowed))
    #expect(!StubProtocol.requests.contains("https://example.com/stolen"))
  }

  @Test func aRedirectWithinTheAllowedHostsIsFollowed() async {
    StubProtocol.set("https://image.civitai.com/a", .init(status: 302, headers: ["Location": "https://blobs-b2.civitai.com/a"]))
    StubProtocol.set("https://blobs-b2.civitai.com/a", .init(body: Data("img".utf8)))
    #expect(await fetch("https://image.civitai.com/a") == .success(Data("img".utf8)))
  }

  @Test func theStatusBecomesTheError() async {
    for (status, error) in [(404, LAFetchError.notFound), (403, .needsAccess), (401, .needsAccess), (429, .rateLimited), (500, .unreachable)] {
      StubProtocol.set("https://civitai.com/s\(status)", .init(status: status))
      #expect(await fetch("https://civitai.com/s\(status)") == .failure(error), "\(status)")
    }
  }

  @Test func anAddressThatIsNotAllowedIsNeverAsked() async {
    #expect(await fetch("http://civitai.com/plain") == .failure(.notAllowed))
    #expect(await fetch("https://example.com/x") == .failure(.notAllowed))
    #expect(!StubProtocol.requests.contains { $0.contains("plain") || $0.contains("example.com/x") })
  }

  @Test func theSessionKeepsNoCookiesAndNoCache() {
    let configuration = LAFetcher.configuration
    #expect(configuration.httpCookieStorage == nil && configuration.urlCache == nil && configuration.urlCredentialStorage == nil)
    #expect(configuration.timeoutIntervalForRequest == 20)
  }
}

struct LAThumbnailTests {
  @Test func aPictureBecomesASmallJPEG() throws {
    let jpeg = try #require(LAThumbnail.jpeg(from: Pictures.png(width: 600, height: 400)))
    let size = try #require(Pictures.size(of: jpeg))
    #expect(size.width == 256 && size.height == 171)
    #expect(Pictures.type(of: jpeg) == "public.jpeg")
  }

  @Test func whatIsNotAPictureIsRefused() {
    #expect(LAThumbnail.jpeg(from: Data("not an image".utf8)) == nil)
    #expect(LAThumbnail.jpeg(from: Data()) == nil)
  }
}

struct LAPagesTests {
  let model = """
    {"id": 7, "name": "Event", "description": "<p>Film <b>grain</b></p>", "modelVersions": [
      {"id": 1, "availability": "Public", "baseModel": "SDXL 1.0", "trainedWords": [],
       "images": [{"type": "image", "url": "https://image.civitai.com/one.jpeg"}]},
      {"id": 2, "name": "Giallo", "availability": "Public", "baseModel": "Krea 2", "trainedWords": ["giallostyle", "film"],
       "images": [{"type": "video", "url": "https://image.civitai.com/v.mp4"}, {"type": "image", "url": "https://image.civitai.com/a.jpeg"}]}
    ]}
    """

  func page(_ json: String, version: Int?) -> Result<LAPage, LAFetchError> {
    do throws(LAFetchError) {
      return .success(try LACivitai.page(json: Data(json.utf8), version: version))
    } catch {
      return .failure(error)
    }
  }

  @Test func theVersionOfTheLinkIsRead() throws {
    let read = try page(model, version: 2).get()
    #expect(read.text == "Film grain\nVersion: Giallo\nBase model: Krea 2\nTrigger words: giallostyle, film")
    #expect(read.imageURL?.absoluteString == "https://image.civitai.com/a.jpeg")
  }

  @Test func withoutAVersionTheFirstOneIsRead() throws {
    let read = try page(model, version: nil).get()
    #expect(read.text == "Film grain\nBase model: SDXL 1.0")
    #expect(read.imageURL?.absoluteString == "https://image.civitai.com/one.jpeg")
  }

  @Test func aVersionThatIsNotThereFallsBackToTheFirst() throws {
    #expect(try page(model, version: 99).get().imageURL?.absoluteString == "https://image.civitai.com/one.jpeg")
  }

  @Test func aPageThatIsNotPublicNeedsAccess() {
    let early = #"{"description":"x","modelVersions":[{"id":1,"availability":"EarlyAccess","images":[]}]}"#
    #expect(page(early, version: nil) == .failure(.needsAccess))
  }

  @Test func anAnswerOfAnotherShapeIsUnreadable() {
    for json in ["{}", "\"x\"", "x", #"{"modelVersions":[]}"#, #"{"modelVersions":5}"#] {
      #expect(page(json, version: nil) == .failure(.unreadable), "\(json)")
    }
  }

  @Test func aPictureOnAnotherHostIsLeftOut() throws {
    let json = #"{"description":"d","modelVersions":[{"id":1,"images":[{"type":"image","url":"https://example.com/a.jpg"},{"type":"image","url":"not a url"}]}]}"#
    let read = try page(json, version: nil).get()
    #expect(read.imageURL == nil && read.text == "d")
  }

  @Test func theSearchAcceptsOnlyTheSameName() {
    let results = #"{"items":[{"id":1,"name":"K2 Girls"},{"id":2,"name":"Radiance Chrome Voluptuous"},{"id":3,"name":"Radiance"}]}"#
    #expect(LACivitai.match(json: Data(results.utf8), name: "Radiance Chrome Voluptuous v1.0") == 2)
    #expect(LACivitai.match(json: Data(results.utf8), name: "Kuniyoshi") == nil)
    #expect(LACivitai.match(json: Data(#"{"items":[]}"#.utf8), name: "x") == nil)
    #expect(LACivitai.match(json: Data("broken".utf8), name: "x") == nil)
  }

  @Test func theAddressesOfCivitai() {
    #expect(LACivitai.modelURL(7).absoluteString == "https://civitai.com/api/v1/models/7")
    let search = LACivitai.searchURL("a b&c").absoluteString
    #expect(search.hasPrefix("https://civitai.com/api/v1/models?"))
    #expect(search.contains("query=a%20b%26c") && search.contains("types=LORA") && search.contains("nsfw=true") && search.contains("limit=10"))
  }

  func hf(api: String, readme: String) -> LAPage {
    LAHuggingFace.page(api: Data(api.utf8), readme: readme, repo: "A/B")
  }

  @Test func huggingFaceTakesTheWidgetPictureFirst() {
    let api = #"{"cardData":{"widget":[{"text":"x"},{"output":{"url":"https://huggingface.co/A/B/resolve/main/images/w.png"}}]},"siblings":[{"rfilename":"images/0.png"}]}"#
    #expect(hf(api: api, readme: "<img src=\"./images/poster.jpeg\">").imageURL?.absoluteString == "https://huggingface.co/A/B/resolve/main/images/w.png")
    let relative = #"{"cardData":{"widget":[{"output":{"url":"images/rel one.png"}}]}}"#
    #expect(hf(api: relative, readme: "").imageURL?.absoluteString == "https://huggingface.co/A/B/resolve/main/images/rel%20one.png")
  }

  @Test func thenThePictureOfTheReadmeThenTheFirstPictureFile() {
    let files = #"{"siblings":[{"rfilename":"README.md"},{"rfilename":"lora.safetensors"},{"rfilename":"images/0.png"}]}"#
    #expect(
      hf(api: files, readme: "text ![badge](https://img.shields.io/x.svg) <img src=\"./images/poster.jpeg\">").imageURL?.absoluteString
        == "https://huggingface.co/A/B/resolve/main/images/poster.jpeg")
    #expect(hf(api: files, readme: "![a](pics/a.webp)").imageURL?.absoluteString == "https://huggingface.co/A/B/resolve/main/pics/a.webp")
    #expect(hf(api: files, readme: "no pictures").imageURL?.absoluteString == "https://huggingface.co/A/B/resolve/main/images/0.png")
  }

  @Test func aRepositoryWithoutPicturesHasNone() {
    let page = hf(api: #"{"siblings":[{"rfilename":"lora.safetensors"}]}"#, readme: "---\nlicense: mit\n---\n# Title\n<b>Bold</b> text")
    #expect(page.imageURL == nil)
    #expect(page.text == "# Title Bold text")
    #expect(hf(api: "broken", readme: "t").imageURL == nil)
  }

  @Test func theAddressesOfHuggingFace() {
    #expect(LAHuggingFace.apiURL(repo: "A/B").absoluteString == "https://huggingface.co/api/models/A/B")
    #expect(LAHuggingFace.readmeURL(repo: "A/B").absoluteString == "https://huggingface.co/A/B/raw/main/README.md")
  }
}

@MainActor
struct LAImporterTests {
  let store = LAStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("la-import-\(UUID().uuidString)", isDirectory: true))
  let fetcher = FakeFetcher()
  let link = LALink.civitai(model: 7, version: nil)
  let image = URL(string: "https://image.civitai.com/a.jpeg")!
  var importer: LAImporter { LAImporter(fetcher: fetcher, store: store) }

  func servePage(text: String = "Film grain look", withImage: Bool = true) {
    let images = withImage ? #"[{"type":"image","url":"https://image.civitai.com/a.jpeg"}]"# : "[]"
    fetcher.set(LACivitai.modelURL(7), text: #"{"description":"<p>\#(text)</p>","modelVersions":[{"id":1,"images":\#(images)}]}"#)
    fetcher.set(image, .success(Pictures.png()))
  }

  @Test func emptyNotesTakeTheBeginningOfThePage() async {
    servePage(text: String(repeating: "parola ", count: 200))
    #expect(await importer.importPage(link, for: "a.ckpt", notes: .keepUsers) == .imported(noImage: false))
    let entry = store.entry(for: "a.ckpt")
    #expect(entry.link == "https://civitai.com/models/7" && entry.rawNotes)
    #expect(entry.notes.count <= 401 && entry.notes.hasSuffix("…"))
    #expect(store.pageText(for: "a.ckpt")?.count == 1399)
    #expect(store.thumbnailURL(for: "a.ckpt").flatMap { try? Data(contentsOf: $0) }.flatMap(Pictures.size(of:))?.width == 256)
    #expect(!entry.manualThumbnail)
  }

  @Test func rawNotesAreReplacedByANewImport() async {
    servePage(text: "first")
    _ = await importer.importPage(link, for: "a.ckpt", notes: .keepUsers)
    servePage(text: "second")
    _ = await importer.importPage(link, for: "a.ckpt", notes: .keepUsers)
    #expect(store.entry(for: "a.ckpt").notes == "second" && store.pageText(for: "a.ckpt") == "second")
  }

  @Test func theUsersNotesAreKeptUnlessTheyAskToReplaceThem() async {
    servePage()
    store.setNotesByUser("mie", for: "a.ckpt")
    #expect(await importer.importPage(link, for: "a.ckpt", notes: .keepUsers) == .imported(noImage: false))
    #expect(store.entry(for: "a.ckpt").notes == "mie" && !store.entry(for: "a.ckpt").rawNotes)
    #expect(store.pageText(for: "a.ckpt") == nil)
    #expect(store.entry(for: "a.ckpt").thumbnail != nil)
    _ = await importer.importPage(link, for: "a.ckpt", notes: .replace)
    #expect(store.entry(for: "a.ckpt").notes == "Film grain look" && store.entry(for: "a.ckpt").rawNotes)
  }

  @Test func aThumbnailChosenByTheUserIsNotReplaced() async {
    servePage()
    store.setThumbnail(Data([9]), manual: true, for: "a.ckpt")
    let before = store.entry(for: "a.ckpt").thumbnail
    #expect(await importer.importPage(link, for: "a.ckpt", notes: .keepUsers) == .imported(noImage: false))
    #expect(store.entry(for: "a.ckpt").thumbnail == before && store.entry(for: "a.ckpt").manualThumbnail)
    #expect(!fetcher.requests.contains(image.absoluteString))
  }

  @Test func aPageWithoutAPictureLeavesTheThumbnailAsItWas() async {
    servePage(withImage: false)
    store.setThumbnail(Data([9]), manual: false, for: "a.ckpt")
    let before = store.entry(for: "a.ckpt").thumbnail
    #expect(await importer.importPage(link, for: "a.ckpt", notes: .keepUsers) == .imported(noImage: true))
    #expect(store.entry(for: "a.ckpt").thumbnail == before)
    #expect(store.entry(for: "a.ckpt").notes == "Film grain look")
  }

  @Test func aPictureThatIsNotAPictureIsNoPicture() async {
    servePage()
    fetcher.set(image, text: "<html>blocked</html>")
    #expect(await importer.importPage(link, for: "a.ckpt", notes: .keepUsers) == .imported(noImage: true))
    #expect(store.entry(for: "a.ckpt").thumbnail == nil)
  }

  @Test func aFailedPageLeavesTheEntryAloneButKeepsTheLink() async {
    store.setNotesByUser("mie", for: "a.ckpt")
    store.setThumbnail(Data([9]), manual: false, for: "a.ckpt")
    let before = store.entry(for: "a.ckpt")
    fetcher.set(LACivitai.modelURL(7), .failure(.notFound))
    #expect(await importer.importPage(link, for: "a.ckpt", notes: .replace) == .failed(.notFound))
    var expected = before
    expected.link = "https://civitai.com/models/7"
    #expect(store.entry(for: "a.ckpt") == expected)
  }

  @Test func huggingFaceIsReadFromItsTwoAddresses() async {
    let link = LALink.huggingFace(repo: "A/B")
    fetcher.set(LAHuggingFace.apiURL(repo: "A/B"), text: #"{"siblings":[{"rfilename":"images/0.png"}]}"#)
    fetcher.set(LAHuggingFace.readmeURL(repo: "A/B"), text: "---\na: b\n---\nA detail LoRA")
    fetcher.set(URL(string: "https://huggingface.co/A/B/resolve/main/images/0.png")!, .success(Pictures.png()))
    #expect(await importer.importPage(link, for: "h.ckpt", notes: .keepUsers) == .imported(noImage: false))
    #expect(store.entry(for: "h.ckpt").notes == "A detail LoRA" && store.entry(for: "h.ckpt").thumbnail != nil)
    #expect(store.entry(for: "h.ckpt").link == "https://huggingface.co/A/B")
  }
}
