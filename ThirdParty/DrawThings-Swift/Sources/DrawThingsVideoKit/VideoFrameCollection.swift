//
//  VideoFrameCollection.swift
//  DrawThingsVideoKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import CoreGraphics
import DrawThingsClient
import Foundation
import ImageIO

/// A standardized container for video frames that supports multiple image formats.
///
/// VideoFrameCollection provides a unified interface for working with sequences of images
/// regardless of their source format (CGImage, CIImage, platform images, or file URLs).
///
/// Example usage:
/// ```swift
/// // From URLs
/// let collection = VideoFrameCollection(urls: frameURLs)
///
/// // From CGImages
/// let collection = VideoFrameCollection(cgImages: images)
///
/// // Adding frames
/// var collection = VideoFrameCollection()
/// collection.append(cgImage: image)
/// collection.append(url: imageURL)
/// ```
public struct VideoFrameCollection: Sendable {
    /// The frames in this collection.
    public private(set) var frames: [VideoFrame]

    /// Metadata associated with this collection.
    public var metadata: VideoFrameMetadata

    /// Audio tracks (WAV) that go with these frames.
    public var audioData: [Data]?

    /// The number of frames in the collection.
    public var count: Int { frames.count }

    /// Whether the collection is empty.
    public var isEmpty: Bool { frames.isEmpty }

    /// Creates an empty frame collection.
    public init() {
        self.frames = []
        self.metadata = VideoFrameMetadata()
    }

    /// Creates a frame collection from file URLs.
    ///
    /// - Parameters:
    ///   - urls: Array of image file URLs.
    ///   - metadata: Optional metadata for the collection.
    public init(urls: [URL], metadata: VideoFrameMetadata = VideoFrameMetadata()) {
        self.frames = urls.map { VideoFrame.url($0) }
        self.metadata = metadata
    }

    /// Creates a frame collection from CGImages.
    ///
    /// - Parameters:
    ///   - cgImages: Array of CGImage instances.
    ///   - metadata: Optional metadata for the collection.
    public init(cgImages: [CGImage], metadata: VideoFrameMetadata = VideoFrameMetadata()) {
        self.frames = cgImages.map { VideoFrame.cgImage($0) }
        self.metadata = metadata
    }

    /// Creates a frame collection from platform images.
    ///
    /// - Parameters:
    ///   - images: Array of platform-specific images (NSImage/UIImage).
    ///   - metadata: Optional metadata for the collection.
    public init(images: [PlatformImage], metadata: VideoFrameMetadata = VideoFrameMetadata()) {
        self.frames = images.compactMap { $0.cgImageRepresentation.map(VideoFrame.cgImage) }
        self.metadata = metadata
    }

    // MARK: - Mutating Methods

    /// Appends a frame from a URL.
    public mutating func append(url: URL) {
        frames.append(.url(url))
    }

    /// Appends a frame from a CGImage.
    public mutating func append(cgImage: CGImage) {
        frames.append(.cgImage(cgImage))
    }

    /// Appends a frame from a platform image.
    public mutating func append(image: PlatformImage) {
        if let cgImage = image.cgImageRepresentation {
            frames.append(.cgImage(cgImage))
        }
    }

    /// Appends all frames from another collection.
    public mutating func append(contentsOf other: VideoFrameCollection) {
        frames.append(contentsOf: other.frames)
        if let otherAudio = other.audioData, !otherAudio.isEmpty {
            if audioData != nil {
                audioData!.append(contentsOf: otherAudio)
            } else {
                audioData = otherAudio
            }
        }
    }

    /// Removes all frames from the collection.
    public mutating func removeAll() {
        frames.removeAll()
        audioData = nil
    }

    /// Removes frames at the specified indices.
    public mutating func remove(at indices: IndexSet) {
        for index in indices.reversed() where frames.indices.contains(index) {
            frames.remove(at: index)
        }
    }

    // MARK: - Accessing Frames

    /// Accesses the frame at the specified index.
    public subscript(index: Int) -> VideoFrame {
        frames[index]
    }

    /// Returns the CGImage for the frame at the specified index.
    ///
    /// - Parameter index: The frame index.
    /// - Returns: The CGImage, or nil if it couldn't be loaded.
    public func cgImage(at index: Int) -> CGImage? {
        frames[index].cgImage
    }

    /// Returns all frames as CGImages.
    ///
    /// - Returns: Array of CGImages (frames that fail to load are excluded).
    public func allCGImages() -> [CGImage] {
        frames.compactMap { $0.cgImage }
    }
}

// MARK: - VideoFrame

/// A single frame in a video frame collection.
public enum VideoFrame: Sendable {
    /// A frame stored as a file URL.
    case url(URL)

