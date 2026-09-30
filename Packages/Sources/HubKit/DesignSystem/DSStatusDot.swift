import SwiftUI

/// Traffic-light dot for the Draw Things connection: green connected, yellow connecting,
/// red not reachable (spec §7).
public struct DSStatusDot: View {
  let status: ConnectionStatus

  public init(status: ConnectionStatus) { self.status = status }

  public var body: some View {
    Circle()
      .fill(color)
      .frame(width: 10, height: 10)
      .shadow(color: color.opacity(0.6), radius: 4)
  }

  private var color: Color {
    switch status {
    case .connected: .green
    case .connecting: .yellow
    case .disconnected: .red
    }
  }
}
