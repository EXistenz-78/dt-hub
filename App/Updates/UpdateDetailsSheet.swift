import AppKit
import HubCore
import HubKit
import SwiftUI

/// What an update would do — the items, where from, how much — and, after «Scarica e installa», how it went.
struct UpdateDetailsSheet: View {
  let controller: UpdateController
  @Environment(\.dismiss) private var dismiss
  @State private var selected: Set<String> = []

  private var total: Int64 { controller.offers.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.item.size } }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.panelPadding) {
      Text("updates.sheet.title").font(.title3.weight(.semibold))
      if case .results(let results) = controller.message {
        resultsView(results)
      } else {
        offersView
      }
    }
    .padding(20)
    .frame(width: 460)
    .onAppear { selected = Set(controller.offers.map(\.id)) }
    .interactiveDismissDisabled(isInstalling)
  }

  private var isInstalling: Bool {
    if case .installing = controller.state { return true }
    return false
  }

  // MARK: Before the install

  private var offersView: some View {
    VStack(alignment: .leading, spacing: DS.controlGap) {
      ForEach(controller.offers) { offer in
        Toggle(isOn: Binding(get: { selected.contains(offer.id) }, set: { on in
          if on { selected.insert(offer.id) } else { selected.remove(offer.id) }
        })) {
          HStack {
            Text(verbatim: offer.item.name)
            Spacer(minLength: DS.controlGap)
            Text(verbatim: "\(offer.installed) → \(offer.item.version)  ·  \(UpdateText.size(offer.item.size))")
              .foregroundStyle(.secondary)
          }
        }
        .disabled(isInstalling)
      }
      Text("updates.source").font(.caption).foregroundStyle(.secondary)
      Text(verbatim: String(format: String(localized: "updates.total"), UpdateText.size(total)))
        .font(.caption).foregroundStyle(.secondary)
      if let tag = controller.tag,
        let notes = URL(string: "https://github.com/EXistenz-78/dt-hub/releases/tag/\(tag)")
      {
        Link("updates.releaseNotes", destination: notes).font(.caption)
      }
      if case .installing(let name, let fraction) = controller.state {
        ProgressView(value: fraction) {
          Text(verbatim: String(format: String(localized: "updates.downloading"), name)).font(.caption)
        }
      }
      HStack(spacing: DS.controlGap) {
        Spacer(minLength: 0)
        Button("updates.later") {
          controller.putOff()
          dismiss()
        }
        .buttonStyle(DSPillButtonStyle())
        .disabled(isInstalling)
        Button("updates.install") { Task { await controller.install(selected) } }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(selected.isEmpty || isInstalling)
      }
    }
  }

  // MARK: After the install

  private func resultsView(_ results: [UpdateResult]) -> some View {
    VStack(alignment: .leading, spacing: DS.controlGap) {
      ForEach(results, id: \.id) { result in
        HStack(alignment: .firstTextBaseline, spacing: DS.controlGap) {
          Image(systemName: result.error == nil ? "checkmark.circle.fill" : "xmark.octagon.fill")
            .foregroundStyle(result.error == nil ? Color.green : DS.remove)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: result.name)
            if let error = result.error {
              Text(verbatim: UpdateText.error(error)).font(.caption).foregroundStyle(DS.remove)
            } else {
              Text("updates.result.ok").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      if results.contains(where: { $0.id != "app" && $0.error == nil }) {
        Text("updates.plugins.note").font(.caption).foregroundStyle(.secondary)
      }
      if controller.needsRelaunch {
        Text("updates.relaunch.note").font(.caption).foregroundStyle(.secondary)
      }
      if controller.revealedApp != nil {
        Text("updates.revealed").font(.caption).foregroundStyle(.secondary)
      }
      HStack(spacing: DS.controlGap) {
        Spacer(minLength: 0)
        if let app = controller.revealedApp {
          Button("updates.reveal") { NSWorkspace.shared.activateFileViewerSelecting([app]) }
            .buttonStyle(DSPillButtonStyle(prominent: true))
        }
        if controller.needsRelaunch {
          Button("updates.relaunchNow") {
            // Close this sheet through SwiftUI first: an open sheet blocks the quit.
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { AppRelaunch.relaunch() }
          }
            .buttonStyle(DSPillButtonStyle(prominent: true))
        }
        Button(controller.needsRelaunch ? "updates.later" : "updates.close") {
          controller.clearResults()
          dismiss()
        }
        .buttonStyle(DSPillButtonStyle())
      }
    }
  }
}