    /// A frame stored as a CGImage.
    case cgImage(CGImage)

    /// Returns the CGImage representation of this frame.
    ///
    /// For URL frames, this loads the image from disk.
    public var cgImage: CGImage? {
        switch self {
        case .url(let url):
            return Self.loadCGImage(from: url)
        case .cgImage(let image):
            return image
        }
    }

    /// Loads a CGImage from a file URL.
    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }
}

// MARK: - VideoFrameMetadata

/// Metadata associated with a video frame collection.
public struct VideoFrameMetadata: Sendable {
    /// The source job ID if frames came from a DrawThingsKit job.
    public var sourceJobId: UUID?

    /// The prompt used to generate the frames.
    public var prompt: String?

    /// The negative prompt used to generate the frames.
    public var negativePrompt: String?

    /// The model used to generate the frames.
    public var model: String?

    /// The seed used for generation.
    public var seed: UInt32?

    /// The timestamp when the frames were generated.
    public var generatedAt: Date?

    /// Custom metadata dictionary.
    public var custom: [String: String]

    /// Creates metadata with optional values.
    public init(
        sourceJobId: UUID? = nil,
        prompt: String? = nil,
        negativePrompt: String? = nil,
        model: String? = nil,
        seed: UInt32? = nil,
        generatedAt: Date? = nil,
        custom: [String: String] = [:]
    ) {
        self.sourceJobId = sourceJobId
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.model = model
        self.seed = seed
        self.generatedAt = generatedAt
        self.custom = custom
    }
}

// MARK: - Collection Conformance

extension VideoFrameCollection: Collection {
    public var startIndex: Int { frames.startIndex }
    public var endIndex: Int { frames.endIndex }

    public func index(after i: Int) -> Int {
        frames.index(after: i)
    }
}

// MARK: - Frame Format

/// Image format for saving video frames.
public enum FrameFormat: String, Codable, Sendable {
    /// PNG format (lossless, larger files).
    case png
    /// JPEG format with specified quality.
    case jpeg

    /// Default JPEG quality (0.9).
    public static let defaultJPEGQuality: Double = 0.9
}

// MARK: - Persistence Errors

/// Errors that can occur during frame collection persistence.
public enum VideoFrameCollectionError: Error, LocalizedError, Sendable {
    case directoryCreationFailed(Error)
    case manifestWriteFailed(Error)
    case manifestReadFailed(Error)
    case manifestNotFound
    case invalidManifest(String)
    case frameWriteFailed(index: Int, Error)
    case frameReadFailed(filename: String)
    case noFramesToSave
    case unsupportedManifestVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "Failed to create directory: \(error.localizedDescription)"
        case .manifestWriteFailed(let error):
            return "Failed to write manifest: \(error.localizedDescription)"
        case .manifestReadFailed(let error):
            return "Failed to read manifest: \(error.localizedDescription)"
        case .manifestNotFound:
            return "Manifest file not found in directory"
        case .invalidManifest(let reason):
            return "Invalid manifest: \(reason)"
        case .frameWriteFailed(let index, let error):
            return "Failed to write frame \(index): \(error.localizedDescription)"
        case .frameReadFailed(let filename):
            return "Failed to read frame: \(filename)"
        case .noFramesToSave:
            return "No frames to save"
        case .unsupportedManifestVersion(let version):
            return "Unsupported manifest version: \(version)"
        }
    }
}

// MARK: - Manifest Structures

/// The manifest file structure for a saved frame collection.
private struct FrameCollectionManifest: Codable {
    static let currentVersion = 2
    static let filename = "manifest.json"

    let version: Int
    let frameCount: Int
    let format: FrameFormat
    let jpegQuality: Double?
    let frames: [FrameEntry]
    let metadata: MetadataEntry
    let audio: [AudioEntry]?

    struct FrameEntry: Codable {
        let filename: String
        let index: Int
    }

    struct AudioEntry: Codable {
        let filename: String
        let index: Int
    }

    struct MetadataEntry: Codable {
        let sourceJobId: String?
        let prompt: String?
        let negativePrompt: String?
        let model: String?
        let seed: Int64?
        let generatedAt: Date?
        let custom: [String: String]?
    }
}

// MARK: - Save/Load Extensions

