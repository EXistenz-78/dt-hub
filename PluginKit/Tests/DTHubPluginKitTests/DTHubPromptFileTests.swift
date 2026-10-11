import Testing

@testable import DTHubPluginKit

struct DTHubPromptFileTests {
  @Test func headerAndBodyAreSplit() {
    let file = DTHubPromptFile.parse("---\nlabel: A\nversion: 3\n---\nTesto")
    #expect(file.header == ["label": "A", "version": "3"])
    #expect(file.body == "Testo")
    #expect(file.version == 3 && file.isValid)
  }

  @Test func noHeaderMeansTheWholeTextIsTheBody() {
    let file = DTHubPromptFile.parse("Solo testo\nsu due righe")
    #expect(file.header.isEmpty && file.body == "Solo testo\nsu due righe" && file.isValid && file.version == 0)
  }

  @Test func crlfAndBomAreAccepted() {
    let file = DTHubPromptFile.parse("\u{FEFF}---\r\nlabel: A\r\n---\r\nRiga uno\r\nRiga due")
    #expect(file.header == ["label": "A"] && file.isValid)
    #expect(file.body == "Riga uno\nRiga due")
  }

  @Test func anUnclosedHeaderIsInvalid() {
    let text = "---\nlabel: A\nTesto"
    let file = DTHubPromptFile.parse(text)
    #expect(!file.isValid && file.header.isEmpty && file.body == text)
  }

  @Test func aHeaderLineWithoutColonIsInvalid() {
    let file = DTHubPromptFile.parse("---\nlabel A\n---\nTesto")
    #expect(!file.isValid)
  }

  @Test func valuesKeepTheirColons() {
    #expect(DTHubPromptFile.parse("---\nlabel: A: B\n---\nx").header["label"] == "A: B")
  }

  @Test func resolvedReplacesOnlyTheNamedPlaceholders() {
    let file = DTHubPromptFile(body: #"{"prompt": "x"} {words} {other}"#)
    #expect(file.resolved(["words": "300-450"]) == #"{"prompt": "x"} 300-450 {other}"#)
  }

  @Test func serializedParsesBackToTheSame() {
    let file = DTHubPromptFile(header: ["version": "2", "label": "A"], body: "Corpo\nsu due righe")
    #expect(DTHubPromptFile.parse(file.serialized()) == file)
    #expect(file.serialized().hasPrefix("---\nlabel: A\nversion: 2\n---\n"))
  }
}
