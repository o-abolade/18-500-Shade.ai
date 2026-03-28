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

    init(position: Int?, mode: String?, moving: Bool?, connected: Bool?) {
        self.position = position
        self.mode = mode
        self.moving = moving
        self.connected = connected
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(Int.self, forKey: .position)
        mode = try c.decodeIfPresent(String.self, forKey: .mode)
        moving = try c.decodeIfPresent(Bool.self, forKey: .moving)
        connected = try c.decodeIfPresent(Bool.self, forKey: .connected)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(position, forKey: .position)
        try c.encodeIfPresent(mode, forKey: .mode)
        try c.encodeIfPresent(moving, forKey: .moving)
        try c.encodeIfPresent(connected, forKey: .connected)
    }
}
