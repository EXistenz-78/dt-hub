import Foundation
import HubKit
import ImageIO

/// The prompt and the negative prompt as they sit in the fields.
public struct PromptPair: Equatable, Sendable {
  public var prompt: String
  public var negative: String

  public init(prompt: String, negative: String) {
    self.prompt = prompt
    self.negative = negative
  }
}

/// One message for the language model: text, images and options (system included).
public struct PromptRequest: Equatable, Sendable {
  public let prompt: String
  public let images: [URL]
  public let options: LanguageModelOptions
  /// The rows of a table of boxes the PUP must not change: the answer is reconciled with them before it is read.
  public var locked: [PupBoxRow]?
}

/// The pictures that go with Enhance Prompt: the start image of the Control tab and the Moodboard pictures that are on,
/// in the order of the thumbnails. Draw Things numbers them in that order (start first), so the prompt's "image 2" means
/// the same picture to the LLM.
public struct EnhanceImages: Equatable, Sendable {
  public var start: URL?
  public var references: [URL]

  public init(start: URL? = nil, references: [URL] = []) {
    self.start = start
    self.references = references
  }

  public var isEmpty: Bool { start == nil && references.isEmpty }
  /// The start image (when there is one), then the references.
  public var all: [URL] { (start.map { [$0] } ?? []) + references }
}

/// The messages the Enhance/Generate Prompt tools send to the language model (pure functions).
/// What a picture dropped on «Soggetto» or «Stile» is used for; the other half comes from the text of the prompt field.
public enum DescribeFocus: Equatable, Sendable {
  /// The picture gives the subject, the setting and the action; the text gives the style.
  case subject
  /// The picture gives the style; the text gives the subject, the setting and the action.
  case style
}

public enum PromptBrief {
  /// The system prompt for a family and a task: Rules, Family and the user's own, from the library.
  public static func system(family: String?, task: PromptTask = .enhance, library: PromptLibrary = .builtIn) -> String {
    library.system(task: task, family: family)
  }

  /// A language model's own system prompt, plus what the user added for the task (if anything).
  private static func ownSystem(_ system: String, task: PromptTask, library: PromptLibrary) -> String {
    library.ownSystemAddition(task: task).map { system + "\n\n" + $0 } ?? system
  }

  public static func enhance(_ current: PromptPair, family: String?, library: PromptLibrary = .builtIn) -> PromptRequest {
    var text =
      "Improve the prompt below for this model. Keep every element it describes and never contradict it; add concrete visual detail as the model notes ask. The prompt may be in any language.\n\nPrompt:\n"
      + current.prompt
    if library.family(family)?.negative == true, !current.negative.isEmpty {
      text += "\n\nNegative prompt:\n" + current.negative
    }
    return PromptRequest(prompt: text, images: [], options: options(system: system(family: family, task: .enhance, library: library)))
  }

  public static func describe(imageAt url: URL, family: String?, library: PromptLibrary = .builtIn) -> PromptRequest {
    PromptRequest(
      prompt:
        "Describe this image as a prompt for this model, following the model notes. Describe only what is visible; do not invent a story.",
      images: [url], options: options(system: system(family: family, task: .describe, library: library)))
  }

  /// The sentence that sets what to take from the picture, then the text of the prompt field if there is one.
  static func focusText(_ focus: DescribeFocus, userText: String) -> String {
    let sentence: String
    switch focus {
    case .subject:
      sentence =
        "Use the picture for ONLY the subject, the setting and the action; ignore its style (light, colours, medium, mood, rendering). If there is a user's text, take the style from the user's text. Write one single new prompt that merges the two."
    case .style:
      sentence =
        "Use the picture for ONLY the style (light, colours, medium, mood, rendering); ignore what it shows. If there is a user's text, take the subject, the setting and the action from the user's text. Write one single new prompt that merges the two."
    }
    let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? sentence : sentence + "\n\nUser's text:\n" + text
  }

  /// Generate Prompt from a picture dropped on «Soggetto» / «Stile»: the usual request, then the sentence for the focus.
  public static func describe(
    imageAt url: URL, current: PromptPair, family: String?, focus: DescribeFocus, library: PromptLibrary = .builtIn
  ) -> PromptRequest {
    let usual = describe(imageAt: url, family: family, library: library)
    return PromptRequest(
      prompt: usual.prompt + "\n\n" + focusText(focus, userText: current.prompt), images: usual.images,
      options: usual.options)
  }

