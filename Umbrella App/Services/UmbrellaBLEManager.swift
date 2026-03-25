//
//  UmbrellaBLEManager.swift
//  Umbrella App
//
//  CoreBluetooth transport for umbrella control.
//

import Combine
import CoreBluetooth
import Foundation

enum UmbrellaBLEConnectionPhase: Equatable {
    case unavailable(String)
    case disconnected
    case scanning
    case connecting(String?)
    case connected(String)
}

enum UmbrellaBLECommandType: String, Codable, Sendable {
    case move
    case stop
    case mode
}

struct UmbrellaBLECommand: Codable, Sendable {
    let type: UmbrellaBLECommandType
    let direction: String?
    let value: String?
    let speed: Int?

    static func move(direction: String, speed: Int? = nil) -> Self {
        Self(type: .move, direction: direction, value: nil, speed: speed)
    }

    static func stop() -> Self {
        Self(type: .stop, direction: nil, value: nil, speed: nil)
    }

    static func mode(_ value: String) -> Self {
        Self(type: .mode, direction: nil, value: value, speed: nil)
    }
}

@MainActor
final class UmbrellaBLEManager: NSObject, ObservableObject {
    @Published private(set) var connectionPhase: UmbrellaBLEConnectionPhase = .disconnected
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothStateDescription = "Starting Bluetooth..."
    @Published private(set) var discoveredDeviceName: String?
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var status: UmbrellaStatus?
    @Published private(set) var lastError: String?

    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var connectedPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var scanTimeoutTask: Task<Void, Never>?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    var isBluetoothReady: Bool {
        centralManager.state == .poweredOn
    }

    func connect() {
        lastError = nil

        guard centralManager.state == .poweredOn else {
            handleBluetoothUnavailable()
            return
        }

        if let discoveredPeripheral {
            connect(to: discoveredPeripheral)
            return
        }

        startScanning()
    }

    func startScanning() {
        lastError = nil

        guard centralManager.state == .poweredOn else {
            handleBluetoothUnavailable()
            return
        }

        discoveredPeripheral = nil
        discoveredDeviceName = nil
        connectedDeviceName = nil
        commandCharacteristic = nil
        statusCharacteristic = nil
        status = nil
        isScanning = true
        connectionPhase = .scanning

        centralManager.stopScan()
        centralManager.scanForPeripherals(
            withServices: [UmbrellaBLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        scheduleScanTimeout()
    }

    func disconnect() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        isScanning = false
        centralManager.stopScan()

        if let connectedPeripheral {
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        } else {
            resetConnectionState()
            connectionPhase = .disconnected
        }
    }

    func requestStatus() {
        guard let connectedPeripheral, let statusCharacteristic else { return }
        connectedPeripheral.readValue(for: statusCharacteristic)
    }

    func move(direction: String, speed: Int? = nil) {
        send(command: .move(direction: direction, speed: speed))
    }

    func stop() {
        send(command: .stop())
    }

    func setMode(_ mode: String) {
        send(command: .mode(mode))
    }

    private func send(command: UmbrellaBLECommand) {
        guard
            let connectedPeripheral,
            let commandCharacteristic
        else {
            lastError = "Bluetooth device is not connected yet."
            return
        }

        do {
            let data = try encoder.encode(command)
            connectedPeripheral.writeValue(data, for: commandCharacteristic, type: .withResponse)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func connect(to peripheral: CBPeripheral) {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        isScanning = false
        centralManager.stopScan()

        discoveredPeripheral = peripheral
        discoveredDeviceName = resolvedName(for: peripheral)
        connectionPhase = .connecting(discoveredDeviceName)
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    private func scheduleScanTimeout() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, isScanning else { return }
            centralManager.stopScan()
            isScanning = false
            connectionPhase = .errorState("No umbrella device found nearby.")
            lastError = "No umbrella device found nearby."
        }
    }

    private func resetConnectionState() {
        discoveredPeripheral = nil
        connectedPeripheral = nil
        commandCharacteristic = nil
        statusCharacteristic = nil
        connectedDeviceName = nil
        isScanning = false
        status = nil
    }

    private func handleBluetoothUnavailable() {
        let message: String

        switch centralManager.state {
        case .poweredOff:
            message = "Bluetooth is turned off."
        case .unauthorized:
            message = "Bluetooth permission is not granted."
        case .unsupported:
            message = "Bluetooth LE is not supported on this device."
        case .resetting:
            message = "Bluetooth is resetting."
        case .unknown:
            message = "Bluetooth state is unknown."
        @unknown default:
            message = "Bluetooth is unavailable."
        }

        bluetoothStateDescription = message
        connectionPhase = .unavailable(message)
        lastError = message
    }

    private func resolvedName(for peripheral: CBPeripheral) -> String {
        peripheral.name ?? discoveredDeviceName ?? UmbrellaBLEConstants.advertisedName
    }

    private func updateStatus(from data: Data?) {
        guard let data else { return }

        do {
            let decoded = try decoder.decode(UmbrellaStatus.self, from: data)
            status = decoded
            lastError = nil
        } catch {
            lastError = "Failed to decode status from Bluetooth."
        }
    }
}

extension UmbrellaBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                bluetoothStateDescription = "Bluetooth is ready."
                if case .unavailable = connectionPhase {
                    connectionPhase = .disconnected
                }
            case .poweredOff:
                resetConnectionState()
                handleBluetoothUnavailable()
            case .unauthorized, .unsupported, .resetting, .unknown:
                resetConnectionState()
                handleBluetoothUnavailable()
            @unknown default:
                resetConnectionState()
                handleBluetoothUnavailable()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            discoveredPeripheral = peripheral
            discoveredDeviceName = resolvedName(for: peripheral)
            connect(to: peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectedPeripheral = peripheral
            connectedDeviceName = resolvedName(for: peripheral)
            connectionPhase = .connecting(connectedDeviceName)
            peripheral.discoverServices([UmbrellaBLEConstants.serviceUUID])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            resetConnectionState()
            let message = error?.localizedDescription ?? "Failed to connect to the umbrella device."
            connectionPhase = .unavailable(message)
            lastError = message
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            resetConnectionState()
            if let error {
                lastError = error.localizedDescription
                connectionPhase = .unavailable(error.localizedDescription)
            } else {
                connectionPhase = .disconnected
            }
        }
    }
}

