//
//  QueueStorage.swift
//  DrawThingsQueue
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import DrawThingsClient
import Foundation
import SwiftProtobuf

/// Saves a ``GenerationQueue``'s pending jobs to a JSON file so they survive a relaunch.
///
/// Requests are saved whole: the configuration as Draw Things JSON, input images and masks as
/// PNG, and hints and metadata overrides as protobuf. Encoding runs on this actor, off the main
/// actor.
public actor QueueStorage {
    /// The file jobs are saved to.
    public nonisolated let fileURL: URL
    private var writtenGeneration = 0

    /// Creates storage at a file URL. The default is
    /// `Application Support/DrawThingsQueue/queue.json`, where DrawThingsQueue 0.x saved its queue.
    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = URL.applicationSupportDirectory
            self.fileURL = appSupport.appending(components: "DrawThingsQueue", "queue.json")
        }
    }

    /// Writes the jobs, unless a newer save has already been written.
    func save(_ jobs: [QueueJob], generation: Int) {
        guard generation > writtenGeneration else { return }
        writtenGeneration = generation
        do {
            let file = SavedQueue(jobs: try jobs.map(SavedJob.init))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(file)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            DTLogger.error("Couldn't save the queue: \(error.localizedDescription)", category: .queue)
        }
    }

    /// Reads the saved jobs. Returns an empty list when nothing has been saved.
    public func load() throws -> [QueueJob] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // DrawThingsQueue 0.x wrote a bare array.
        if let legacy = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return try LegacyQueueFile.jobs(from: legacy)
        }
        return try decoder.decode(SavedQueue.self, from: data).jobs.map { try $0.job() }
    }

    /// Deletes the saved file.
    public func clear() throws {
        writtenGeneration += 1
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

// MARK: - File format

private struct SavedQueue: Codable {
    var version = 2
    var jobs: [SavedJob]
}

private struct SavedJob: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var retryCount: Int
    var prompt: String
    var negativePrompt: String
    var configuration: DrawThingsConfiguration
    var image: Data?
    var mask: Data?
    var hints: [Data]
    var override: Data?
    var modelFamily: String?
    var audioSampleRate: Double?

    init(_ job: QueueJob) throws {
        let request = job.request
        id = job.id
        name = job.name
        createdAt = job.createdAt
        retryCount = job.retryCount
        prompt = request.prompt
        negativePrompt = request.negativePrompt
        configuration = request.configuration
        image = try request.image.map(ImageHelpers.pngData(for:))
        mask = try request.mask.map(ImageHelpers.pngData(for:))
        hints = try request.hints.map { try $0.serializedData() }
        override = try request.override.map { try $0.serializedData() }
        modelFamily = request.modelFamily?.rawValue
        audioSampleRate = request.audioSampleRate
    }

    func job() throws -> QueueJob {
        let request = GenerationRequest(
            id: id,
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: configuration,
            image: try image.map(ImageHelpers.decodeCGImage),
            mask: try mask.map(ImageHelpers.decodeCGImage),
            hints: try hints.map { try HintProto(serializedBytes: $0) },
            override: try override.map { try MetadataOverride(serializedBytes: $0) },
            modelFamily: modelFamily.flatMap(ModelFamily.init(rawValue:)),
            audioSampleRate: audioSampleRate
        )
        return QueueJob(request: request, name: name, createdAt: createdAt, retryCount: retryCount)
    }
}

/// Reads the array DrawThingsQueue 0.x saved: prompts and configuration only, with the
/// configuration's Swift property names as keys.
enum LegacyQueueFile {
    static func jobs(from entries: [[String: Any]]) throws -> [QueueJob] {
        let dateFormatter = ISO8601DateFormatter()
        return try entries.map { entry in
            guard let idString = entry["id"] as? String, let id = UUID(uuidString: idString),
                  let configuration = entry["configuration"] as? [String: Any] else {
                throw DrawThingsError.decodingFailed("unreadable job in a DrawThingsQueue 0.x file")
            }
            let request = GenerationRequest(
                id: id,
                prompt: entry["prompt"] as? String ?? "",
                negativePrompt: entry["negativePrompt"] as? String ?? "",
                configuration: try self.configuration(from: configuration)
            )
            let createdAt = (entry["createdAt"] as? String).flatMap(dateFormatter.date(from:)) ?? Date()
            return QueueJob(request: request, name: entry["name"] as? String, createdAt: createdAt)
        }
    }

    /// Converts the 0.x keys to Draw Things JSON and decodes that.
    static func configuration(from legacy: [String: Any]) throws -> DrawThingsConfiguration {
        var json = legacy
        json["name"] = legacy["configName"]
        json["configName"] = nil
        if let method = legacy["compressionArtifacts"] as? Int {
            json["compressionArtifacts"] = ["disabled", "h264", "h265", "jpeg"].indices.contains(method)
                ? ["disabled", "h264", "h265", "jpeg"][method] : "disabled"
        }
        if let calibration = legacy["colorCalibration"] as? Int {
            json["colorCalibration"] = calibration == 1 ? "lab" : "none"
        }
        // Draw Things JSON has no separate switch: 0 frames means off.
        if legacy["causalInferenceEnabled"] as? Bool == false {
            json["causalInference"] = 0
        }
        json["causalInferenceEnabled"] = nil
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(DrawThingsConfiguration.self, from: data)
    }
}
