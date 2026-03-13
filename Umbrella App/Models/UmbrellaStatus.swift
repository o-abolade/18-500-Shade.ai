//
//  UmbrellaStatus.swift
//  Umbrella App
//
//  Response model for GET /status
//

import Foundation

/// Response from GET /status
struct UmbrellaStatus: Codable, Sendable {
    let position: Int?
    let mode: String?
    let moving: Bool?
    let connected: Bool?

    enum CodingKeys: String, CodingKey {
        case position
        case mode
        case moving
        case connected
    }
}
