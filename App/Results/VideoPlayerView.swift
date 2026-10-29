import AVKit
import SwiftUI

/// Plays the MP4 of a video result with the system's inline controls: looping, audio on, paused until the user
/// presses play. The player is torn down when the view goes away or the URL changes, so a selection that moves
/// through many results never leaves players running.
struct VideoPlayerView: NSViewRepresentable {
  let url: URL

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .inline
    view.showsFullScreenToggleButton = true
    context.coordinator.load(url, into: view)
    return view
  }

  func updateNSView(_ view: AVPlayerView, context: Context) {
    if context.coordinator.url != url { context.coordinator.load(url, into: view) }
  }

  static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
    coordinator.stop(in: view)
  }

  @MainActor
  final class Coordinator {
    private(set) var url: URL?
    private var looper: AVPlayerLooper?
    private var player: AVQueuePlayer?

    func load(_ url: URL, into view: AVPlayerView) {
      stop(in: view)
      self.url = url
      let player = AVQueuePlayer()
      looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
      self.player = player
      view.player = player
    }

    func stop(in view: AVPlayerView) {
      player?.pause()
      looper?.disableLooping()
      looper = nil
      player?.removeAllItems()
      player = nil
      view.player = nil
      url = nil
    }
  }
}
