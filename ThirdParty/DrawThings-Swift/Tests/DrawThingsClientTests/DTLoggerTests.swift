import CoreGraphics
import Foundation
import Testing
@testable import DrawThingsClient

/// DTLogger settings are global, so these tests run one at a time and restore them afterwards.
@Suite("DTLogger", .serialized)
final class DTLoggerTests {
    private let savedLevel: DTLogLevel
    private let savedEnabled: Bool

    init() {
        savedLevel = DTLogger.minimumLevel
        savedEnabled = DTLogger.shared.isEnabled
    }

    deinit {
        DTLogger.minimumLevel = savedLevel
        DTLogger.shared.isEnabled = savedEnabled
    }

    @Test func loggingIsOffByDefault() {
        #expect(DTLogger.minimumLevel == .none)
        #expect(!(DTLogger.isLogging(.fault)))
    }

    @Test func minimumLevelFiltersLowerLevels() {
        DTLogger.minimumLevel = .warning
        #expect(!(DTLogger.isLogging(.debug)))
        #expect(!(DTLogger.isLogging(.info)))
        #expect(DTLogger.isLogging(.warning))
        #expect(DTLogger.isLogging(.error))
        #expect(!(DTLogger.isLogging(.none)))
    }

    @Test func isEnabledOverridesLevel() {
        DTLogger.minimumLevel = .debug
        DTLogger.shared.isEnabled = false
        #expect(!(DTLogger.isLogging(.fault)))
    }

    @Test func messageIsNotEvaluatedWhenFiltered() {
        DTLogger.minimumLevel = .error
        var evaluated = false
        DTLogger.debug({ evaluated = true; return "skipped" }())
        #expect(!(evaluated))
    }

    @Test func concurrentUse() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    DTLogger.minimumLevel = i.isMultiple(of: 2) ? .debug : .none
                    DTLogger.debug("concurrent \(i)", category: .grpc)
                }
            }
        }
    }

    @available(*, deprecated)
    @Test func deprecatedClientLoggerForwards() {
        DrawThingsClientLogger.minimumLevel = .notice
        #expect(DTLogger.minimumLevel == .warning)
    }
}
