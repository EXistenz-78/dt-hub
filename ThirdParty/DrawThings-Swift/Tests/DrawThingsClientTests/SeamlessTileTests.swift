import FlatBuffers
import Foundation
import Testing
@testable import DrawThingsClient

@Suite("Seamless tile")
struct SeamlessTileTests {
    private func root(_ configuration: DrawThingsConfiguration) throws -> GenerationConfiguration {
        var buffer = ByteBuffer(data: try configuration.toFlatBufferData())
        return try getCheckedRoot(byteBuffer: &buffer)
    }

    /// The slot of the vtable at `offset` (in bytes), read from the raw buffer; 0 when absent.
    private func slot(_ offset: Int, in data: Data) -> UInt16 {
        func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        let table = u32(0)
        let soffset = Int(Int32(truncatingIfNeeded: u32(table)))
        let vtable = table - soffset
        return offset + 2 <= u16(vtable) ? UInt16(u16(vtable + offset)) : 0
    }

    @Test func theFieldSitsRightAfterTheSchedulerAtVtable190() throws {
        var configuration = DrawThingsConfiguration(width: 512, height: 512, steps: 4, model: "m.ckpt")
        configuration.scheduler = 4
        #expect(slot(188, in: try configuration.toFlatBufferData()) != 0)
        #expect(slot(190, in: try configuration.toFlatBufferData()) == 0)
        configuration.seamlessTile = 3
        #expect(slot(190, in: try configuration.toFlatBufferData()) != 0)
    }

    @Test func theValueTravelsInTheBuffer() throws {
        for value: Int8 in [1, 2, 3] {
            var configuration = DrawThingsConfiguration(width: 512, height: 512, steps: 4, model: "m.ckpt")
            configuration.seamlessTile = value
            #expect(try root(configuration).seamlessTile == value)
        }
    }

    @Test func offWritesNothingNew() throws {
        let configuration = DrawThingsConfiguration(width: 512, height: 512, steps: 4, model: "m.ckpt", seed: 7)
        #expect(configuration.seamlessTile == 0)
        var explicit = configuration
        explicit.seamlessTile = 0
        #expect(try configuration.toFlatBufferData() == explicit.toFlatBufferData())
        #expect(try root(configuration).seamlessTile == 0)
    }

    @Test func itSurvivesTheJSONRoundTripOnlyWhenSet() throws {
        var configuration = DrawThingsConfiguration(width: 512, height: 512, steps: 4, model: "m.ckpt")
        #expect(!(try configuration.toJSON().contains("seamlessTile")))
        configuration.seamlessTile = 2
        let copy = try DrawThingsConfiguration.fromJSON(try configuration.toJSON())
        #expect(copy.seamlessTile == 2)
    }
}
