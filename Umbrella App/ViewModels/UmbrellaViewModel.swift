//
//  UmbrellaViewModel.swift
//  Umbrella App
//
//  MVVM ViewModel for umbrella connection and control.
//

import Foundation

enum ConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

@MainActor
final class UmbrellaViewModel: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var status: UmbrellaStatus?
    @Published private(set) var lastError: String?

    @Published var host: String = "192.168.1.100"
    @Published var port: Int = 8080

    private var apiService: UmbrellaAPIService?
    private var pollingTask: Task<Void, Never>?
    private let pollingInterval: TimeInterval = 2.0

    private var moveDebounceTask: Task<Void, Never>?
    private let moveDebounceInterval: TimeInterval = 0.15

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var baseURL: URL? {
        guard case .connected = connectionState else { return nil }
        return URL(string: "http://\(host):\(port)")
    }

    func connect() async {
        connectionState = .connecting
        lastError = nil

        guard let url = URL(string: "http://\(host):\(port)") else {
            connectionState = .error("Invalid host or port")
            return
        }

        let service = UmbrellaAPIService(baseURL: url)
        apiService = service

        do {
            _ = try await service.fetchStatus()
            connectionState = .connected
            startPolling()
        } catch {
            connectionState = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        stopPolling()
        moveDebounceTask?.cancel()
        moveDebounceTask = nil
        apiService = nil
        connectionState = .disconnected
        status = nil
        lastError = nil
    }

    func move(direction: String) {
        moveDebounceTask?.cancel()
        moveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(moveDebounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await sendMove(direction: direction)
        }
    }

    func moveImmediate(direction: String) async {
        moveDebounceTask?.cancel()
        moveDebounceTask = nil
        await sendMove(direction: direction)
    }

    func stop() async {
        moveDebounceTask?.cancel()
        moveDebounceTask = nil
        guard let service = apiService else { return }
        do {
            try await service.stop()
            await refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setMode(_ mode: String) async {
        guard let service = apiService else { return }
        do {
            try await service.setMode(mode)
            await refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshStatus() async {
        guard let service = apiService else { return }
        do {
            let s = try await service.fetchStatus()
            status = s
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func sendMove(direction: String) async {
        guard let service = apiService else { return }
        do {
            try await service.move(direction: direction)
            await refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startPolling() {
        stopPolling()
        pollingTask = Task { @MainActor in
            while !Task.isCancelled {
                await refreshStatus()
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
