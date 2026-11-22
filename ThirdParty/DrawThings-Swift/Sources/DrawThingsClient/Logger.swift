//
//  Logger.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import os

/// Logging categories shared by DrawThingsClient and the packages built on it
/// (DrawThingsQueue, DrawThingsKit, DrawThingsVideoKit).
public enum DTLogCategory: String, CaseIterable, Sendable {
    case connection = "Connection"
    case queue = "Queue"
    case generation = "Generation"
    case grpc = "gRPC"
    case models = "Models"
    case configuration = "Configuration"
    case images = "Images"
    case video = "Video"
    case general = "General"
}

/// Log levels matching os.log levels.
public enum DTLogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case fault = 4
    /// Disables all logging when used as `minimumLevel`.
    case none = 5

    public static func < (lhs: DTLogLevel, rhs: DTLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning, .none: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .fault: return "💥"
        case .none: return ""
        }
    }
}

extension DTLogLevel {
    @available(*, deprecated, renamed: "warning")
    public static var notice: DTLogLevel { .warning }
}

/// Centralized logger for DrawThingsClient and the packages built on it.
///
/// Uses Apple's unified logging system (os.log) under the subsystem `com.drawthings`.
/// Logging is off by default; enable it from your app:
///
/// ```swift
/// DTLogger.minimumLevel = .debug
/// ```
///
/// Usage:
/// ```swift
/// DTLogger.debug("Starting connection", category: .connection)
/// DTLogger.info("Job enqueued: \(job.id)", category: .queue)
/// DTLogger.error("Failed to parse config: \(error)", category: .configuration)
///
/// // Log data payload (only in debug builds)
/// DTLogger.logData(requestData, label: "gRPC Request", category: .grpc)
/// ```
///
/// View logs in Terminal:
/// ```bash
/// log stream --predicate 'subsystem == "com.drawthings"' --level debug
/// ```
public final class DTLogger: Sendable {
    /// Shared instance
    public static let shared = DTLogger()

    /// The subsystem identifier for os.log
    public static let subsystem = "com.drawthings"

    private struct Settings {
        var minimumLevel: DTLogLevel = .none
        var isEnabled = true
        var includeTimestamps = true
        var useEmoji = true
        var logToConsole: Bool = {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }()
    }

    private let settings = OSAllocatedUnfairLock(initialState: Settings())

    private static let loggers: [DTLogCategory: Logger] = Dictionary(
        uniqueKeysWithValues: DTLogCategory.allCases.map {
            ($0, Logger(subsystem: subsystem, category: $0.rawValue))
        }
    )