extension VideoFrameCollection {
    /// Saves the frame collection to a directory.
    ///
    /// Creates a directory containing individual frame files and a manifest.json
    /// that preserves the frame order and metadata.
    ///
    /// Example:
    /// ```swift
    /// let collection = VideoFrameCollection(cgImages: frames)
    /// try await collection.save(to: outputDirectory)
    ///
    /// // With JPEG format and progress
    /// try await collection.save(
    ///     to: outputDirectory,
    ///     format: .jpeg,
    ///     jpegQuality: 0.85
    /// ) { progress in
    ///     print("Saving: \(Int(progress * 100))%")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - directory: The directory to save to. Will be created if it doesn't exist.
    ///   - format: The image format to use (default: .png).
    ///   - jpegQuality: JPEG quality if format is .jpeg (0.0-1.0, default: 0.9).
    ///   - progress: Optional progress callback (0.0 to 1.0).
    /// - Throws: `VideoFrameCollectionError` if saving fails.
    public func save(
        to directory: URL,
        format: FrameFormat = .png,
        jpegQuality: Double = FrameFormat.defaultJPEGQuality,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard !isEmpty else {
            throw VideoFrameCollectionError.noFramesToSave
        }

        // Create directory if needed
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw VideoFrameCollectionError.directoryCreationFailed(error)
        }

        let fileExtension = format == .png ? "png" : "jpg"
        var frameEntries: [FrameCollectionManifest.FrameEntry] = []

        // Save each frame
        for (index, frame) in frames.enumerated() {
            let filename = String(format: "frame_%04d.\(fileExtension)", index)
            let fileURL = directory.appendingPathComponent(filename)

            guard let cgImage = frame.cgImage else {
                throw VideoFrameCollectionError.frameWriteFailed(
                    index: index,
                    NSError(domain: "VideoFrameCollection", code: -1,
                           userInfo: [NSLocalizedDescriptionKey: "Could not get CGImage"])
                )
            }

            do {
                try saveImage(cgImage, to: fileURL, format: format, quality: jpegQuality)
            } catch {
                throw VideoFrameCollectionError.frameWriteFailed(index: index, error)
            }

            frameEntries.append(FrameCollectionManifest.FrameEntry(
                filename: filename,
                index: index
            ))

            progress?(Double(index + 1) / Double(frames.count))
        }

        // Save audio files if present
        var audioEntries: [FrameCollectionManifest.AudioEntry]? = nil
        if let audioDataArray = audioData, !audioDataArray.isEmpty {
            var entries: [FrameCollectionManifest.AudioEntry] = []
            for (index, wavData) in audioDataArray.enumerated() {
                let filename = String(format: "audio_%04d.wav", index)
                let fileURL = directory.appendingPathComponent(filename)
                try wavData.write(to: fileURL)
                entries.append(FrameCollectionManifest.AudioEntry(filename: filename, index: index))
            }
            audioEntries = entries
        }

        // Create and save manifest
        let manifest = FrameCollectionManifest(
            version: FrameCollectionManifest.currentVersion,
            frameCount: frames.count,
            format: format,
            jpegQuality: format == .jpeg ? jpegQuality : nil,
            frames: frameEntries,
            metadata: FrameCollectionManifest.MetadataEntry(
                sourceJobId: metadata.sourceJobId?.uuidString,
                prompt: metadata.prompt,
                negativePrompt: metadata.negativePrompt,
                model: metadata.model,
                seed: metadata.seed.map(Int64.init),
                generatedAt: metadata.generatedAt,
                custom: metadata.custom.isEmpty ? nil : metadata.custom
            ),
            audio: audioEntries
        )

