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
      // An answer that is only an action block has no words to show: the note after it tells what happened.
      let words = ActionBlock.strip(message.text)
      if !words.isEmpty {
        Text(verbatim: words)
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
          TextField(L.text(.placeholder), text: $state.draft, axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
            .disabled(state.isWaiting)
            .onKeyPress(.return, phases: .down) { press in
              // Return sends, Shift-Return makes a new line.
              if press.modifiers.contains(.shift) { return .ignored }
              send()
              return .handled
            }
          Button(L.command(italian: italian)) { state.insertCommand() }
            .buttonStyle(DSPillButtonStyle())
            .disabled(state.isWaiting)
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
}
