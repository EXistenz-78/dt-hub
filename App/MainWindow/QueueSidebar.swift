import DTHubDesign
import HubCore
import HubKit
import SwiftUI

/// The «Coda» sidebar: [+] [Start] on top, the entries, [Svuota] at the bottom (queue design §5).
struct QueueSidebar: View {
  let store: QueueStore
  let runner: QueueRunner
  let generation: GenerationController
  let connection: DrawThingsConnection

  /// What the last click on + or on an entry had to say.
  @State private var notice: String?
  @State private var confirmClear = false
  /// A capture is under way (a plug-in is asked for its snapshot): the + waits.
  @State private var capturing = false

  static let width: CGFloat = 260
  /// `@AppStorage` key: the sidebar is open or closed (kept between launches).
  static let visibleKey = "queue.sidebarVisible"

  var body: some View {
    VStack(alignment: .leading, spacing: DS.controlGap) {
      HStack(spacing: DS.controlGap) {
        Button {
          add()
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(DSGlassCircleButtonStyle())
        .disabled(capturing)
        .help(String(localized: "queue.add"))
        .accessibilityLabel(String(localized: "queue.add"))
        Spacer(minLength: 0)
        startStopButton
      }
      list
      if let text = notice ?? runnerMessage {
        Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Button(String(localized: "queue.clear")) { confirmClear = true }
        .disabled(store.entries.isEmpty || runner.isRunning)
        .frame(maxWidth: .infinity)
        .confirmationDialog(String(localized: "queue.clear.confirm"), isPresented: $confirmClear) {
          Button(String(localized: "queue.clear"), role: .destructive) { store.clear() }
        }
    }
    .padding(DS.panelPadding)
    .frame(width: Self.width)
    .frame(maxHeight: .infinity, alignment: .top)
    .dsPanel()
  }

  @ViewBuilder private var startStopButton: some View {
    if runner.isRunning {
      Button(String(localized: "queue.stop")) { runner.stop() }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .disabled(runner.state == .stopping)
    } else {
      Button(String(localized: "queue.start")) {
        notice = nil
        runner.start()
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
    }
  }

  private var runnerMessage: String? {
    switch runner.message {
    case .noPending: String(localized: "queue.noPending")
    case .cannotRun: String(localized: "queue.error.cannotRun")
    case nil: nil
    }
  }

  @ViewBuilder private var list: some View {
    if store.entries.isEmpty {
      Text(String(localized: "queue.empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List {
        ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
          QueueRow(index: index + 1, entry: entry)
            .contentShape(Rectangle())
            .onTapGesture { load(entry) }
            .contextMenu {
              Button(String(localized: "queue.delete"), role: .destructive) { store.remove(id: entry.id) }
                .disabled(isRunning(entry))
            }
        }
        .onMove { store.move(from: $0, to: $1) }
        .onDelete { offsets in
          for index in offsets where !isRunning(store.entries[index]) { store.remove(id: store.entries[index].id) }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
    }
  }

  private func isRunning(_ entry: QueueEntry) -> Bool { entry.status == .running }

  private func add() {
    guard !capturing else { return }
    notice = nil
    capturing = true
    Task {
      let result = await generation.captureQueueEntry(in: connection, store: store)
      if let entry = result.entry { store.add(entry) } else { notice = result.problem }
      capturing = false
    }
  }

  /// A click puts the entry on the tabs without running it; not while the queue runs.
  private func load(_ entry: QueueEntry) {
    guard !runner.isRunning else { return }
    Task { notice = await generation.restoreQueueEntry(entry, store: store, in: connection) }
  }
}

private struct QueueRow: View {
  let index: Int
  let entry: QueueEntry

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      statusIcon.frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: "\(index). \(entry.preset.prompt.isEmpty ? "—" : entry.preset.prompt)").lineLimit(1)
        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .help(helpText)
  }

  private var detail: String {
    var parts = [entry.preset.model.isEmpty ? "—" : entry.preset.model]
    switch entry.pipeline {
    case .user(let name): parts.append(String(format: String(localized: "queue.pipeline"), name))
    case .plugin(_, let name, _): parts.append(String(format: String(localized: "queue.pipeline"), name))
    case .guided(_, let name, _, _): parts.append(String(format: String(localized: "queue.pipeline"), name))
    case nil: break
    }
    return parts.joined(separator: " · ")
  }

  private var helpText: String {
    if case .failed(let reason) = entry.status { return reason }
    return entry.preset.prompt
  }

  @ViewBuilder private var statusIcon: some View {
    switch entry.status {
    case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
    case .running: ProgressView().controlSize(.small)
    case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(DS.remove)
    }
  }
}
