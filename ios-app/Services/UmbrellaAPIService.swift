//
//  UmbrellaAPIService.swift
//  Umbrella App
//
//  HTTP JSON API client for Raspberry Pi umbrella control.
//  Requires NSAllowsLocalNetworking in Info.plist for local HTTP (see ATS notes).
//

import Foundation

enum UmbrellaAPIError: Error, Sendable {
    case invalidURL
    case network(Error)
    case invalidResponse
    case decoding(Error)
}

actor UmbrellaAPIService: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    /// GET /status
    func fetchStatus() async throws -> UmbrellaStatus {
        let url = baseURL.appendingPathComponent("status")
        let (data, response) = try await performRequest(url: url, method: "GET")
        try validateResponse(response, data: data)
        return try decoder.decode(UmbrellaStatus.self, from: data)
    }

    /// POST /move
    func move(direction: String, speed: Int? = nil) async throws {
        let url = baseURL.appendingPathComponent("move")
        let body = MoveRequest(direction: direction, speed: speed)
        let (data, response) = try await performPost(url: url, body: body)
        try validateResponse(response, data: data)
    }

    /// POST /stop
    func stop() async throws {
        let url = baseURL.appendingPathComponent("stop")
        let (_, response) = try await performRequest(url: url, method: "POST")
        try validateResponse(response, data: nil)
    }

    /// POST /mode
    func setMode(_ mode: String) async throws {
        let url = baseURL.appendingPathComponent("mode")
        let body = ModeRequest(mode: mode)
        let (data, response) = try await performPost(url: url, body: body)
        try validateResponse(response, data: data)
    }

    private func performRequest(url: URL, method: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            return try await session.data(for: request)
        } catch {
            throw UmbrellaAPIError.network(error)
        }
    }

    private func performPost<T: Encodable>(url: URL, body: T) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        do {
            return try await session.data(for: request)
        } catch {
            throw UmbrellaAPIError.network(error)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw UmbrellaAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw UmbrellaAPIError.invalidResponse
        }
    }
}
