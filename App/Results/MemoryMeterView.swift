import HubCore
import HubKit
import SwiftUI

/// The memory meter under the progress bar of a run: a bar split between the image server, DT Hub (with its language
/// models), the rest of the system and what is free, and the free memory in numbers. Click for the details. It exists
/// only while a run goes on without DT+ (with DT+ the work is in the cloud), so the sampling stops with it.
///
/// This view alone reads the monitor: a reading every second must not redraw the results window.
struct MemoryMeterView: View {
  let monitor: MemoryMonitor
  @State private var showDetails = false
  @Environment(\.locale) private var locale
  @Environment(\.controlActiveState) private var activeState

  private func color(_ kind: MemorySegmentKind) -> Color {
    switch kind {
    case .server: DS.accent
    case .app: DS.accentDeep
    case .rest: Color.primary.opacity(0.35)
    case .free: Color.clear
    }
  }

  private func color(for state: MemoryState) -> Color {
    switch state {
    case .ok: .green
    case .near: .orange
    case .critical: .red
    }
  }

  var body: some View {
    // The task hangs on a container that always exists: on an empty view (no reading yet) it would never start, and
    // with it the first reading.
    ZStack(alignment: .leading) {
      Color.clear.frame(height: 0)
      if let snapshot = monitor.snapshot {
        let presentation = MemoryMeterPresentation(snapshot: snapshot, locale: locale)
        Button {
          showDetails.toggle()
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            bar(presentation)
            Text(String(format: String(localized: "results.memory.free"), presentation.compact))
              .font(.caption.monospacedDigit())
              .foregroundStyle(color(for: presentation.state))
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "results.memory.help"))
        .accessibilityLabel(String(localized: "results.memory.title"))
        .accessibilityValue(String(format: String(localized: "results.memory.free"), presentation.compact))
        .popover(isPresented: $showDetails) { details(snapshot, presentation) }
      }
    }
    // Slower while the window is not the active one; the task ends with the view when the run ends.
    .task(id: activeState == .inactive) {
      await monitor.run(every: activeState == .inactive ? .seconds(5) : MemoryMonitor.defaultInterval)
    }
  }

  private func bar(_ presentation: MemoryMeterPresentation) -> some View {
    GeometryReader { proxy in
      HStack(spacing: 0) {
        ForEach(presentation.segments.indices, id: \.self) { index in
          let segment = presentation.segments[index]
          Rectangle().fill(color(segment.kind)).frame(width: proxy.size.width * segment.fraction)
        }
      }
      .frame(width: proxy.size.width, alignment: .leading)
      .background(Color.primary.opacity(0.12))
      .clipShape(Capsule())
    }
    .frame(height: 5)
  }

  private func gigabytes(_ bytes: UInt64) -> String { MemoryMeterPresentation.gigabytes(bytes, locale: locale) }

  private func row(_ kind: MemorySegmentKind, _ title: LocalizedStringKey, _ bytes: UInt64?) -> some View {
    HStack(spacing: 8) {
      Circle().fill(kind == .free ? Color.primary.opacity(0.12) : color(kind)).frame(width: 8, height: 8)
      Text(title)
      Spacer(minLength: 16)
      Text(verbatim: bytes.map(gigabytes) ?? "—").monospacedDigit().foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func details(_ snapshot: MemorySnapshot, _ presentation: MemoryMeterPresentation) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("results.memory.title").font(.headline)
      Text(verbatim: gigabytes(snapshot.totalBytes)).font(.system(size: 22, weight: .semibold).monospacedDigit())
        .foregroundStyle(color(for: presentation.state))
      row(.server, "results.memory.server", snapshot.serverBytes)
      row(.app, "results.memory.app", snapshot.appBytes)
      row(.rest, "results.memory.rest", snapshot.restBytes)
      row(.free, "results.memory.free.row", snapshot.availableBytes)
      Divider()
      switch snapshot.pressure {
      case .normal: Text("results.memory.pressure.normal")
      case .warning: Text("results.memory.pressure.warning").foregroundStyle(.orange)
      case .critical: Text("results.memory.pressure.critical").foregroundStyle(.red)
      }
      if snapshot.swapUsedBytes > 0 {
        Text(String(format: String(localized: "results.memory.swap"), gigabytes(snapshot.swapUsedBytes)))
          .foregroundStyle(.orange)
      }
      if snapshot.serverBytes == nil {
        Text("results.memory.serverUnknown").foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(minWidth: 260, alignment: .leading)
  }
}
