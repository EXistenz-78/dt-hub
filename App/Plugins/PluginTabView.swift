import AppKit
import SwiftUI

/// A plug-in's tab: the view controller its code made.
///
/// The plug-in has one view controller, and its tab can move between the main window and a window of its own. Each
/// place that shows the tab has a host of its own, and the plug-in's controller is the host's child: the host that
/// comes takes it, and the host that goes lets it go only if it still has it. Given to SwiftUI directly, the window
/// that went took the view away after the new one had it, and the tab stayed empty.
struct PluginTabView: NSViewControllerRepresentable {
  let controller: NSViewController

  func makeNSViewController(context: Context) -> PluginTabHost { PluginTabHost(child: controller) }

  func updateNSViewController(_ host: PluginTabHost, context: Context) {}

  static func dismantleNSViewController(_ host: PluginTabHost, coordinator: ()) { host.letGo() }
}

/// Holds a plug-in's view controller for one place that shows its tab.
final class PluginTabHost: NSViewController {
  private let child: NSViewController

  init(child: NSViewController) {
    self.child = child
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    view = NSView()
    take()
  }

  /// Takes the plug-in's controller, from another host if one still has it. The view fills the host.
  private func take() {
    guard child.parent !== self else { return }
    child.view.removeFromSuperview()
    child.removeFromParent()
    addChild(child)
    child.view.translatesAutoresizingMaskIntoConstraints = true
    child.view.frame = view.bounds
    child.view.autoresizingMask = [.width, .height]
    view.addSubview(child.view)
  }

  /// Lets the plug-in's controller go, unless another host took it meanwhile.
  func letGo() {
    guard child.parent === self else { return }
    child.view.removeFromSuperview()
    child.removeFromParent()
  }
}