  /// The same for an LLM with its own system prompt.
  public static func describe(
    imageAt url: URL, ownSystem: String, generation: LanguageModelProfile.Generation?, current: PromptPair,
    focus: DescribeFocus, library: PromptLibrary = .builtIn
  ) -> PromptRequest {
    let usual = describe(imageAt: url, ownSystem: ownSystem, generation: generation, library: library)
    return PromptRequest(
      prompt: usual.prompt + "\n\n" + focusText(focus, userText: current.prompt), images: usual.images,
      options: usual.options)
  }

  /// Enhance with an LLM that has its own system prompt: the user's text goes as it is (the model was made for
  /// exactly that), with the model's own sampling values and room to think.
  public static func enhance(
    _ current: PromptPair, ownSystem: String, generation: LanguageModelProfile.Generation?,
    library: PromptLibrary = .builtIn
  ) -> PromptRequest {
    PromptRequest(
      prompt: current.prompt, images: [],
      options: ownOptions(Self.ownSystem(ownSystem, task: .enhance, library: library), generation))
  }

  /// One line per picture, in sending order, numbered as Draw Things numbers them: the start image is 1 when there
  /// is one, and the Moodboard pictures follow; without a start image the first Moodboard picture is 1.
  public static func imageLabels(hasStart: Bool, references: Int) -> [String] {
    var labels: [String] = []
    if hasStart { labels.append("Image 1: the start image (the picture being edited).") }
    for index in 0..<max(references, 0) {
      labels.append("Image \(labels.count + 1): reference image \(index + 1).")
    }
    return labels
  }

  private static func imagesBlock(_ images: EnhanceImages) -> String? {
    guard !images.isEmpty else { return nil }
    let lines = imageLabels(hasStart: images.start != nil, references: images.references.count).map { "- " + $0 }
    return "Attached images:\n" + lines.joined(separator: "\n")
      + "\n\nThe prompt refers to these images. Look at them to make the description concrete and accurate, and keep every reference to an image (image 1, image 2…) exactly as written.\n\n"
  }

  /// Enhance with the pictures attached: the numbered list first, then the usual request.
  public static func enhance(
    _ current: PromptPair, family: String?, images: EnhanceImages, library: PromptLibrary = .builtIn
  ) -> PromptRequest {
    let usual = enhance(current, family: family, library: library)
    guard let block = imagesBlock(images) else { return usual }
    return PromptRequest(prompt: block + usual.prompt, images: images.all, options: usual.options)
  }

  /// Enhance with the pictures attached, for an LLM with its own system prompt.
  public static func enhance(
    _ current: PromptPair, ownSystem: String, generation: LanguageModelProfile.Generation?, images: EnhanceImages,
    library: PromptLibrary = .builtIn
  ) -> PromptRequest {
    let usual = enhance(current, ownSystem: ownSystem, generation: generation, library: library)
    guard let block = imagesBlock(images) else { return usual }
    return PromptRequest(prompt: block + usual.prompt, images: images.all, options: usual.options)
  }

  /// Generate with an LLM that has its own system prompt.
  public static func describe(
    imageAt url: URL, ownSystem: String, generation: LanguageModelProfile.Generation?, library: PromptLibrary = .builtIn
  ) -> PromptRequest {
    PromptRequest(
      prompt: "Describe this image as a prompt for an image-generation model.", images: [url],
      options: ownOptions(Self.ownSystem(ownSystem, task: .describe, library: library), generation))
  }

  // MARK: The official PUP (`system_prompts.json`)

  /// What the PUP is asked when Generate Prompt has no text to go on.
  static let pupDescribeRequest = "Describe this image as a detailed prompt to recreate it."

  /// The decoding of BFL's `pup.py`: greedy, top-p 0.95, top-k 20, 3584 tokens, no thinking; the presence penalty is 1.5 for a
  /// text-to-image request and 0 for an edit.
  private static func pupOptions(system: String, presencePenalty: Double) -> LanguageModelOptions {
    LanguageModelOptions(
      system: system, temperature: 0, topP: 0.95, topK: 20, presencePenalty: presencePenalty, maxTokens: 3584, thinking: false)
  }

  /// `I2I_SCAFFOLD[False]` of BFL's `pup.py`: the pictures go in the order they are attached.
  private static func pupScaffold(_ instruction: String) -> String {
    "Reference images follow in order (the first image, the second image, ...).\nUser request: \(instruction)\nOutput the caption."
  }

