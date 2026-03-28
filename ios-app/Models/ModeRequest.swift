//
//  ModeRequest.swift
//  Umbrella App
//
//  Request model for POST /mode
//

import Foundation

/// Request body for POST /mode
struct ModeRequest: Codable, Sendable {
    let mode: String

    nonisolated init(mode: String) {
        self.mode = mode
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decode(String.self, forKey: .mode)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
    }

    enum CodingKeys: String, CodingKey { case mode }
}
