import AppKit
import SwiftUI

/// A plug-in's tab: the view controller its code made.
struct PluginTabView: NSViewControllerRepresentable {
  let controller: NSViewController

  func makeNSViewController(context: Context) -> NSViewController { controller }

  func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
