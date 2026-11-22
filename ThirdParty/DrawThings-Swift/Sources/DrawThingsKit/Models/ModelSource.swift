//
//  ModelSource.swift
//  DrawThingsKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation

/// Indicates where a model is available from.
public enum ModelSource: String, Codable, Sendable, CaseIterable {
    /// Model is installed locally on the Draw Things server.
    case local

    /// Official model available through Draw Things cloud service.
    /// These are the built-in models from ModelZoo (available on Community and DrawThings+ plans).
    case official

    /// Community-contributed model available through Draw Things cloud service.
    /// These are user-submitted models from the community-models repository.
    case community

    /// Display name for the source.
    public var displayName: String {
        switch self {
        case .local: return "Local"
        case .official: return "Official"
        case .community: return "Community"
        }
    }

    /// SF Symbol name for the source icon.
    public var iconName: String {
        switch self {
        case .local: return "internaldrive"
        case .official: return "checkmark.seal.fill"
        case .community: return "person.2.fill"
        }
    }
}
