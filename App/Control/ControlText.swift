import HubCore
import HubKit
import SwiftUI

/// The words for the Control tab: where an image came from, what changed, what went wrong.
enum ControlText {
  static func error(_ error: ControlError) -> String {
    switch error {
    case .unreadable(let name): String(format: String(localized: "control.error.unreadable"), name)
    case .cannotSave(let detail): String(format: String(localized: "control.error.cannotSave"), detail)
    }
  }

  static func source(_ source: ReferenceImage.Source) -> String {
    switch source {
    case .file: String(localized: "control.source.file")
    case .result: String(localized: "control.source.result")
    case .pasteboard: String(localized: "control.source.pasteboard")
    case .plugin(let id): String(format: String(localized: "control.source.plugin"), id)
    }
  }

  static func notice(_ notice: ControlNotice) -> String {
    switch notice {
    case .removed(let name): String(format: String(localized: "control.notice.removed"), name)
    case .replaced(let name): String(format: String(localized: "control.notice.replaced"), name)
    case .cleared: String(localized: "control.notice.cleared")
    case .missingAtLaunch(let name): String(format: String(localized: "control.notice.missing"), name)
    case .maskCleared: String(localized: "control.notice.maskCleared")
    case .maskMissingAtLaunch: String(localized: "control.notice.maskMissing")
    case .paintCleared: String(localized: "control.notice.paintCleared")
    case .paintMissingAtLaunch: String(localized: "control.notice.paintMissing")
    }
  }

  static func warning(_ warning: ControlWarning) -> String {
    switch warning {
    case .strongCrop(let percent): String(format: String(localized: "control.warning.crop"), percent)
    case .manyReferences(let count): String(format: String(localized: "control.warning.many"), count)
    case .moodboardIgnored: String(localized: "control.warning.ignored")
    }
  }
}
