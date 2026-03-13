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

    init(direction: String, speed: Int? = nil) {
        self.direction = direction
        self.speed = speed
    }
}
