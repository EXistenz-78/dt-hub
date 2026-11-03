import AppKit

/// The standard About panel (icon, name, version) with a line under the version that links to the GitHub repository.
enum AboutPanel {
  static let repository = URL(string: "https://github.com/EXistenz-78/dt-hub")!

  @MainActor
  static func show() {
    let centered = NSMutableParagraphStyle()
    centered.alignment = .center
    let credits = NSAttributedString(
      string: String(localized: "about.link"),
      attributes: [
        .link: repository, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .paragraphStyle: centered,
      ])
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
  }
}
