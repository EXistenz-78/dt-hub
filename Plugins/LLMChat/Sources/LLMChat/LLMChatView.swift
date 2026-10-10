import DTHubDesign
import DTHubPluginKit
import SwiftUI

/// The tab: a bar (model, images, new chat, chats), the messages, and the field to write in.
struct LLMChatView: View {
  @ObservedObject var state: LLMChatState
  let send: () -> Void
  @State private var renaming = false
  @State private var newName = ""
  @State private var deleting = false
  private var italian: Bool { L.systemIsItalian }

  var body: some View {
    VStack(spacing: DS.rowGap) {
      bar
      messages
      composer
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .alert(L.text(.renamePrompt), isPresented: $renaming) {
      TextField("", text: $newName)
      Button(L.text(.ok)) { state.rename(newName) }
      Button(L.text(.cancel), role: .cancel) {}
    }
    .confirmationDialog(L.text(.deleteConfirm), isPresented: $deleting, titleVisibility: .visible) {
      Button(L.text(.delete), role: .destructive) { state.deleteCurrent() }
      Button(L.text(.cancel), role: .cancel) {}
    }
  }

  // MARK: Bar

  private var bar: some View {
    HStack(spacing: DS.controlGap) {
      Menu {
        ForEach(state.models, id: \.name) { model in
          Button {
            state.selectModel(model.name)
          } label: {
            if model.name == state.resolvedModel?.name {
              Label(model.name, systemImage: "checkmark")
            } else {
              Text(verbatim: model.name)
            }
          }
        }
      } label: {
        Text(verbatim: state.resolvedModel?.name ?? L.text(.model)).lineLimit(1)
      }
      .menuStyle(.button)
      .frame(maxWidth: 260)
      Toggle(L.text(.images), isOn: $state.settings.includeImages)
        .toggleStyle(DSCheckboxToggleStyle())
        .disabled(!state.imagesAvailable)
        .help(state.imagesAvailable ? "" : L.text(.imagesOff))
      if !state.imagesAvailable, state.resolvedModel != nil {
        Text(L.text(.imagesOff)).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: DS.controlGap)
      Button(L.text(.newChat)) { state.newChat() }.buttonStyle(DSPillButtonStyle())
      Menu {
        ForEach(state.summaries) { summary in
          Button {
            state.open(summary.id)
          } label: {
            if summary.id == state.chat.id {
              Label("\(summary.title) · \(Self.date(summary.updated))", systemImage: "checkmark")
            } else {
              Text(verbatim: "\(summary.title) · \(Self.date(summary.updated))")
            }
          }
        }
        if !state.summaries.isEmpty { Divider() }
        Button(L.text(.rename)) {
          newName = state.chat.title
          renaming = true
        }
        .disabled(state.chat.messages.isEmpty)
        Button(L.text(.delete)) { deleting = true }.disabled(state.chat.messages.isEmpty)
      } label: {
        Text(verbatim: state.chat.title.isEmpty ? L.text(.chats) : state.chat.title).lineLimit(1)
      }
      .menuStyle(.button)
      .frame(maxWidth: 220)
    }
    .padding(DS.panelPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .dsPanel()
  }

  private static func date(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }

  // MARK: Messages

  private var messages: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: DS.rowGap) {
          ForEach(state.chat.messages) { message in
            row(message).id(message.id)
          }
          if state.isWaiting { Color.clear.frame(height: 1).id("bottom") }
        }
        .padding(DS.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .onChange(of: state.chat.messages.count) {
        if let last = state.chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .dsPanel()
  }

  @ViewBuilder private func row(_ message: ChatMessage) -> some View {
    switch message.role {
    case .user:
      VStack(alignment: .trailing, spacing: 2) {
        Text(verbatim: message.text)
          .textSelection(.enabled)
          .padding(10)
          .background(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous).fill(DS.accent.opacity(0.22)))
        if !message.images.isEmpty {
          Text(L.format(.attached, message.images.count)).font(.caption).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    case .assistant:
      // The words of the answer, then the texts the action block carries (prompts, the prompts of the passes of a pipeline)
      // that the answer does not already say: a person wants to read those. Settings are left to the note after.
      let words = ActionBlock.strip(message.text)
      let lines = ActionBlock.readableLines(in: message.text, italian: italian)
      if !words.isEmpty || !lines.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          if !words.isEmpty { Text(verbatim: words) }
          ForEach(Array(lines.enumerated()), id: \.offset) { _, line in Text(verbatim: line) }
        }
        .textSelection(.enabled)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous).fill(Color.primary.opacity(0.07)))
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    case .note:
      Text(verbatim: message.text)
        .font(.caption)
        .foregroundStyle(color(of: message.note))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func color(of kind: ChatMessage.NoteKind?) -> Color {
    switch kind {
    case .action?: DS.accent
    case .error?: .red
    default: .secondary
    }
  }

  // MARK: Composer

  @ViewBuilder private var composer: some View {
    if let blocker = state.blocker {
      Text(blocker)
        .foregroundStyle(.secondary)
        .padding(DS.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanel()
    } else {
      VStack(alignment: .leading, spacing: DS.controlGap) {
        if state.isWaiting {
          HStack(spacing: DS.controlGap) {
            ProgressView().controlSize(.small)
            Text(L.text(.thinking)).foregroundStyle(.secondary)
            Button(L.text(.stopWaiting)) { state.cancelWait() }.buttonStyle(DSPillButtonStyle())
          }
        }
        HStack(alignment: .bottom, spacing: DS.controlGap) {
          field
          Button(action: send) {
            Image(systemName: "paperplane")
          }
          .buttonStyle(DSGlassCircleButtonStyle())
          .help(L.text(.sendButton))
          .accessibilityLabel(L.text(.sendButton))
          .disabled(state.isWaiting || state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .padding(DS.panelPadding)
      .dsPanel()
    }
  }

  /// The text box: Return sends, Shift-Return makes a new line (a `TextEditor` does it at the cursor). The command button is
  /// small, inside the box, at the bottom right.
  private var field: some View {
    ZStack(alignment: .bottomTrailing) {
      TextEditor(text: $state.draft)
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 26)
        .disabled(state.isWaiting)
        .onKeyPress(.return, phases: .down) { press in
          if press.modifiers.contains(.shift) { return .ignored }
          send()
          return .handled
        }
        .overlay(alignment: .topLeading) {
          if state.draft.isEmpty {
            Text(L.text(.placeholder))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 9)
              .padding(.top, 4)
              .allowsHitTesting(false)
          }
        }
      Button {
        state.insertCommand()
      } label: {
        Text(L.command(italian: italian))
          .font(.system(size: 11, weight: .semibold, design: .monospaced))
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(Capsule().fill(DS.accent.opacity(0.25)))
      }
      .buttonStyle(.plain)
      .disabled(state.isWaiting)
      .help(L.text(.commandHelp))
      .padding(6)
    }
    .frame(height: fieldHeight)
    .background(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
  }

  /// From one line to six, by the text typed (a `TextEditor` does not grow by itself).
  private var fieldHeight: CGFloat {
    let lines = state.draft.split(separator: "\n", omittingEmptySubsequences: false)
      .reduce(0) { $0 + max(1, ($1.count + 79) / 80) }
    return CGFloat(min(6, max(1, lines))) * 19 + 34
  }
}
