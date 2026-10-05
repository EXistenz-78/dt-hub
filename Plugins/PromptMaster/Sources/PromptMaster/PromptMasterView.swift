import DTHubDesign
import SwiftUI

/// The tab, in the look of the app: the list of terms on the left; on the right the description and the chosen terms
/// with the button that writes the prompt.
struct PromptMasterView: View {
  @ObservedObject var state: PMState
  let write: () -> Void
  let makeScene: () -> Void
  let applyRatio: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      TermListView(state: state).frame(minWidth: 340, maxWidth: .infinity)
      VStack(spacing: DS.groupGap) {
        descriptionCard
        chosenCard
      }
      .frame(minWidth: 340, maxWidth: .infinity)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var descriptionCard: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "text.alignleft", title: L.text(.description, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        HStack {
          Spacer()
          Button(action: makeScene) {
            if state.isMakingScene {
              HStack(spacing: DS.pillIconGap) {
                ProgressView().controlSize(.small)
                Text(L.text(.sceneWriting, italian: state.italian))
              }
            } else {
              HStack(spacing: DS.pillIconGap) {
                Image(systemName: "dice")
                Text(L.text(.sceneShuffle, italian: state.italian))
              }
            }
          }
          .buttonStyle(DSPillButtonStyle())
          .disabled(state.isMakingScene || state.isWriting || !state.active)
        }
        ZStack(alignment: .topLeading) {
          TextEditor(text: $state.description)
            .font(.body).scrollContentBackground(.hidden).padding(6)
          if state.description.isEmpty {
            Text(L.text(.descriptionPlaceholder, italian: state.italian)).foregroundStyle(.tertiary)
              .padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false)
          }
        }
        .frame(minHeight: 110, maxHeight: 190)
        .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  private var chosenCard: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "checklist", title: L.text(.chosen, italian: state.italian))
        .overlay(alignment: .trailing) {
          Button { state.clearAll() } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(DS.remove)
          }
          .buttonStyle(.plain).padding(.trailing, DS.panelPadding)
          .help(L.text(.clearAll, italian: state.italian))
          .disabled(state.selection.isEmpty)
        }
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if state.selectedTerms.isEmpty {
          Text(L.text(.noneChosen, italian: state.italian)).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(state.selectedTerms) { term in
              HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                  Text(term.title).font(.callout).foregroundStyle(term.isNegative ? DS.remove : Color.primary)
                  Text(term.categoryTitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { state.setChosen(term.id, false) } label: { Image(systemName: "xmark").font(.caption) }
                  .buttonStyle(.plain).foregroundStyle(.secondary).help(L.text(.removeChosen, italian: state.italian))
              }
            }
          }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
        if state.hasBooruSwitch {
          Toggle(L.text(.booru, italian: state.italian), isOn: $state.booru).toggleStyle(DSCheckboxToggleStyle())
        }
        if !state.status.isEmpty {
          Text(state.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        if let ratio = state.suggestedRatio {
          Button(action: applyRatio) {
            HStack(spacing: DS.pillIconGap) {
              Image(systemName: "aspectratio")
              Text("\(L.text(.apply, italian: state.italian)) \(ratio)")
            }
          }
          .buttonStyle(DSPillButtonStyle())
          .disabled(!state.canApplyRatio)
        }
        Button(action: write) {
          if state.isWriting {
            HStack(spacing: DS.pillIconGap) {
              ProgressView().controlSize(.small)
              Text(L.text(.writing, italian: state.italian))
            }
          } else {
            HStack(spacing: DS.pillIconGap) {
              Image(systemName: "sparkles")
              Text(L.text(.writePrompt, italian: state.italian))
            }
          }
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .disabled(!state.canWrite)
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
    .frame(maxHeight: .infinity)
  }
}
