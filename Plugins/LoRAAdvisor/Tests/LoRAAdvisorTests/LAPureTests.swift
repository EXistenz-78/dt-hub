import Foundation
import Testing

@testable import LoRAAdvisor

struct LALinkTests {
  @Test func civitaiLinks() {
    #expect(LALink.parse("https://civitai.com/models/123456") == .civitai(model: 123456, version: nil))
    let red = LALink.parse("https://civitai.red/models/2958510/event-horizon-or-krealoralab?modelVersionId=3351450")
    #expect(red == .civitai(model: 2_958_510, version: 3_351_450))
    #expect(red?.canonical == "https://civitai.com/models/2958510?modelVersionId=3351450")
    #expect(LALink.parse("  https://www.civitai.com/models/9?foo=1 \n") == .civitai(model: 9, version: nil))
    #expect(LALink.civitai(model: 9, version: nil).canonical == "https://civitai.com/models/9")
  }

  @Test func huggingFaceLinks() {
    let link = LALink.parse("https://huggingface.co/XLabs-AI/flux-RealismLora/tree/main")
    #expect(link == .huggingFace(repo: "XLabs-AI/flux-RealismLora"))
    #expect(link?.canonical == "https://huggingface.co/XLabs-AI/flux-RealismLora")
  }

  @Test(arguments: [
    "http://civitai.com/models/1", "https://civitai.com.evil.io/models/1", "https://user:pw@civitai.com/models/1",
    "https://civitai.com/user/x", "https://civitai.com/models/abc", "https://huggingface.co/solo",
    "https://example.com/models/1", "", "models/1", "https://huggingface.co/models/x",
  ])
  func otherAddressesAreRefused(text: String) {
    #expect(LALink.parse(text) == nil)
  }

  @Test func onlyTheKnownHostsOverHTTPSAreAllowed() {
    for text in ["https://civitai.com/x", "https://blobs-b2.civitai.com/x", "https://us.aws.cdn.hf.co/x", "https://huggingface.co/x"] {
      #expect(LAHosts.isAllowed(URL(string: text)!), "\(text)")
    }
    for text in [
      "http://civitai.com/x", "https://civitai.red/x", "https://evilcivitai.com/x", "https://civitai.com.evil.io/x",
      "https://a:b@civitai.com/x", "file:///etc/passwd", "https://hf.co.evil.io/x",
    ] {
      #expect(!LAHosts.isAllowed(URL(string: text)!), "\(text)")
    }
  }
}

struct LATextTests {
  @Test func htmlBecomesPlainText() {
    #expect(
      LAText.plain(fromHTML: "<p>Hello&nbsp;<b>world</b> &amp; more</p><br><ul><li>one</li><li>two</li></ul>")
        == "Hello world & more one two")
    #expect(LAText.plain(fromHTML: "a<script>alert(1)</script>b<style>p{}</style>c") == "a b c")
    #expect(LAText.plain(fromHTML: "x &lt;b&gt; &#39;y&#39; &quot;z&quot;") == "x <b> 'y' \"z\"")
  }

  @Test func theTextIsCutAtTheLimit() {
    #expect(LAText.plain(fromHTML: String(repeating: "word ", count: 2000)).count == 6000)
  }

  @Test func theFrontMatterGoes() {
    #expect(LAText.withoutFrontMatter("---\na: b\n---\n# Title\ntext") == "# Title\ntext")
    #expect(LAText.withoutFrontMatter("# Title\n---\ntext") == "# Title\n---\ntext")
  }

  @Test func anExcerptEndsAtAWord() {
    let long = String(repeating: "parola ", count: 150)
    let cut = LAText.excerpt(long)
    #expect(cut.count <= 401 && cut.hasSuffix("…") && !cut.hasSuffix(" …"))
    #expect(LAText.excerpt("breve testo") == "breve testo")
    #expect(LAText.firstLine("\n  prima \nseconda") == "prima")
  }
}

struct LANameTests {
  @Test func theQueryIsTheNameOrTheCleanedFile() {
    #expect(LAName.query(name: "Radiance Chrome Voluptuous", file: "x.ckpt") == "Radiance Chrome Voluptuous")
    #expect(LAName.query(name: "", file: "q21_radiancechrome_v1.0_lora_f16.ckpt") == "q21 radiancechrome v1.0")
    #expect(LAName.query(name: " ", file: "analog-film_lora_q8p.ckpt") == "analog film")
  }

  @Test func namesMatchWhateverTheCapitalsThePunctuationAndATrailingVersion() {
    #expect(LAName.matches(lora: "Radiance Chrome Voluptuous v1.0", result: "Radiance Chrome Voluptuous"))
    #expect(LAName.matches(lora: "Radiance Chrome Voluptuous", result: "Radiance Chrome Voluptuous V2"))
    #expect(LAName.matches(lora: "radiance-chrome_voluptuous", result: "Radiance Chrome Voluptuous"))
    #expect(LAName.matches(lora: "Più Luce", result: "piu luce"))
  }

  @Test func aNameThatOnlyLooksAlikeDoesNotMatch() {
    #expect(!LAName.matches(lora: "Radiance", result: "Radiance Chrome Voluptuous"))
    #expect(!LAName.matches(lora: "Kuniyoshi", result: "Utagawa Kuniyoshi [LoRA SDXL]"))
    #expect(!LAName.matches(lora: "", result: ""))
    #expect(!LAName.matches(lora: "v1.0", result: "v2"))
  }
}