  /// Enhance with the PUP: `t2i` and the prompt as it is without pictures; `i2i` with the pictures (the start image first,
  /// then the references, as Draw Things numbers them, at most ten) and the prompt as the request. A prompt that ends with a table
  /// of boxes goes to `t2i_bbox` / `i2i_bbox` with the rows locked (the model's file has those prompts, or the usual way applies).
  public static func enhance(_ current: PromptPair, pup: LanguageModelProfile.Pup, images: EnhanceImages) -> PromptRequest {
    let attached = Array(images.all.prefix(10))
    if let found = PupBoxes.detect(current.prompt) {
      if attached.isEmpty, let system = pup.t2iBbox {
        return PromptRequest(
          prompt: PupBoxes.upsamplingInput(prompt: found.prompt, rows: found.rows), images: [],
          options: pupOptions(system: system, presencePenalty: 1.5), locked: found.rows)
      }
      if !attached.isEmpty, let system = pup.i2iBbox {
        return PromptRequest(
          prompt: PupBoxes.editScaffold(PupBoxes.upsamplingInput(prompt: found.prompt, rows: found.rows)), images: attached,
          options: pupOptions(system: system, presencePenalty: 0), locked: found.rows)
      }
    }
    guard !attached.isEmpty else {
      return PromptRequest(prompt: current.prompt, images: [], options: pupOptions(system: pup.t2i, presencePenalty: 1.5))
    }
    return PromptRequest(prompt: pupScaffold(current.prompt), images: attached, options: pupOptions(system: pup.i2i, presencePenalty: 0))
  }

  /// Generate with the PUP: always `i2i`; the text in the field is the request, or a default one when it is empty.
  /// With a `focus` (a picture dropped on «Soggetto» / «Stile») the request is the default one plus the sentence for the
  /// focus and the text of the field.
  public static func describe(
    imageAt url: URL, current: PromptPair, pup: LanguageModelProfile.Pup, focus: DescribeFocus? = nil
  ) -> PromptRequest {
    let text = current.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let request =
      focus.map { pupDescribeRequest + " " + focusText($0, userText: text) } ?? (text.isEmpty ? pupDescribeRequest : text)
    return PromptRequest(
      prompt: pupScaffold(request), images: [url], options: pupOptions(system: pup.i2i, presencePenalty: 0))
  }

  // MARK: A prompt expander with its own request (`prompt/t2i/`, `prompt/edit/`)

  /// What the expander is asked by Generate Prompt: the text-to-image request, with the picture attached. (The edit
  /// prompt would describe the picture as a change to «Picture 1», which means nothing without that picture.)
  static let expanderDescribeRequest =
    "Recreate the attached image exactly: describe everything visible in it as the image to generate."

  /// Python's `template.format(argument)` for a template with one `{}`: `{{` and `}}` are braces, the first `{}` is the
  /// argument (as it is), any other `{}` is empty.
  static func pythonFormat(_ template: String, _ argument: String) -> String {
    var result = ""
    var used = false
    var index = template.startIndex
    while index < template.endIndex {
      let rest = template[index...]
      if rest.hasPrefix("{{") || rest.hasPrefix("}}") {
        result.append(template[index])
        index = template.index(index, offsetBy: 2)
      } else if rest.hasPrefix("{}") {
        if !used { result += argument }
        used = true
        index = template.index(index, offsetBy: 2)
      } else {
        result.append(template[index])
        index = template.index(after: index)
      }
    }
    return result
  }

  /// A width and a height as the lowest `W:H`; nil when either is not positive.
  static func reducedRatio(width: Int, height: Int) -> String? {
    guard width > 0, height > 0 else { return nil }
    var (a, b) = (width, height)
    while b != 0 { (a, b) = (b, a % b) }
    return "\(width / a):\(height / a)"
  }

  /// The display ratio of a picture file (EXIF orientation applied), as the lowest `W:H`.
  public static func aspectRatio(of url: URL) -> String? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
    else { return nil }
    // Orientations 5…8 lie on their side.
    let turned = ((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) >= 5
    return turned ? reducedRatio(width: height, height: width) : reducedRatio(width: width, height: height)
  }

  private static func expanderOptions(_ expander: LanguageModelProfile.Expander, system: String?) -> LanguageModelOptions {
    LanguageModelOptions(
      system: system, temperature: expander.temperature, topP: expander.topP, topK: expander.topK,
      maxTokens: expander.maxTokens, thinking: true)
  }

