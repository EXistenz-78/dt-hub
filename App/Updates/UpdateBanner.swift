import HubCore
import HubKit
import SwiftUI

/// Under the header when the newest release has something for this Mac (or while it is being installed): what is
/// there, with Details and Later. The sheet of the details lives here so it stays open while the offers go away.
struct UpdateBanner: View {
  let controller: UpdateController
  @State private var showsDetails = false

  private var isWorking: Bool {
    switch controller.state {
    case .installing, .finished: true
    default: false
    }
  }

  var body: some View {
    Group {
      if !controller.visibleOffers.isEmpty || isWorking {
        HStack(alignment: .firstTextBaseline, spacing: DS.controlGap) {
          Image(systemName: "arrow.down.circle.fill")
            .foregroundStyle(DS.accent)
            .accessibilityHidden(true)
          Text(verbatim: line)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: DS.controlGap)
          Button("updates.details") { showsDetails = true }
            .buttonStyle(DSPillButtonStyle(prominent: true))
          if !isWorking {
            Button("updates.later") { controller.putOff() }
              .buttonStyle(DSPillButtonStyle())
          }
        }
        .padding(DS.boxPadding)
        .background(
          RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
            .fill(DS.accent.opacity(0.10)))
        .overlay(
          RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
            .strokeBorder(DS.accent.opacity(0.35), lineWidth: 1))
      }
    }
    .sheet(isPresented: $showsDetails) { UpdateDetailsSheet(controller: controller) }
  }

  private var line: String {
    switch controller.state {
    case .installing(let name, _): String(format: String(localized: "updates.banner.installing"), name)
    case .finished: String(localized: "updates.banner.done")
    default: UpdateText.summary(controller.visibleOffers)
    }
  }
}
