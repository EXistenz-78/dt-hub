import SwiftUI

/// The tab: the lights on the left, the sphere and the two buttons on the right.
struct SphereLightView: View {
  @ObservedObject var state: SLRState
  let send: (SphereSender.Kind) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      lights.frame(width: 290)
      preview.frame(maxWidth: .infinity)
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var lights: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(L.text(.lights)).font(.title3.weight(.semibold))
      ScrollView {
        VStack(spacing: 14) {
          ForEach($state.lights) { $light in
            let index = state.lights.firstIndex(where: { $0.id == light.id }) ?? 0
            LightControlView(
              light: $light, index: index,
              isExpanded: Binding(
                get: { state.expanded[light.id, default: true] }, set: { state.expanded[light.id] = $0 }),
              canRemove: state.lights.count > 1, onRemove: { state.removeLight(light.id) },
              onChange: { state.lightChanged() })
            if index < state.lights.count - 1 { Divider() }
          }
        }
      }
      if state.canAddLight {
        Button { state.addLight() } label: { Label(L.text(.addLight), systemImage: "plus") }
      }
    }
  }

  private var preview: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L.text(.preview)).font(.title3.weight(.semibold))
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06))
        if let image = state.previewImage {
          Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(6)
        } else {
          ProgressView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .aspectRatio(1, contentMode: .fit)

      Toggle(L.text(.overcast), isOn: $state.overcast).toggleStyle(.checkbox)
      Toggle(L.text(.saveDesktop), isOn: $state.saveToDesktop).toggleStyle(.checkbox)
      HStack {
        Button { send(.pipeline) } label: {
          if state.isSending { ProgressView().controlSize(.small) } else { Text(L.text(.sendPipeline)) }
        }
        .buttonStyle(.borderedProminent)
        .disabled(state.isSending || !state.active)
        Button(L.text(.sendMoodboard)) { send(.moodboard) }
          .disabled(state.isSending || !state.active)
      }
      if !state.status.isEmpty {
        Text(state.status).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
  }
}
