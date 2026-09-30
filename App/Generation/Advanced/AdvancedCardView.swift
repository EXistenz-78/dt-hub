import HubCore
import HubKit
import SwiftUI

/// One Advanced card: its title and icon, and the rows of the fields the chosen model uses.
struct AdvancedCardView: View {
  let card: AdvancedCard
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection

  private var model: CatalogModel? { controller.selectedModel(in: connection) }
  private var catalog: ModelCatalog { connection.monitor.catalog }
  private var advanced: Binding<AdvancedParameters> { $controller.parameters.advanced }

  private func shows(_ field: AdvancedField) -> Bool {
    field.isShown(for: model, sampler: controller.parameters.sampler)
  }

  var body: some View {
    DSCollapsibleCard(title, systemImage: systemImage, isExpanded: controller.cards.binding("advanced.\(card.rawValue)")) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        switch card {
        case .refiner: refinerRows
        case .hiresFix: hiresFixRows
        case .upscale: upscaleRows
        case .guidance: guidanceRows
        case .textEncoder: textEncoderRows
        case .sdxl: sdxlRows
        case .performance: performanceRows
        case .output: outputRows
        }
      }
    }
  }

  private var title: String {
    switch card {
    case .refiner: String(localized: "advanced.card.refiner")
    case .hiresFix: String(localized: "advanced.card.hiresFix")
    case .upscale: String(localized: "advanced.card.upscale")
    case .guidance: String(localized: "advanced.card.guidance")
    case .textEncoder: String(localized: "advanced.card.textEncoder")
    case .sdxl: String(localized: "advanced.card.sdxl")
    case .performance: String(localized: "advanced.card.performance")
    case .output: String(localized: "advanced.card.output")
    }
  }

  private var systemImage: String {
    switch card {
    case .refiner: "wand.and.stars"
    case .hiresFix: "arrow.up.left.and.arrow.down.right"
    case .upscale: "arrow.up.forward.app"
    case .guidance: "scope"
    case .textEncoder: "character.cursor.ibeam"
    case .sdxl: "square.resize"
    case .performance: "speedometer"
    case .output: "paintpalette"
    }
  }

  // MARK: Refiner

  @ViewBuilder private var refinerRows: some View {
    CardRow(label: String(localized: "advanced.refiner.model")) {
      FilePicker(
        label: String(localized: "advanced.refiner.model"), selection: advanced.refinerModel,
        options: catalog.models.map { ($0.file, $0.name) })
    }
    if !advanced.wrappedValue.refinerModel.isEmpty {
      CardRow(label: String(localized: "advanced.refiner.start")) {
        DecimalField(
          label: String(localized: "advanced.refiner.start"), value: advanced.refinerStart,
          range: AdvancedParameters.unitRange, step: 0.05, fractionDigits: 2)
      }
    }
  }

  // MARK: Hires fix

  @ViewBuilder private var hiresFixRows: some View {
    CardRow(label: String(localized: "advanced.field.hiresFix")) {
      Toggle(isOn: advanced.hiresFix) { Text("advanced.enabled") }
        .toggleStyle(DSCheckboxToggleStyle())
    }
    if advanced.wrappedValue.hiresFix {
      CardRow(label: String(localized: "advanced.hiresFix.start")) {
        SizePair(width: advanced.hiresFixWidth, height: advanced.hiresFixHeight, range: GenerationParameters.sizeRange.upperBound)
      }
      Text("advanced.autoSizeHint")
        .font(.caption)
        .foregroundStyle(.secondary)
      CardRow(label: String(localized: "advanced.hiresFix.strength")) {
        DecimalField(
          label: String(localized: "advanced.hiresFix.strength"), value: advanced.hiresFixStrength,
          range: AdvancedParameters.unitRange, step: 0.05, fractionDigits: 2)
      }
    }
  }

  // MARK: Upscaler and face restoration

  @ViewBuilder private var upscaleRows: some View {
    CardRow(label: String(localized: "advanced.field.upscaler")) {
      FilePicker(
        label: String(localized: "advanced.field.upscaler"), selection: advanced.upscaler,
        options: catalog.upscalers.map { ($0, Self.displayName($0)) })
    }
    if !advanced.wrappedValue.upscaler.isEmpty {
      CardRow(label: String(localized: "advanced.upscaler.factor")) {
        Picker(selection: advanced.upscalerScaleFactor) {
          Text("advanced.upscaler.factor.auto").tag(0)
          Text(verbatim: "2×").tag(2)
          Text(verbatim: "4×").tag(4)
        } label: {
          EmptyView()
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(String(localized: "advanced.upscaler.factor"))
      }
    }
    CardRow(label: String(localized: "advanced.field.faceRestoration")) {
      FilePicker(
        label: String(localized: "advanced.field.faceRestoration"), selection: advanced.faceRestoration,
        options: catalog.faceRestorers.map { ($0, Self.displayName($0)) })
    }
  }

  /// "realesrgan_x4plus_f16.ckpt" → "realesrgan_x4plus".
  static func displayName(_ file: String) -> String {
    var name = file
    for suffix in [".ckpt", "_f16", "_q8p", "_q6p"] where name.hasSuffix(suffix) {
      name.removeLast(suffix.count)
    }
    return name
  }

  // MARK: Extra guidance

  @ViewBuilder private var guidanceRows: some View {
    if shows(.guidanceEmbed) {
      CardRow(label: String(localized: "advanced.field.guidanceEmbed")) {
        Toggle(isOn: advanced.speedUpWithGuidanceEmbed) { Text("advanced.guidance.speedUp") }
          .toggleStyle(DSCheckboxToggleStyle())
      } control: {
        DecimalField(
          label: String(localized: "advanced.field.guidanceEmbed"), value: advanced.guidanceEmbed,
          range: AdvancedParameters.guidanceEmbedRange, step: 0.5)
      }
    }
    CardRow(label: String(localized: "advanced.field.sharpness")) {
      DecimalField(
        label: String(localized: "advanced.field.sharpness"), value: advanced.sharpness,
        range: AdvancedParameters.sharpnessRange, step: 0.5)
    }
    if shows(.stochasticSamplingGamma) {
      CardRow(label: String(localized: "advanced.field.stochasticSamplingGamma")) {
        DecimalField(
          label: String(localized: "advanced.field.stochasticSamplingGamma"), value: advanced.stochasticSamplingGamma,
          range: AdvancedParameters.unitRange, step: 0.05, fractionDigits: 2)
      }
    }
  }

  // MARK: Text encoders

  @ViewBuilder private var textEncoderRows: some View {
    if shows(.clipSkip) {
      CardRow(label: String(localized: "advanced.field.clipSkip")) {
        IntField(label: String(localized: "advanced.field.clipSkip"), value: advanced.clipSkip, range: AdvancedParameters.clipSkipRange)
      }
    }
    if shows(.t5TextEncoder) {
      Toggle(isOn: advanced.t5TextEncoder) { Text("advanced.field.t5TextEncoder") }
        .toggleStyle(DSCheckboxToggleStyle())
    }
    if shows(.separateClipL) {
      SeparateText(
        title: String(localized: "advanced.field.separateClipL"), isOn: advanced.separateClipL, text: advanced.clipLText)
    }
    if shows(.separateOpenClipG) {
      SeparateText(
        title: String(localized: "advanced.field.separateOpenClipG"), isOn: advanced.separateOpenClipG,
        text: advanced.openClipGText)
    }
    if shows(.separateT5) {
      SeparateText(title: String(localized: "advanced.field.separateT5"), isOn: advanced.separateT5, text: advanced.t5Text)
    }
    if shows(.zeroNegativePrompt) {
      Toggle(isOn: advanced.zeroNegativePrompt) { Text("advanced.field.zeroNegativePrompt") }
        .toggleStyle(DSCheckboxToggleStyle())
    }
  }

  // MARK: SDXL conditioning

  @ViewBuilder private var sdxlRows: some View {
    CardRow(label: String(localized: "advanced.sdxl.aesthetic")) {
      DecimalField(
        label: String(localized: "advanced.sdxl.aesthetic"), value: advanced.aestheticScore,
        range: AdvancedParameters.aestheticRange, step: 0.5)
    }
    CardRow(label: String(localized: "advanced.sdxl.negativeAesthetic")) {
      DecimalField(
        label: String(localized: "advanced.sdxl.negativeAesthetic"), value: advanced.negativeAestheticScore,
        range: AdvancedParameters.aestheticRange, step: 0.5)
    }
    CardRow(label: String(localized: "advanced.sdxl.crop")) {
      SizePair(
        width: advanced.cropLeft, height: advanced.cropTop, range: AdvancedParameters.conditioningRange.upperBound,
        commit: AdvancedParameters.crop)
    }
    CardRow(label: String(localized: "advanced.sdxl.original")) {
      SizePair(
        width: advanced.originalWidth, height: advanced.originalHeight,
        range: AdvancedParameters.conditioningRange.upperBound, commit: AdvancedParameters.conditioningSize)
    }
    CardRow(label: String(localized: "advanced.sdxl.target")) {
      SizePair(
        width: advanced.targetWidth, height: advanced.targetHeight,
        range: AdvancedParameters.conditioningRange.upperBound, commit: AdvancedParameters.conditioningSize)
    }
    CardRow(label: String(localized: "advanced.sdxl.negativeOriginal")) {
      SizePair(
        width: advanced.negativeOriginalWidth, height: advanced.negativeOriginalHeight,
        range: AdvancedParameters.conditioningRange.upperBound, commit: AdvancedParameters.conditioningSize)
    }
    Text("advanced.autoSizeHint")
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  // MARK: Performance

  @ViewBuilder private var performanceRows: some View {
    Toggle(isOn: advanced.tiledDecoding) { Text("advanced.field.tiledDecoding") }
      .toggleStyle(DSCheckboxToggleStyle())
    if advanced.wrappedValue.tiledDecoding {
      TileRows(width: advanced.decodingTileWidth, height: advanced.decodingTileHeight, overlap: advanced.decodingTileOverlap)
    }
    Toggle(isOn: advanced.tiledDiffusion) { Text("advanced.field.tiledDiffusion") }
      .toggleStyle(DSCheckboxToggleStyle())
    if advanced.wrappedValue.tiledDiffusion {
      TileRows(width: advanced.diffusionTileWidth, height: advanced.diffusionTileHeight, overlap: advanced.diffusionTileOverlap)
    }
    if shows(.teaCache) {
      Toggle(isOn: advanced.teaCache) { Text("advanced.field.teaCache") }
        .toggleStyle(DSCheckboxToggleStyle())
      if advanced.wrappedValue.teaCache {
        CardRow(label: String(localized: "advanced.teaCache.start")) {
          IntField(label: String(localized: "advanced.teaCache.start"), value: advanced.teaCacheStart, range: AdvancedParameters.teaCacheStepRange)
        }
        CardRow(label: String(localized: "advanced.teaCache.end")) {
          IntField(label: String(localized: "advanced.teaCache.end"), value: advanced.teaCacheEnd, range: AdvancedParameters.teaCacheEndRange)
        }
        CardRow(label: String(localized: "advanced.teaCache.threshold")) {
          DecimalField(
            label: String(localized: "advanced.teaCache.threshold"), value: advanced.teaCacheThreshold,
            range: AdvancedParameters.unitRange, step: 0.01, fractionDigits: 2)
        }
        CardRow(label: String(localized: "advanced.teaCache.maxSkip")) {
          IntField(label: String(localized: "advanced.teaCache.maxSkip"), value: advanced.teaCacheMaxSkipSteps, range: AdvancedParameters.teaCacheSkipRange)
        }
      }
    }
  }

  // MARK: Output

  @ViewBuilder private var outputRows: some View {
    Toggle(isOn: advanced.colorCalibration) { Text("advanced.field.colorCalibration") }
      .toggleStyle(DSCheckboxToggleStyle())
    CardRow(label: String(localized: "advanced.field.compressionArtifacts")) {
      Picker(selection: advanced.compressionArtifacts) {
        Text("advanced.compression.none").tag(CompressionArtifacts.none)
        Text(verbatim: "H.264").tag(CompressionArtifacts.h264)
        Text(verbatim: "H.265").tag(CompressionArtifacts.h265)
        Text(verbatim: "JPEG").tag(CompressionArtifacts.jpeg)
      } label: {
        EmptyView()
      }
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel(String(localized: "advanced.field.compressionArtifacts"))
    }
    if advanced.wrappedValue.compressionArtifacts != .none {
      CardRow(label: String(localized: "advanced.compression.quality")) {
        DecimalField(
          label: String(localized: "advanced.compression.quality"), value: advanced.compressionQuality,
          range: AdvancedParameters.qualityRange, step: 1)
      }
    }
  }
}

/// A file chooser with "None" first; a chosen file the server no longer lists stays shown.
private struct FilePicker: View {
  let label: String
  @Binding var selection: String
  let options: [(file: String, name: String)]

  var body: some View {
    Picker(selection: $selection) {
      Text("advanced.none").tag("")
      ForEach(options, id: \.file) { option in
        Text(verbatim: option.name).tag(option.file)
      }
      if !selection.isEmpty, !options.contains(where: { $0.file == selection }) {
        Text(verbatim: selection).tag(selection)
      }
    } label: {
      EmptyView()
    }
    .labelsHidden()
    .fixedSize()
    .accessibilityLabel(label)
  }
}

/// Width × height, each corrected by `commit` when editing ends (Hires fix: multiples of 64
/// up to 2048, 0 = automatic; SDXL sizes: multiples of 64 up to 8192; SDXL crop: any pixel).
private struct SizePair: View {
  @Binding var width: Int
  @Binding var height: Int
  let range: Int
  var commit: (Int) -> Int = { $0 == 0 ? 0 : GenerationParameters.snap(Double($0)) }

  var body: some View {
    HStack(spacing: 4) {
      IntField(
        label: String(localized: "card.dimensions.width"), value: $width, range: 0...range, step: 64,
        commit: commit)
      Text(verbatim: "×").foregroundStyle(.secondary)
      IntField(
        label: String(localized: "card.dimensions.height"), value: $height, range: 0...range, step: 64,
        commit: commit)
    }
  }
}

/// Tile width × height and overlap, for tiled decoding and diffusion.
private struct TileRows: View {
  @Binding var width: Int
  @Binding var height: Int
  @Binding var overlap: Int

  var body: some View {
    CardRow(label: String(localized: "advanced.tile.size")) {
      HStack(spacing: 4) {
        IntField(
          label: String(localized: "card.dimensions.width"), value: $width, range: AdvancedParameters.tileRange, step: 64,
          commit: { GenerationParameters.snap(Double($0)) })
        Text(verbatim: "×").foregroundStyle(.secondary)
        IntField(
          label: String(localized: "card.dimensions.height"), value: $height, range: AdvancedParameters.tileRange, step: 64,
          commit: { GenerationParameters.snap(Double($0)) })
      }
    }
    CardRow(label: String(localized: "advanced.tile.overlap")) {
      IntField(label: String(localized: "advanced.tile.overlap"), value: $overlap, range: AdvancedParameters.overlapRange, step: 64)
    }
  }
}

/// A checkbox for a separate encoder text and, when on, its text box.
private struct SeparateText: View {
  let title: String
  @Binding var isOn: Bool
  @Binding var text: String

  var body: some View {
    Toggle(isOn: $isOn) { Text(title) }
      .toggleStyle(DSCheckboxToggleStyle())
    if isOn {
      TextField(title, text: $text, prompt: Text("advanced.separateText.placeholder"), axis: .vertical)
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...5)
    }
  }
}
