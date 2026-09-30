/// State of the link to the Draw Things gRPC server, shown by the header dot (spec §7).
public enum ConnectionStatus: Equatable, Sendable {
  case connected
  case connecting
  case disconnected
}
