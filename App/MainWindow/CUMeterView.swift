import HubCore
import HubKit
import SwiftUI

/// The CU meter, inside the DT+ pill: the compute units the next RUN needs against the limit per RUN, as
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
    return Snapshot(passes: passes, readings: readings, presentation: presentation)
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
      // The bar, and under it, smaller, the value against the limit.
      VStack(spacing: 3) {
        ZStack(alignment: .leading) {
          Capsule().fill(Color.primary.opacity(0.15))
          if let fraction = presentation.fraction {
            Capsule().fill(color(for: presentation.state)).frame(width: 56 * min(fraction, 1))
          }
        }
        .frame(width: 56, height: 4)
        Text(verbatim: presentation.compact)
          .font(.system(size: 10, weight: .medium))
          .monospacedDigit()
          .foregroundStyle(color(for: presentation.state))
          .lineLimit(1)
          .fixedSize()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(String(localized: presentation.heaviest == nil ? "header.cu.none" : "header.cu.help"))
    .accessibilityLabel(String(localized: "header.cu.title"))
    .accessibilityValue(presentation.compact)
    .popover(isPresented: $showDetails) { details(shot) }
    // The limits are read once DT+ is on; the task ends with the view when DT+ goes off.
    .task { await connection.refreshCULimits() }
  }

  /// The heaviest estimate with no Moodboard picture, when pictures count for it; worked out only when the details
  /// are open.
  private func withoutMoodboard(_ shot: Snapshot) -> Int? {
    guard let heaviest = shot.presentation.heaviest?.reading,
      shot.passes.contains(where: { ($0.inputs?.referenceImages ?? 0) > 0 })
    else { return nil }
    let bare = shot.passes.compactMap { pass -> Int? in
      guard var inputs = pass.inputs else { return nil }
      inputs.referenceImages = 0
      return connection.computeUnits.estimate(inputs)
    }.max()
    guard let bare, bare != heaviest.cu else { return nil }
    return bare
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
        if let bare = withoutMoodboard(shot) {
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
