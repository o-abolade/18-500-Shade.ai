//
//  MoveRequest.swift
//  Umbrella App
//
//  Request model for POST /move
//

import Foundation

/// Request body for POST /move
struct MoveRequest: Codable, Sendable {
    let direction: String
    let speed: Int?

    nonisolated init(direction: String, speed: Int? = nil) {
        self.direction = direction
        self.speed = speed
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        direction = try c.decode(String.self, forKey: .direction)
        speed = try c.decodeIfPresent(Int.self, forKey: .speed)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(direction, forKey: .direction)
        try c.encodeIfPresent(speed, forKey: .speed)
    }

    enum CodingKeys: String, CodingKey { case direction, speed }
}
