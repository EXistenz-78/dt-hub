import CoreGraphics
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Synchronization
@testable import DrawThingsClient

/// An in-process gRPC server implementing the Draw Things `ImageGenerationService`, for
/// testing the client end to end without a real server.
///
/// Each test scripts what `GenerateImage` sends back and inspects what the server received.
final class FakeDrawThingsServer: Sendable {
    typealias GenerateScript = @Sendable (ImageGenerationRequest, RPCWriter<ImageGenerationResponse>) async throws -> Void

    /// What the server has observed.
    struct Record: Sendable {
        var echoRequests: [EchoRequest] = []
        var generateRequests: [ImageGenerationRequest] = []
        /// Set when a generation script ended because the client cancelled the RPC.
        var generationCancelled = false
    }

    let port: Int
    private let server: GRPCServer<HTTP2ServerTransport.Posix>
    private let serveTask: Task<Void, Never>
    private let service: Service

    var record: Record { service.record.withLock { $0 } }

    /// Starts a plaintext server on a free loopback port.
    init(
        echoReply: EchoReply = EchoReply.with { $0.message = "HELLO test" },
        generate: @escaping GenerateScript = { _, _ in }
    ) async throws {
        var config = HTTP2ServerTransport.Posix.Config.defaults
        config.rpc.maxRequestPayloadSize = 64 * 1024 * 1024
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .plaintext,
            config: config
        )
        let service = Service(echoReply: echoReply, generate: generate)
        let server = GRPCServer(transport: transport, services: [service])
        self.service = service
        self.server = server
        self.serveTask = Task { try? await server.serve() }
        guard let port = try await transport.listeningAddress.ipv4?.port else {
            throw DrawThingsError.connectionFailed("test server did not bind")
        }
        self.port = port
    }

    /// A client service connected to this server (plaintext, bundled specs only).
    func makeService(options: ConnectionOptions = ConnectionOptions(security: .plaintext)) -> DrawThingsService {
        DrawThingsService(endpoint: ServerEndpoint(host: "127.0.0.1", port: port), options: options)
    }

    func stop() async {
        server.beginGracefulShutdown()
        await serveTask.value
    }

    private final class Service: ImageGenerationService.SimpleServiceProtocol {
        let echoReply: EchoReply
        let generate: GenerateScript
        let record = Mutex(Record())

        init(echoReply: EchoReply, generate: @escaping GenerateScript) {
            self.echoReply = echoReply
            self.generate = generate
        }

        func echo(request: EchoRequest, context: ServerContext) async throws -> EchoReply {
            record.withLock { $0.echoRequests.append(request) }
            return echoReply
        }

        func generateImage(
            request: ImageGenerationRequest,
            response: RPCWriter<ImageGenerationResponse>,
            context: ServerContext
        ) async throws {
            record.withLock { $0.generateRequests.append(request) }
            do {
                try await generate(request, response)
            } catch is CancellationError {
                record.withLock { $0.generationCancelled = true }
                throw CancellationError()
            }
            if Task.isCancelled { record.withLock { $0.generationCancelled = true } }
        }

        func filesExist(request: FileListRequest, context: ServerContext) async throws -> FileExistenceResponse {
            FileExistenceResponse.with {
                $0.files = request.files
                $0.existences = request.files.map { !$0.hasPrefix("missing") }
            }
        }

        func uploadFile(
            request: RPCAsyncSequence<FileUploadRequest, any Error>,
            response: RPCWriter<UploadResponse>,
            context: ServerContext
        ) async throws {
            throw RPCError(code: .unimplemented, message: "uploadFile")
        }

        func pubkey(request: PubkeyRequest, context: ServerContext) async throws -> PubkeyResponse {
            throw RPCError(code: .unimplemented, message: "pubkey")
        }

        func hours(request: HoursRequest, context: ServerContext) async throws -> HoursResponse {
            throw RPCError(code: .unimplemented, message: "hours")
        }
    }
}

// MARK: - Response builders

enum FakeResponses {
    static func signpost(_ build: (inout ImageGenerationSignpostProto) -> Void) -> ImageGenerationResponse {
        ImageGenerationResponse.with { $0.currentSignpost = .with(build) }
    }

    static func sampling(_ step: Int32) -> ImageGenerationResponse {
        signpost { $0.sampling = .with { $0.step = step } }
    }

    static let textEncoded = signpost { $0.textEncoded = .init() }
    static let imageDecoded = signpost { $0.imageDecoded = .init() }

    static func preview(_ tensor: Data) -> ImageGenerationResponse {
        ImageGenerationResponse.with { $0.previewImage = tensor }
    }

    /// Sends a tensor as the server does with `chunked`: split into `chunkSize` pieces, every
    /// piece but the last marked `.moreChunks`.
    static func chunked(image tensor: Data, chunkSize: Int) -> [ImageGenerationResponse] {
        stride(from: 0, to: tensor.count, by: chunkSize).map { offset in
            let end = min(offset + chunkSize, tensor.count)
            return ImageGenerationResponse.with {
                $0.generatedImages = [tensor.subdata(in: offset..<end)]
                $0.chunkState = end == tensor.count ? .lastChunk : .moreChunks
            }
        }
    }

    static func chunked(audio tensor: Data, chunkSize: Int) -> [ImageGenerationResponse] {
        stride(from: 0, to: tensor.count, by: chunkSize).map { offset in
            let end = min(offset + chunkSize, tensor.count)
            return ImageGenerationResponse.with {
                $0.generatedAudio = [tensor.subdata(in: offset..<end)]
                $0.chunkState = end == tensor.count ? .lastChunk : .moreChunks
            }
        }
    }

    /// A solid-color RGB image tensor, as the server sends for a decoded image.
    static func imageTensor(width: Int, height: Int, gray: CGFloat = 0.5) throws -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try ImageHelpers.imageToDTTensor(context.makeImage()!, forceRGB: true)
    }

    /// A planar stereo Float32 audio tensor ([channels, samples]).
    static func audioTensor(samples: Int) -> Data {
        var header = [UInt32](repeating: 0, count: 17)
        header[1] = 1
        header[2] = 0x01
        header[3] = 0x04000
        header[5] = 2
        header[6] = UInt32(samples)
        var data = header.withUnsafeBufferPointer { Data(buffer: $0) }
        let values = (0..<(2 * samples)).map { Float(sin(Double($0) * 0.01) * 0.5) }
        values.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}
