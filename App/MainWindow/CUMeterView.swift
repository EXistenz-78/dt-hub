import HubCore
import HubKit
import SwiftUI

/// The CU meter, next to the DT+ button: the compute units the next RUN needs against the limit per RUN, as
/// "32,4k / 40k" with a thin bar (green, amber from 90 %, red over the limit). A click opens the details: the exact
/// value, the heaviest pass of a pipeline, the boosts needed. It only advises: the cloud decides (spec §5).
struct CUMeterView: View {
  let connection: DrawThingsConnection
  let generation: GenerationController
  @State private var showDetails = false
  @Environment(\.locale) private var locale

  private struct Snapshot {
    var passes: [CUPass]
    var readings: [CUPassReading]
    var presentation: CUMeterPresentation
    /// The heaviest estimate with no Moodboard picture, when pictures count for it.
    var withoutMoodboard: Int?
  }

  private func snapshot() -> Snapshot {
    let passes = generation.cuPasses(in: connection)
    let limits = connection.cuLimits
    let provider = connection.computeUnits
    let readings = passes.map { pass in
      CUPassReading(
        title: pass.title,
        reading: pass.inputs.flatMap { provider.estimate($0) }.map { CUReading(cu: $0, limits: limits) })
    }
    let presentation = CUMeterPresentation(passes: readings, locale: locale)
    var withoutMoodboard: Int?
    if let heaviest = presentation.heaviest?.reading,
      passes.contains(where: { ($0.inputs?.referenceImages ?? 0) > 0 })
    {
      let bare = passes.compactMap { pass -> Int? in
        guard var inputs = pass.inputs else { return nil }
        inputs.referenceImages = 0
        return provider.estimate(inputs)
      }.max()
      if let bare, bare != heaviest.cu { withoutMoodboard = bare }
    }
    return Snapshot(passes: passes, readings: readings, presentation: presentation, withoutMoodboard: withoutMoodboard)
  }

  private func color(for state: CUState?) -> Color {
    switch state {
    case .ok: .green
    case .near: .orange
    case .over: .red
    case nil: .secondary
    }
  }

  var body: some View {
    let shot = snapshot()
    let presentation = shot.presentation
    Button {
      showDetails.toggle()
    } label: {
      HStack(spacing: 8) {
        Text(verbatim: presentation.compact)
          .monospacedDigit()
          .foregroundStyle(color(for: presentation.state))
        if let fraction = presentation.fraction {
          ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.15))
            Capsule().fill(color(for: presentation.state)).frame(width: 36 * min(fraction, 1))
          }
          .frame(width: 36, height: 4)
        }
      }
    }
    .buttonStyle(DSPillButtonStyle())
    .help(String(localized: presentation.heaviest == nil ? "header.cu.none" : "header.cu.help"))
    .accessibilityLabel(String(localized: "header.cu.title"))
    .accessibilityValue(presentation.compact)
    .popover(isPresented: $showDetails) { details(shot) }
    // The limits are read once DT+ is on; the task ends with the view when DT+ goes off.
    .task { await connection.refreshCULimits() }
  }

  private func number(_ value: Int) -> String {
    value.formatted(.number.locale(locale))
  }

  @ViewBuilder
  private func details(_ shot: Snapshot) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("header.cu.title").font(.headline)
      if let heaviest = shot.presentation.heaviest, let reading = heaviest.reading {
        Text(verbatim: number(reading.cu))
          .font(.system(size: 22, weight: .semibold).monospacedDigit())
          .foregroundStyle(color(for: reading.state))
        Text(String(format: String(localized: "header.cu.limit"), number(reading.limit)))
        if shot.passes.count > 1, !heaviest.title.isEmpty {
          Text(String(format: String(localized: "header.cu.heaviest"), heaviest.title))
        }
        if let bare = shot.withoutMoodboard {
          Text(String(format: String(localized: "header.cu.withoutMoodboard"), number(bare)))
        }
        switch reading.state {
        case .ok: Text("header.cu.within")
        case .near: Text("header.cu.near").foregroundStyle(.orange)
        case .over:
          Text(
            reading.boosts == 1
              ? String(localized: "header.cu.boost.one")
              : String(format: String(localized: "header.cu.boost.other"), reading.boosts)
          )
          .foregroundStyle(.red)
        }
      } else {
        Text("header.cu.none")
      }
    }
    .padding(14)
    .frame(minWidth: 220, alignment: .leading)
  }
}
