import AppKit
import DTHubPluginKit
import SwiftUI

@MainActor
final class SampleState: ObservableObject {
  @Published var model = "—"
  @Published var active = false
}

@MainActor
final class SamplePlugin: DTHubPlugin {
  let manifest = DTHubManifest(id: "com.example.dthub.sample", name: "Sample", version: "1.0", symbol: "star")
  private let state = SampleState()

  func makeViewController() -> NSViewController {
    NSHostingController(rootView: SampleView(state: state))
  }

  func start(host: DTHubHost) {
    host.notice("Sample plug-in started")
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) {
        state.model = context.model ?? "—"
      }
      return nil
    case "activate":
      state.active = true
      return nil
    case "deactivate":
      state.active = false
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }
}

struct SampleView: View {
  @ObservedObject var state: SampleState

  var body: some View {
    VStack(spacing: 8) {
      Text("Sample plug-in").font(.title2)
      Text("Model: \(state.model)")
      Text(state.active ? "active" : "not active").foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

@objc(SampleEntry)
public final class SampleEntry: DTHubPluginEntry {
  public override func makePlugin() -> any DTHubPlugin { SamplePlugin() }
}
