import Foundation
import Testing
@testable import DrawThingsClient

/// Configurations exported from the Draw Things app in its two JSON shapes: the compact
/// "Copy Configuration" and a complete export (GetConfigPro) of the same settings.
@Suite("Draw Things app configuration examples")
struct AppConfigExampleTests {
    static let names = ["Krea 2 + LoRA", "H3 + Turbo"]

    private static func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    /// Compares JSON values the way the app treats them: null and "" are both "none", and
    /// numbers compare with Float precision (the app writes 0.59999999999999998 for 0.6).
    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        func normalized(_ value: Any?) -> Any? {
            if value == nil || value is NSNull { return nil }
            if let string = value as? String, string.isEmpty { return nil }
            return value
        }
        switch (normalized(a), normalized(b)) {
        case (nil, nil):
            return true
        case (let x as NSNumber, let y as NSNumber):
            return Float(truncating: x) == Float(truncating: y)
        case (let x as [Any], let y as [Any]):
            return x.count == y.count && zip(x, y).allSatisfy { same($0, $1) }
        case (let x as [String: Any], let y as [String: Any]):
            return Set(x.keys).union(y.keys).allSatisfy { same(x[$0], y[$0]) }
        case (let x as String, let y as String):
            return x == y
        default:
            return false
        }
    }

    @Test(arguments: names)
    func bothShapesParseAndValidate(name: String) throws {
        for shape in ["DT Copy", "GetConfigPro"] {
            let configuration = try DrawThingsConfiguration.fromJSON(try Self.fixture("\(name) \(shape) Config"))
            #expect(throws: Never.self) { try configuration.validate() }
            #expect(throws: Never.self) { try configuration.toFlatBufferData() }
            #expect(configuration.loras.count == 1)
        }
    }

    @Test(arguments: names)
    func completeExportRoundTripsKeyForKey(name: String) throws {
        let export = try Self.fixture("\(name) GetConfigPro Config")
        let reencoded = try Self.object(try DrawThingsConfiguration.fromJSON(export).toJSON())
        for (key, value) in try Self.object(export) {
            #expect(Self.same(reencoded[key], value), "\(key): app \(value), re-encoded \(String(describing: reencoded[key]))")
        }
    }

    @Test(arguments: names)
    func compactCopyAgreesWithCompleteExport(name: String) throws {
        let copyJSON = try Self.fixture("\(name) DT Copy Config")
        let completeJSON = try Self.fixture("\(name) GetConfigPro Config")
        let copy = try Self.object(copyJSON)
        let completeObject = try Self.object(completeJSON)
        // The example files themselves differ on a few settings (the Krea 2 copy has a fixed
        // seed, its complete export a random one); compare everything else.
        let shared = copy.keys.filter { Self.same(copy[$0], completeObject[$0] ?? NSNull()) || completeObject[$0] == nil }

        // Every shared setting parses to the same value from either shape.
        let fromCopy = try Self.object(try DrawThingsConfiguration.fromJSON(copyJSON).toJSON())
        let fromComplete = try Self.object(try DrawThingsConfiguration.fromJSON(completeJSON).toJSON())
        for key in shared {
            #expect(Self.same(fromCopy[key], fromComplete[key]), "\(key)")
        }

        // Pasting the copy over the complete settings changes only the settings the files
        // disagree on, as in the app.
        var merged = try DrawThingsConfiguration.fromJSON(completeJSON)
        try merged.mergeJSON(copyJSON)
        let mergedObject = try Self.object(try merged.toJSON())
        for (key, value) in fromComplete where shared.contains(key) || copy[key] == nil {
            #expect(Self.same(mergedObject[key], value), "\(key)")
        }
        for key in copy.keys where !shared.contains(key) {
            #expect(Self.same(mergedObject[key], copy[key]), "\(key) takes the pasted value")
        }
    }

    @Test func compactCopyIsAnOverlayNotAFullConfiguration() throws {
        // The H3 copy omits resolutionDependentShift (false in the complete export), so parsing
        // the copy on its own falls back to the default; merging onto a base keeps the base's value.
        let copy = try Self.fixture("H3 + Turbo DT Copy Config")
        #expect(try DrawThingsConfiguration.fromJSON(copy).resolutionDependentShift == DrawThingsConfiguration().resolutionDependentShift)
        var base = DrawThingsConfiguration()
        base.resolutionDependentShift = false
        try base.mergeJSON(copy)
        #expect(!base.resolutionDependentShift)
        #expect(base.model == "minimax_h3_fl2va_q8p.ckpt")
    }

    @Test func largeSeedsAndLoRAWeightsSurvive() throws {
        let krea = try DrawThingsConfiguration.fromJSON(try Self.fixture("Krea 2 + LoRA DT Copy Config"))
        #expect(krea.seed == 2_586_521_127)  // above Int32.max
        let h3 = try DrawThingsConfiguration.fromJSON(try Self.fixture("H3 + Turbo DT Copy Config"))
        #expect(h3.loras.first?.weight == 0.6)
        #expect(h3.numFrames == 124)
        #expect(MediaProfile(configuration: h3).isVideo)
    }
}