    private static let timestampStyle = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
        timeZone: .current,
        calendar: .current
    )

    private init() {}

    // MARK: - Configuration

    /// Minimum log level (messages below this level are ignored).
    /// Defaults to `.none`, so libraries stay silent until the app opts in.
    public var minimumLevel: DTLogLevel {
        get { settings.withLock { $0.minimumLevel } }
        set { settings.withLock { $0.minimumLevel = newValue } }
    }

    /// Whether logging is enabled
    public var isEnabled: Bool {
        get { settings.withLock { $0.isEnabled } }
        set { settings.withLock { $0.isEnabled = newValue } }
    }

    /// Whether to include timestamps in console output
    public var includeTimestamps: Bool {
        get { settings.withLock { $0.includeTimestamps } }
        set { settings.withLock { $0.includeTimestamps = newValue } }
    }

    /// Whether to prefix console output with a level emoji
    public var useEmoji: Bool {
        get { settings.withLock { $0.useEmoji } }
        set { settings.withLock { $0.useEmoji = newValue } }
    }

    /// Whether to log to console (print) in addition to os.log.
    /// Useful for Xcode console visibility. Defaults to true in DEBUG builds.
    public var logToConsole: Bool {
        get { settings.withLock { $0.logToConsole } }
        set { settings.withLock { $0.logToConsole = newValue } }
    }

    /// Shorthand for `DTLogger.shared.minimumLevel`.
    public static var minimumLevel: DTLogLevel {
        get { shared.minimumLevel }
        set { shared.minimumLevel = newValue }
    }

    /// Whether a message at `level` would currently be logged.
    public static func isLogging(_ level: DTLogLevel) -> Bool {
        shared.settings.withLock { $0.isEnabled && level != .none && level >= $0.minimumLevel }
    }

    // MARK: - Public Logging Methods

    /// Log a debug message (verbose, for development)
    public static func debug(
        _ message: @autoclosure () -> String,
        category: DTLogCategory = .general,
        file: String = #fileID,
        line: Int = #line
    ) {
        shared.log(level: .debug, message: message, category: category, file: file, line: line)
    }

    /// Log an info message (general information)
    public static func info(
        _ message: @autoclosure () -> String,
        category: DTLogCategory = .general,
        file: String = #fileID,
        line: Int = #line
    ) {
        shared.log(level: .info, message: message, category: category, file: file, line: line)
    }

    /// Log a warning message (potential issues)
    public static func warning(
        _ message: @autoclosure () -> String,
        category: DTLogCategory = .general,
        file: String = #fileID,
        line: Int = #line
    ) {
        shared.log(level: .warning, message: message, category: category, file: file, line: line)
    }

    /// Log an error message (recoverable errors)
    public static func error(
        _ message: @autoclosure () -> String,
        category: DTLogCategory = .general,
        file: String = #fileID,
        line: Int = #line
    ) {
        shared.log(level: .error, message: message, category: category, file: file, line: line)
    }

    /// Log a fault message (critical, unrecoverable errors)
    public static func fault(
        _ message: @autoclosure () -> String,
        category: DTLogCategory = .general,
        file: String = #fileID,
        line: Int = #line
    ) {
        shared.log(level: .fault, message: message, category: category, file: file, line: line)
    }

    // MARK: - Data Logging

    /// Log binary data with a label (only in DEBUG builds)
    /// Useful for logging gRPC request/response payloads
    public static func logData(
        _ data: Data?,
        label: String,
        category: DTLogCategory = .grpc,
        maxBytes: Int = 1024
    ) {
        #if DEBUG
        guard isLogging(.debug) else { return }

        guard let data = data else {
            debug("\(label): <nil>", category: category)
            return
        }

        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary)
        var message = "\(label): \(sizeStr)"
        let hexString = data.prefix(maxBytes).map { String(format: "%02x", $0) }.joined(separator: " ")

        if data.count <= maxBytes {
            message += "\n  Hex: \(hexString)"

            // Try to show as UTF-8 string if valid
            if let string = String(data: data, encoding: .utf8), string.count < 500 {
                let escaped = string.replacingOccurrences(of: "\n", with: "\\n")
                message += "\n  UTF8: \(escaped)"
            }
        } else {
            message += " (truncated, showing first \(maxBytes) bytes)"
            message += "\n  Hex: \(hexString)..."
        }

        debug(message, category: category)
        #endif
    }

    /// Log a dictionary/JSON structure (only in DEBUG builds)
    public static func logJSON(
        _ dict: [String: Any],
        label: String,
        category: DTLogCategory = .general
    ) {
        #if DEBUG
        guard isLogging(.debug) else { return }

        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            debug("\(label):\n\(jsonString)", category: category)
        } else {
            debug("\(label): \(dict)", category: category)
        }
        #endif
    }

    /// Log a DrawThingsConfiguration JSON string (only in DEBUG builds)
    public static func logConfiguration(
        _ json: String,
        label: String = "Configuration",
        category: DTLogCategory = .configuration
    ) {
        #if DEBUG
        guard isLogging(.debug) else { return }

        if let data = json.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            debug("\(label):\n\(prettyString)", category: category)
        } else {
            debug("\(label): \(json)", category: category)
        }
        #endif
    }

    // MARK: - Scoped Logging

    /// Log the start of an operation.
    /// Returns a closure that logs its completion with the elapsed time.
    public static func startOperation(
        _ name: String,
        category: DTLogCategory = .general
    ) -> @Sendable () -> Void {
        let startTime = CFAbsoluteTimeGetCurrent()
        info("▶ \(name) started", category: category)

        return {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let durationStr = String(format: "%.2fms", duration * 1000)
            info("◀ \(name) completed in \(durationStr)", category: category)
        }
    }

    /// Log entry into a function (debug level)
    public static func enter(
        _ function: String = #function,
        category: DTLogCategory = .general
    ) {
        debug("→ \(function)", category: category)
    }

    /// Log exit from a function (debug level)
    public static func exit(
        _ function: String = #function,
        category: DTLogCategory = .general
    ) {
        debug("← \(function)", category: category)
    }

    // MARK: - Private Implementation

    private func log(
        level: DTLogLevel,
        message: () -> String,
        category: DTLogCategory,
        file: String,
        line: Int
    ) {
        let current = settings.withLock { $0 }
        guard current.isEnabled, level != .none, level >= current.minimumLevel else { return }

        let message = message()
        let logger = Self.loggers[category] ?? Logger(subsystem: Self.subsystem, category: category.rawValue)
        logger.log(level: level.osLogType, "\(message, privacy: .public)")

        if current.logToConsole {
            let timestamp = current.includeTimestamps ? "[\(Date().formatted(Self.timestampStyle))] " : ""
            let emoji = current.useEmoji ? "\(level.emoji) " : ""
            let fileName = (file as NSString).lastPathComponent
            print("\(timestamp)\(emoji)[\(category.rawValue)] \(message) (\(fileName):\(line))")
        }
    }
}

// MARK: - Deprecated

/// Previous logging entry point for DrawThingsClient. Use `DTLogger` instead.
@available(*, deprecated, message: "Use DTLogger; set DTLogger.minimumLevel to enable logging")
public enum DrawThingsClientLogger {
    public typealias Level = DTLogLevel

    public static var minimumLevel: DTLogLevel {
        get { DTLogger.minimumLevel }
        set { DTLogger.minimumLevel = newValue }
    }

    public static var useEmoji: Bool {
        get { DTLogger.shared.useEmoji }
        set { DTLogger.shared.useEmoji = newValue }
    }
}