  /// Enhance with an expander. Without pictures: its system prompt and its template filled with the prompt. With pictures
  /// (the start image first, then the references): no system prompt, and one message that opens with the fixed edit
  /// prompt, then says how many pictures there are and the label and ratio of each, then gives the prompt as the editing
  /// instruction; the ratio of the result is left to the model. (The release puts each label right before its picture; the
  /// app's language models take one text and the pictures, in order.)
  public static func enhance(
    _ current: PromptPair, expander: LanguageModelProfile.Expander, images: EnhanceImages,
    ratio: (URL) -> String? = PromptBrief.aspectRatio
  ) -> PromptRequest {
    guard let editTask = expander.editTask, !images.isEmpty else {
      return PromptRequest(
        prompt: pythonFormat(expander.t2iTask, current.prompt), images: [],
        options: expanderOptions(expander, system: expander.t2iSystem))
    }
    let attached = images.all
    var parts = [
      editTask,
      "Reference Image Count:\n\(attached.count) input image(s), labeled <Picture 1> through <Picture \(attached.count)>.",
    ]
    for (index, url) in attached.enumerated() {
      let metadata = ratio(url).map { "aspect_ratio \($0)" } ?? "aspect_ratio unavailable"
      parts.append("Reference Media:\n- <Picture \(index + 1)> [\(metadata)]")
    }
    let instruction =
      (try? JSONSerialization.data(withJSONObject: current.prompt, options: [.fragmentsAllowed, .withoutEscapingSlashes]))
      .map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    parts.append(
      "\nUser Editing Instruction (JSON string):\n\(instruction)\n\nUser Aspect Ratio Selection:\nadaptive\n\n"
        + "Apply the instructions above to the supplied inputs and reference images. Output only the required two-field JSON object."
    )
    return PromptRequest(
      prompt: parts.joined(separator: "\n\n"), images: attached, options: expanderOptions(expander, system: nil))
  }

  /// Generate with an expander: the text-to-image request with the picture attached; with a `focus`, the sentence for it
  /// and the text of the field follow.
  public static func describe(
    imageAt url: URL, current: PromptPair, expander: LanguageModelProfile.Expander, focus: DescribeFocus? = nil
  ) -> PromptRequest {
    let request = focus.map { expanderDescribeRequest + " " + focusText($0, userText: current.prompt) } ?? expanderDescribeRequest
    return PromptRequest(
      prompt: pythonFormat(expander.t2iTask, request), images: [url],
      options: expanderOptions(expander, system: expander.t2iSystem))
  }

  private static func ownOptions(_ system: String, _ generation: LanguageModelProfile.Generation?) -> LanguageModelOptions {
    LanguageModelOptions(
      system: system, temperature: generation?.temperature, topP: generation?.topP, topK: generation?.topK,
      maxTokens: 16384, thinking: true)
  }

  /// The prompt (and negative prompt) in an answer. Same logic as Prompt Master's `AnswerParser`, copied because the
  /// plug-in is a separate package. Reasoning blocks (`<think>…</think>`) and code fences go; a JSON object gives its
  /// `prompt` (or `rewritten_prompt`, `positive_prompt`, `expanded_caption`) and `negative` (or `negative_prompt`); anything else, a
  /// malformed JSON included, is the prompt itself. `negative` is "" when the answer has none; nil when nothing is left.
  public static func parse(_ raw: String) -> PromptPair? {
    var text = withoutThinking(raw)
    text = withoutFences(text).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
      let object = (try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))) as? [String: Any],
      let prompt = ["prompt", "rewritten_prompt", "positive_prompt", "expanded_caption"].lazy.compactMap({ clean(object[$0]) }).first
    {
      let negative = ["negative", "negative_prompt"].lazy.compactMap { clean(object[$0]) }.first
      return PromptPair(prompt: prompt, negative: negative ?? "")
    }
    return PromptPair(prompt: unquoted(text), negative: "")
  }

  private static func clean(_ value: Any?) -> String? {
    guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
      return nil
    }
    return text
  }

  /// Everything after the last `</think>`; a `<think>` that never closes takes the rest of the text with it.
  private static func withoutThinking(_ text: String) -> String {
    var result = text
    if let close = result.range(of: "</think>", options: .backwards) {
      result = String(result[close.upperBound...])
    }
    if let open = result.range(of: "<think>") { result = String(result[..<open.lowerBound]) }
    return result
  }

  /// The inside of a fenced block (```json … ```), when the text is one.
  private static func withoutFences(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```"), let firstBreak = trimmed.firstIndex(of: "\n") else { return text }
    var inside = String(trimmed[trimmed.index(after: firstBreak)...])
    if let close = inside.range(of: "```", options: .backwards) { inside = String(inside[..<close.lowerBound]) }
    return inside
  }

  /// A prompt wrapped in one pair of quotation marks loses them.
  private static func unquoted(_ text: String) -> String {
    for (open, close) in [("\"", "\""), ("“", "”")]
    where text.count > 1 && text.hasPrefix(open) && text.hasSuffix(close) {
      let inside = String(text.dropFirst().dropLast())
      if !inside.contains(open) { return inside.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return text
  }

  /// A model that reasons by default would spend the tokens on its reasoning: thinking is off.
  private static func options(system: String) -> LanguageModelOptions {
    LanguageModelOptions(system: system, maxTokens: 2048, thinking: false)
  }
}
