//
//  UmbrellaViewModel.swift
//  Umbrella App
//
//  MVVM ViewModel for umbrella connection and control.
//

import Combine
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
    @Published private(set) var bluetoothStateDescription = "Starting Bluetooth..."
    @Published private(set) var discoveredDeviceName: String?
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var isScanning = false

    private let bleManager: UmbrellaBLEManager
    private var cancellables = Set<AnyCancellable>()
    private var moveDebounceTask: Task<Void, Never>?
    private let moveDebounceInterval: TimeInterval = 0.15

    init(bleManager: UmbrellaBLEManager? = nil) {
        self.bleManager = bleManager ?? UmbrellaBLEManager()
        bindBLEManager()
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var isUsingDemoMode: Bool {
        false
    }

    var canConnect: Bool {
        !isScanning
    }

    var connectionStateText: String {
        switch connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return isScanning ? "Scanning for Raspberry Pi…" : "Connecting…"
        case .connected:
            return connectedDeviceName ?? "Connected"
        case .error(let message):
            return message
        }
    }

    var connectionSubtitle: String {
        if let connectedDeviceName, isConnected {
            return "Connected to \(connectedDeviceName)"
        }

        if let discoveredDeviceName, isScanning {
            return "Found \(discoveredDeviceName)"
        }

        return bluetoothStateDescription
    }

    var preferredDeviceName: String {
        connectedDeviceName ?? discoveredDeviceName ?? UmbrellaBLEConstants.advertisedName
    }

    func connect() async {
        lastError = nil
        bleManager.connect()
    }

    func scanForDevices() {
        lastError = nil
        bleManager.startScanning()
    }

    func disconnect() {
        moveDebounceTask?.cancel()
        moveDebounceTask = nil
        bleManager.disconnect()
    }

    func move(direction: String) {
        moveDebounceTask?.cancel()
        moveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(moveDebounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            bleManager.move(direction: direction)
        }
    }

    func moveImmediate(direction: String) async {
        moveDebounceTask?.cancel()
        moveDebounceTask = nil
        bleManager.move(direction: direction)
    }

    func stop() async {
        moveDebounceTask?.cancel()
        moveDebounceTask = nil
        bleManager.stop()
    }

    func setMode(_ mode: String) async {
        bleManager.setMode(mode)
    }

    func refreshStatus() async {
        bleManager.requestStatus()
    }

    private func bindBLEManager() {
        bleManager.$status
            .sink { [weak self] in
                self?.status = $0
            }
            .store(in: &cancellables)

        bleManager.$lastError
            .sink { [weak self] in
                self?.lastError = $0
            }
            .store(in: &cancellables)

        bleManager.$bluetoothStateDescription
            .sink { [weak self] in
                self?.bluetoothStateDescription = $0
            }
            .store(in: &cancellables)

        bleManager.$discoveredDeviceName
            .sink { [weak self] in
                self?.discoveredDeviceName = $0
            }
            .store(in: &cancellables)

        bleManager.$connectedDeviceName
            .sink { [weak self] in
                self?.connectedDeviceName = $0
            }
            .store(in: &cancellables)

        bleManager.$isScanning
            .sink { [weak self] in
                self?.isScanning = $0
            }
            .store(in: &cancellables)

        bleManager.$connectionPhase
            .sink { [weak self] phase in
                self?.apply(connectionPhase: phase)
            }
            .store(in: &cancellables)
    }

    private func apply(connectionPhase: UmbrellaBLEConnectionPhase) {
        switch connectionPhase {
        case .unavailable(let message):
            connectionState = .error(message)
        case .disconnected:
            connectionState = .disconnected
        case .scanning, .connecting:
            connectionState = .connecting
        case .connected:
            connectionState = .connected
        }
    }
}
