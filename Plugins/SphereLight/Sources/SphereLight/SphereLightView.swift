import DTHubDesign
import SwiftUI

/// The tab, in the look of the app: the lights as cards on the left, the sphere in a panel on the right.
struct SphereLightView: View {
  @ObservedObject var state: SLRState
  let send: (SphereSender.Kind) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: DS.groupGap) {
      lights.frame(width: 300)
      preview.frame(maxWidth: .infinity)
    }
    .padding(DS.groupGap)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var lights: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      DSGroupHeader(title: L.text(.lights), prominent: true)
      ScrollView {
        VStack(spacing: DS.groupGap) {
          ForEach($state.lights) { $light in
            LightControlView(
              light: $light, index: state.lights.firstIndex(where: { $0.id == light.id }) ?? 0,
              isExpanded: Binding(
                get: { state.expanded[light.id, default: true] }, set: { state.expanded[light.id] = $0 }),
              canRemove: state.lights.count > 1, onRemove: { state.removeLight(light.id) },
              onChange: { state.lightChanged() })
          }
        }
        .padding(.bottom, DS.panelPadding)
      }
      .scrollIndicators(.hidden)
      if state.canAddLight {
        Button { state.addLight() } label: {
          HStack(spacing: DS.pillIconGap) {
            Image(systemName: "plus")
            Text(L.text(.addLight))
          }
        }
        .buttonStyle(DSPillButtonStyle())
      }
    }
  }

  private var preview: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "circle.lefthalf.filled", title: L.text(.preview))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        ZStack {
          RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06))
          if let image = state.previewImage {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(6)
          } else {
            ProgressView()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)

        Toggle(L.text(.overcast), isOn: $state.overcast).toggleStyle(DSCheckboxToggleStyle())
        Toggle(L.text(.saveDesktop), isOn: $state.saveToDesktop).toggleStyle(DSCheckboxToggleStyle())
        HStack(spacing: DS.controlGap) {
          Button { send(.pipeline) } label: {
            if state.isSending {
              ProgressView().controlSize(.small)
            } else {
              HStack(spacing: DS.pillIconGap) {
                Image(systemName: "sparkles")
                Text(L.text(.sendPipeline))
              }
            }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(state.isSending || !state.active)
          Button(L.text(.sendMoodboard)) { send(.moodboard) }
            .buttonStyle(DSPillButtonStyle())
            .disabled(state.isSending || !state.active)
        }
        if !state.status.isEmpty {
          Text(state.status).font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }
}
