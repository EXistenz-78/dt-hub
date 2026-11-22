//
//  SavedConfiguration.swift
//  DrawThingsKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import SwiftData

/// A saved configuration preset that can be stored and retrieved.
///
/// Use with SwiftData to persist configuration presets:
/// ```swift
/// @Model
/// final class SavedConfiguration { ... }
///
/// // In your App:
/// .modelContainer(for: SavedConfiguration.self)
/// ```
@Model
public final class SavedConfiguration {
    public var id: UUID
    public var name: String
    public var tags: [String]
    public var configurationJSON: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        name: String,
        tags: [String] = [],
        configurationJSON: String
    ) {
        self.id = UUID()
        self.name = name
        self.tags = tags
        self.configurationJSON = configurationJSON
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Search helper - checks if name or any tag contains the query
    public func matches(query: String) -> Bool {
        let lowercasedQuery = query.lowercased()
        if name.lowercased().contains(lowercasedQuery) {
            return true
        }
        return tags.contains { $0.lowercased().contains(lowercasedQuery) }
    }
}
