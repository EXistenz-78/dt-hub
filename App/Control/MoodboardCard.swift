import HubCore
import HubKit
import SwiftUI

/// The Moodboard (spec: tab Control §3): the pictures with a switch and a ✕ on each, and the drop
/// rule: on a picture replaces it, anywhere else in the card adds. Every picture that is on
/// counts the same (the shares of §4.1 come back when a model honours them).
struct MoodboardCard: View {
  let generation: GenerationController
  let connection: DrawThingsConnection
  let report: (ControlMessage) -> Void
  @State private var isTargeted = false
  @Environment(ContributionStore.self) private var contributions: ContributionStore?

  private var control: ControlStore { generation.control }
  private var entries: [MoodboardEntry] { control.inputs.moodboard }
  /// How many pictures are on when there are too many for the render time (the store decides).
  private var manyReferences: Int? {
    let warnings = control.warnings(
      canvasWidth: generation.parameters.width, canvasHeight: generation.parameters.height, usesMoodboard: usable)
    for warning in warnings { if case .manyReferences(let count) = warning { return count } }
    return nil
  }
  private var usable: Bool { FamilyTraits.of(generation.family(in: connection)).usesMoodboard }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "control.moodboard.title"), systemImage: "square.grid.2x2",
      isExpanded: generation.cards.binding("control.moodboard")
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if !usable {
          Label(String(localized: "control.moodboard.unsupported"), systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
        }
        if let many = manyReferences {
          Label(ControlText.warning(.manyReferences(count: many)), systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(DS.remove)
        }
        if !entries.isEmpty {
          HStack(spacing: DS.controlGap) {
            Text("control.moodboard.equal").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("control.moodboard.add") {
              Task { if let message = await ControlImport.chooseMoodboard(into: control) { report(.error(message)) } }
            }
            .buttonStyle(DSPillButtonStyle())
          }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: DS.rowGap, alignment: .top)], spacing: DS.rowGap) {
            ForEach(entries) { entry in
              MoodboardTile(
                entry: entry, control: control, isContributed: contributions?.moodboardPlugins[entry.id] != nil, report: report)
            }
          }
          Text("control.moodboard.hint").font(.caption).foregroundStyle(.secondary)
        } else {
          emptyZone
        }
      }
      .opacity(usable ? 1 : 0.5)
      .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(DS.accent, lineWidth: isTargeted ? 2 : 0))
      .dropDestination(for: URL.self) { urls, _ in
        Task { if let message = await ControlImport.takeMoodboard(urls: urls, into: control) { report(.error(message)) } }
        return true
      } isTargeted: { isTargeted = $0 }
    }
  }

  private var emptyZone: some View {
    VStack(spacing: DS.controlGap) {
      Image(systemName: "square.grid.2x2").font(.system(size: 24)).foregroundStyle(.secondary)
      Text("control.moodboard.drop").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("control.moodboard.add") {
        Task { if let message = await ControlImport.chooseMoodboard(into: control) { report(.error(message)) } }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
    .background(
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
  }
}

/// A picture of the Moodboard: thumbnail with the switch and the ✕. A picture dropped on it
/// replaces it.
private struct MoodboardTile: View {
  let entry: MoodboardEntry
  let control: ControlStore
  /// A plug-in added this picture and it is still there: teal at 30%.
  let isContributed: Bool
  let report: (ControlMessage) -> Void
  @Environment(PluginRegistry.self) private var plugins: PluginRegistry?
  @State private var thumbnail: CGImage?
  @State private var isTargeted = false

  var body: some View {
    VStack(spacing: 4) {
      ZStack {
        Group {
          if let thumbnail {
            Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
          } else {
            Color.primary.opacity(0.08)
          }
        }
        .frame(width: 124, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
        .opacity(entry.isOn ? 1 : 0.4)
        .overlay(
          RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
            .strokeBorder(DS.accent, lineWidth: isTargeted ? 2 : 0))
        VStack {
          HStack {
            overlayButton(
              systemImage: entry.isOn ? "eye" : "eye.slash",
              label: String(localized: entry.isOn ? "control.moodboard.turnOff" : "control.moodboard.turnOn")
            ) { control.setMoodboardOn(id: entry.id, isOn: !entry.isOn) }
            Spacer()
            overlayButton(systemImage: "xmark", label: String(localized: "control.moodboard.remove")) {
              control.removeMoodboardImage(id: entry.id)
            }
          }
          Spacer()
        }
        .padding(4)
      }
      .frame(width: 124, height: 124)
      .contributed(isContributed)
      if case .plugin = entry.image.source {
        Text(verbatim: ControlText.source(entry.image.source, plugins: plugins))
          .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      Task {
        if let message = await ControlImport.replaceMoodboard(id: entry.id, urls: urls, into: control) {
          report(.error(message))
        }
      }
      return true
    } isTargeted: { isTargeted = $0 }
    .task(id: entry.id) {
      guard let request = control.previewRequest(ofMoodboard: entry.id, maxPixel: 280) else { return thumbnail = nil }
      thumbnail = await Task.detached { request.render() }.value
    }
  }

  private func overlayButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
        .frame(width: 22, height: 22)
        .background(Circle().fill(Color.black.opacity(0.55)))
        .foregroundStyle(.white)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .help(label)
  }
}
