import AppKit
import DTHubDesign
import DTHubPluginKit
import SwiftUI
import UniformTypeIdentifiers

/// "Your LoRAs": every LoRA of the server, by family, with its thumbnail and notes, and the two jobs that fill them in.
struct LAListCard: View {
  @ObservedObject var state: LAState

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      HStack(spacing: DS.controlGap) {
        DSGroupHeader(title: state.text(.listTitle), prominent: true)
        Spacer(minLength: 0)
        TextField(state.text(.filterPlaceholder), text: $state.filter)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 240)
      }
      jobsRow
      if let message = state.jobs.message {
        Text(verbatim: message).font(.caption).foregroundStyle(DS.remove)
      }
      if state.store.isUnreadable {
        Text(verbatim: state.text(.unreadableStore)).font(.caption).foregroundStyle(DS.remove)
      }
      if let blocker = state.blocker {
        Text(verbatim: text(of: blocker))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        list
      }
    }
    .padding(DS.panelPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .dsPanel()
  }

  private func text(of blocker: LAState.Blocker) -> String {
    switch blocker {
    case .notActive: state.text(.notActive)
    case .oldApp: state.text(.needsNewApp)
    case .noLoRAs: state.text(.noLoRAs)
    }
  }

  /// "Find pages" and "Summarise all", each with how many LoRAs it has to do; while one runs, its progress and "Stop".
  @ViewBuilder private var jobsRow: some View {
    let toSearch = state.jobs.toSearch(in: state.catalog).count
    let toSummarise = state.jobs.toSummarise(in: state.catalog).count
    HStack(spacing: DS.controlGap) {
      if state.jobs.running != nil {
        ProgressView().controlSize(.small)
        if let progress = state.jobs.progress {
          Text(verbatim: L.text(.progress, progress.done, progress.total)).font(.caption).monospacedDigit()
        }
        Button(state.text(.stop)) { state.jobs.stop() }
          .buttonStyle(DSPillButtonStyle())
      } else {
        Button(L.text(.findPages, toSearch)) {
          state.flushNotes()
          Task { await state.jobs.searchAll(state.catalog) }
        }
        .buttonStyle(DSPillButtonStyle())
        .disabled(toSearch == 0 || state.isBusy)
        Button(L.text(.summariseAll, toSummarise)) {
          state.flushNotes()
          Task { await state.jobs.summariseAll(state.catalog) }
        }
        .buttonStyle(DSPillButtonStyle())
        .disabled(toSummarise == 0 || state.isBusy || !state.hasLanguageModel)
        .help(state.hasLanguageModel ? "" : state.text(.needsLLM))
        Text(verbatim: state.text(.jobsNote)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
  }

  private var list: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 4) {
        ForEach(state.groups, id: \.family) { group in
          Text(verbatim: title(of: group))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, DS.controlGap)
          ForEach(group.loras, id: \.file) { lora in
            LARow(state: state, lora: lora)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func title(of group: LAState.Group) -> String {
    let name = group.family ?? state.text(.unknownFamily)
    return group.isCurrent ? name + " · " + state.text(.currentModel) : name
  }
}

/// One LoRA: closed, its thumbnail, name, trigger word, weight and the first line of its notes; open, the notes to
/// write, the link of its page and the thumbnail's menu. "Add" is on both.
struct LARow: View {
  @ObservedObject var state: LAState
  let lora: DTHubCatalogLoRA
  @State private var link = ""
  @State private var confirming = false

  private var file: String { lora.file }
  private var isOpen: Bool { state.openFile == file }
  private var entry: LAEntry { state.entry(for: file) }

  var body: some View {
    HStack(alignment: .top, spacing: DS.rowGap) {
      VStack(alignment: .leading, spacing: 6) {
        LAThumbnailView(url: state.thumbnailURL(for: file), side: isOpen ? 112 : 64)
        if isOpen { thumbnailMenu }
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: DS.controlGap) {
          Text(verbatim: lora.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
          Image(systemName: isOpen ? "chevron.up" : "chevron.down")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          Spacer(minLength: 0)
          addControl
        }
        // The name closes an open row; anywhere on a closed row opens it.
        .contentShape(Rectangle())
        .onTapGesture { if isOpen { state.openFile = nil } else { open() } }
        meta
        if isOpen { opened } else { preview }
      }
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: DS.boxRadius).fill(isOpen ? AnyShapeStyle(.background.opacity(0.35)) : AnyShapeStyle(.clear)))
    .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(isOpen ? AnyShapeStyle(.separator) : AnyShapeStyle(.clear)))
    .contentShape(Rectangle())
    .onTapGesture { if !isOpen { open() } }
    // The field shows the link the entry has: a search, or "Not this one", changes it under an open row.
    .onAppear { link = entry.link ?? "" }
    .onChange(of: entry.link) { _, new in link = new ?? "" }
    .confirmationDialog(state.text(.replaceNotesQuestion), isPresented: $confirming) {
      Button(state.text(.replace)) { state.startImport(for: file, link: link, notes: .replace) }
      Button(state.text(.keepMine)) { state.startImport(for: file, link: link, notes: .keepUsers) }
      Button(state.text(.cancel), role: .cancel) {}
    }
  }

  private func open() {
    link = entry.link ?? ""
    state.openFile = file
  }

  /// "trigger: … · weight …", then where the LoRA's page stands.
  private var meta: some View {
    HStack(spacing: 6) {
      Text(
        verbatim: (lora.trigger.isEmpty ? state.text(.noTrigger) : L.text(.trigger, lora.trigger)) + " · "
          + L.text(.weight, Self.format(lora.weight))
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .truncationMode(.middle)
      if state.jobs.isRaw(file) {
        LATag(text: state.text(.toSummarise), warning: true)
      } else if entry.foundBySearch {
        LATag(text: state.text(.foundAuto))
      } else if entry.searched && entry.link == nil {
        LATag(text: state.text(.pageNotFound), warning: true)
      }
    }
  }

  private var preview: some View {
    let first = LAText.firstLine(state.notes(for: file))
    return Text(verbatim: first.isEmpty ? state.text(.noNotes) : first)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .truncationMode(.tail)
  }

  /// "Add", or "already in the list" for a LoRA that is on the Generation tab.
  @ViewBuilder private var addControl: some View {
    if state.isOnTab(file) {
      LATag(text: state.text(.onTab))
    } else {
      Button(state.text(.add)) { Task { await state.add(lora) } }
        .buttonStyle(DSPillButtonStyle())
        .controlSize(.small)
        .disabled(!state.canAdd(lora) || !state.active)
        .help(state.canAdd(lora) ? "" : state.text(.otherFamily))
    }
  }

  @ViewBuilder private var opened: some View {
    TextEditor(text: Binding(get: { state.notes(for: file) }, set: { state.setNotes($0, for: file) }))
      .font(.body)
      .scrollContentBackground(.hidden)
      .padding(4)
      .frame(height: 96)
      .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.5)))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
      .accessibilityLabel(state.text(.notes))
    HStack(spacing: DS.controlGap) {
      TextField(state.text(.link), text: $link)
        .textFieldStyle(.roundedBorder)
      if state.importing == file {
        ProgressView().controlSize(.small)
        Button(state.text(.cancel)) { state.cancelImport() }
          .buttonStyle(DSPillButtonStyle())
      } else {
        Button(state.text(.importPage)) {
          if state.needsConfirmationToImport(file) { confirming = true } else { state.startImport(for: file, link: link, notes: .keepUsers) }
        }
        .buttonStyle(DSPillButtonStyle())
        .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isBusy)
      }
    }
    HStack(spacing: DS.controlGap) {
      if state.jobs.isRaw(file) {
        Button(state.text(.summarise)) { Task { await state.summarise(lora) } }
          .buttonStyle(DSPillButtonStyle())
          .disabled(state.isBusy || !state.hasLanguageModel)
          .help(state.hasLanguageModel ? "" : state.text(.needsLLM))
      }
      if entry.foundBySearch {
        Button(state.text(.notThisOne)) { state.notThisOne(file) }
        .buttonStyle(DSPillButtonStyle())
        .disabled(state.isBusy)
      }
      if entry.searched && entry.link == nil {
        Button(state.text(.searchAgain)) {
          Task { await state.jobs.searchAgain(lora) }
        }
        .buttonStyle(DSPillButtonStyle())
        .disabled(state.isBusy)
      }
    }
    if let message = state.rowMessage(for: file) {
      Text(verbatim: message).font(.caption).foregroundStyle(DS.remove)
    }
  }

  /// A picture of the user's own for the thumbnail: a file, or the start image of the Control tab.
  private var thumbnailMenu: some View {
    Menu(state.text(.thumbnail)) {
      Button(state.text(.chooseFile)) { chooseFile() }
      Button(state.text(.useControlImage)) { state.useControlImage(for: file) }
        .disabled(!state.canUseControlImage)
      Button(state.text(.removeThumbnail)) { state.removeThumbnail(for: file) }
        .disabled(entry.thumbnail == nil)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
  }

  private func chooseFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .webP, .heic]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    state.setThumbnail(fromFile: url, for: file)
  }

  static func format(_ weight: Double) -> String {
    weight.formatted(.number.precision(.fractionLength(0...2)))
  }
}
