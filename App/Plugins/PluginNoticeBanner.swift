import HubCore
import HubKit
import SwiftUI

/// A line a plug-in asked to show, floating over the window for a few seconds.
struct PluginNoticeBanner: View {
  let plugins: PluginRegistry

  var body: some View {
    Group {
      if let notice = plugins.latestNotice {
        HStack(spacing: DS.controlGap) {
          Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "puzzlepiece.extension")
            .foregroundStyle(notice.isError ? DS.remove : DS.accent)
          Text(verbatim: "\(notice.pluginName): \(notice.text)").lineLimit(2)
          Button {
            plugins.dismissNotice()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6, y: 2)
        .padding(.bottom, 16)
        .transition(.opacity)
        .task(id: notice.id) {
          try? await Task.sleep(for: .seconds(8))
          if plugins.latestNotice?.id == notice.id { plugins.dismissNotice() }
        }
      }
    }
    .animation(.default, value: plugins.latestNotice?.id)
  }
}
