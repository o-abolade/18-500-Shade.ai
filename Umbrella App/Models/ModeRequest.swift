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

    init(mode: String) {
        self.mode = mode
    }
}