extension UmbrellaBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                lastError = error.localizedDescription
                connectionPhase = .unavailable(error.localizedDescription)
                return
            }

            guard let service = peripheral.services?.first(where: { $0.uuid == UmbrellaBLEConstants.serviceUUID }) else {
                let message = "Umbrella BLE service was not found."
                lastError = message
                connectionPhase = .unavailable(message)
                return
            }

            peripheral.discoverCharacteristics(
                [
                    UmbrellaBLEConstants.commandCharacteristicUUID,
                    UmbrellaBLEConstants.statusCharacteristicUUID
                ],
                for: service
            )
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                lastError = error.localizedDescription
                connectionPhase = .unavailable(error.localizedDescription)
                return
            }

            commandCharacteristic = service.characteristics?.first(where: {
                $0.uuid == UmbrellaBLEConstants.commandCharacteristicUUID
            })
            statusCharacteristic = service.characteristics?.first(where: {
                $0.uuid == UmbrellaBLEConstants.statusCharacteristicUUID
            })

            guard let statusCharacteristic else {
                let message = "Umbrella status characteristic is missing."
                lastError = message
                connectionPhase = .unavailable(message)
                return
            }

            connectedDeviceName = resolvedName(for: peripheral)
            connectionPhase = .connected(connectedDeviceName ?? UmbrellaBLEConstants.advertisedName)
            peripheral.setNotifyValue(true, for: statusCharacteristic)
            peripheral.readValue(for: statusCharacteristic)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                lastError = error.localizedDescription
                return
            }

            if characteristic.uuid == UmbrellaBLEConstants.statusCharacteristicUUID {
                updateStatus(from: characteristic.value)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                lastError = error.localizedDescription
                return
            }

            if characteristic.uuid == UmbrellaBLEConstants.commandCharacteristicUUID {
                requestStatus()
            }
        }
    }
}

private extension UmbrellaBLEConnectionPhase {
    static func errorState(_ message: String) -> Self {
        .unavailable(message)
    }
}