        let manifestURL = directory.appendingPathComponent(FrameCollectionManifest.filename)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL)
        } catch {
            throw VideoFrameCollectionError.manifestWriteFailed(error)
        }
    }

    /// Loads a frame collection from a previously saved directory.
    ///
    /// Reads the manifest.json and loads frames in the correct order.
    ///
    /// Example:
    /// ```swift
    /// let collection = try await VideoFrameCollection.load(from: savedDirectory)
    /// print("Loaded \(collection.count) frames")
    /// ```
    ///
    /// - Parameters:
    ///   - directory: The directory containing the saved collection.
    ///   - loadImagesImmediately: If true, loads all images into memory as CGImages.
    ///     If false (default), stores URLs and loads on demand.
    ///   - progress: Optional progress callback (0.0 to 1.0).
    /// - Returns: The loaded frame collection.
    /// - Throws: `VideoFrameCollectionError` if loading fails.
    public static func load(
        from directory: URL,
        loadImagesImmediately: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> VideoFrameCollection {
        let manifestURL = directory.appendingPathComponent(FrameCollectionManifest.filename)

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw VideoFrameCollectionError.manifestNotFound
        }

        // Read manifest
        let manifest: FrameCollectionManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(FrameCollectionManifest.self, from: data)
        } catch {
            throw VideoFrameCollectionError.manifestReadFailed(error)
        }

        // Version check
        guard manifest.version <= FrameCollectionManifest.currentVersion else {
            throw VideoFrameCollectionError.unsupportedManifestVersion(manifest.version)
        }

        // Sort frames by index to ensure correct order
        let sortedFrames = manifest.frames.sorted { $0.index < $1.index }

        // Load frames
        var frames: [VideoFrame] = []
        frames.reserveCapacity(sortedFrames.count)

        for (progressIndex, entry) in sortedFrames.enumerated() {
            let frameURL = directory.appendingPathComponent(entry.filename)

            guard FileManager.default.fileExists(atPath: frameURL.path) else {
                throw VideoFrameCollectionError.frameReadFailed(filename: entry.filename)
            }

            if loadImagesImmediately {
                // Load CGImage immediately
                guard let source = CGImageSourceCreateWithURL(frameURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw VideoFrameCollectionError.frameReadFailed(filename: entry.filename)
                }
                frames.append(.cgImage(cgImage))
            } else {
                // Store URL for lazy loading
                frames.append(.url(frameURL))
            }

            progress?(Double(progressIndex + 1) / Double(sortedFrames.count))
        }

        // Reconstruct metadata
        let metadata = VideoFrameMetadata(
            sourceJobId: manifest.metadata.sourceJobId.flatMap { UUID(uuidString: $0) },
            prompt: manifest.metadata.prompt,
            negativePrompt: manifest.metadata.negativePrompt,
            model: manifest.metadata.model,
            seed: manifest.metadata.seed.flatMap(UInt32.init(exactly:)),
            generatedAt: manifest.metadata.generatedAt,
            custom: manifest.metadata.custom ?? [:]
        )

        // Load audio files if present
        var loadedAudio: [Data]? = nil
        if let audioEntries = manifest.audio, !audioEntries.isEmpty {
            let sortedAudio = audioEntries.sorted { $0.index < $1.index }
            var audioArray: [Data] = []
            for entry in sortedAudio {
                let audioURL = directory.appendingPathComponent(entry.filename)
                if FileManager.default.fileExists(atPath: audioURL.path) {
                    let wavData = try Data(contentsOf: audioURL)
                    audioArray.append(wavData)
                }
            }
            if !audioArray.isEmpty {
                loadedAudio = audioArray
            }
        }

        var collection = VideoFrameCollection()
        collection.frames = frames
        collection.metadata = metadata
        collection.audioData = loadedAudio
        return collection
    }

    /// Checks if a directory contains a valid saved frame collection.
    ///
    /// - Parameter directory: The directory to check.
    /// - Returns: True if the directory contains a valid manifest.
    public static func exists(at directory: URL) -> Bool {
        let manifestURL = directory.appendingPathComponent(FrameCollectionManifest.filename)
        return FileManager.default.fileExists(atPath: manifestURL.path)
    }

    /// Returns information about a saved collection without fully loading it.
    ///
    /// - Parameter directory: The directory containing the saved collection.
    /// - Returns: A tuple with frame count and metadata.
    /// - Throws: `VideoFrameCollectionError` if reading fails.
    public static func info(from directory: URL) async throws -> (frameCount: Int, metadata: VideoFrameMetadata) {
        let manifestURL = directory.appendingPathComponent(FrameCollectionManifest.filename)

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw VideoFrameCollectionError.manifestNotFound
        }

        let manifest: FrameCollectionManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(FrameCollectionManifest.self, from: data)
        } catch {
            throw VideoFrameCollectionError.manifestReadFailed(error)
        }

        let metadata = VideoFrameMetadata(
            sourceJobId: manifest.metadata.sourceJobId.flatMap { UUID(uuidString: $0) },
            prompt: manifest.metadata.prompt,
            negativePrompt: manifest.metadata.negativePrompt,
            model: manifest.metadata.model,
            seed: manifest.metadata.seed.flatMap(UInt32.init(exactly:)),
            generatedAt: manifest.metadata.generatedAt,
            custom: manifest.metadata.custom ?? [:]
        )

        return (manifest.frameCount, metadata)
    }

    // MARK: - Private Helpers

    /// Saves a CGImage to a file.
    private func saveImage(
        _ image: CGImage,
        to url: URL,
        format: FrameFormat,
        quality: Double
    ) throws {
        let uti: CFString
        var properties: [CFString: Any] = [:]

        switch format {
        case .png:
            uti = "public.png" as CFString
        case .jpeg:
            uti = "public.jpeg" as CFString
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            uti,
            1,
            nil
        ) else {
            throw NSError(
                domain: "VideoFrameCollection",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"]
            )
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(
                domain: "VideoFrameCollection",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image"]
            )
        }
    }
}
