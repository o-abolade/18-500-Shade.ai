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
    case location
}

struct UmbrellaBLECommand: Codable, Sendable {
    let type: UmbrellaBLECommandType
    let direction: String?
    let value: String?
    let speed: Int?
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?
    let timestamp: String?

    static func move(direction: String, speed: Int? = nil) -> Self {
        Self(
            type: .move,
            direction: direction,
            value: nil,
            speed: speed,
            latitude: nil,
            longitude: nil,
            accuracy: nil,
            timestamp: nil
        )
    }

    static func stop() -> Self {
        Self(
            type: .stop,
            direction: nil,
            value: nil,
            speed: nil,
            latitude: nil,
            longitude: nil,
            accuracy: nil,
            timestamp: nil
        )
    }

    static func mode(_ value: String) -> Self {
        Self(
            type: .mode,
            direction: nil,
            value: value,
            speed: nil,
            latitude: nil,
            longitude: nil,
            accuracy: nil,
            timestamp: nil
        )
    }

    static func location(latitude: Double, longitude: Double, accuracy: Double, timestamp: String) -> Self {
        Self(
            type: .location,
            direction: nil,
            value: nil,
            speed: nil,
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            timestamp: timestamp
        )
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
    private var connectionTimeoutTask: Task<Void, Never>?
    private var hasRetriedServiceDiscovery = false

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
        hasRetriedServiceDiscovery = false
        status = nil
        isScanning = true
        connectionPhase = .scanning
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil

        centralManager.stopScan()
        // Scan broadly, then filter by advertised service or device name.
        // Some Pi BLE stacks do not consistently advertise the custom service UUID.
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        scheduleScanTimeout()
    }

    func disconnect() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
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

    func sendLocation(latitude: Double, longitude: Double, accuracy: Double, timestamp: String) {
        send(command: .location(
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            timestamp: timestamp
        ))
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
        scheduleConnectionTimeout()
    }

    private func scheduleScanTimeout() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, isScanning else { return }
            centralManager.stopScan()
            isScanning = false
            connectionPhase = .errorState("No umbrella device found nearby.")
            lastError = "No umbrella device found nearby."
        }
    }

    private func isMatchingUmbrellaPeripheral(
        _ peripheral: CBPeripheral,
        advertisementData: [String: Any]
    ) -> Bool {
        if resolvedName(for: peripheral).caseInsensitiveCompare(UmbrellaBLEConstants.advertisedName) == .orderedSame {
            return true
        }

        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           localName.caseInsensitiveCompare(UmbrellaBLEConstants.advertisedName) == .orderedSame {
            return true
        }

        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            return serviceUUIDs.contains(UmbrellaBLEConstants.serviceUUID)
        }

        return false
    }

    private func resetConnectionState() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        discoveredPeripheral = nil
        connectedPeripheral = nil
        commandCharacteristic = nil
        statusCharacteristic = nil
        hasRetriedServiceDiscovery = false
        connectedDeviceName = nil
        isScanning = false
        status = nil
    }

    private func handleBluetoothUnavailable() {
        let message: String

        switch centralManager.state {
        case .poweredOn:
            message = "Bluetooth is ready."
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

    private func scheduleConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            guard case .connecting = connectionPhase else { return }

            if let connectedPeripheral, !hasRetriedServiceDiscovery {
                hasRetriedServiceDiscovery = true
                print("BLE retrying service discovery for \(resolvedName(for: connectedPeripheral))")
                connectedPeripheral.discoverServices(nil)
                scheduleConnectionTimeout()
                return
            }

            let message = "Connected to UmbrellaPi, but service discovery did not finish. Check that the Pi is running the latest ble_server.py."
            lastError = message
            connectionPhase = .unavailable(message)

            if let connectedPeripheral {
                centralManager.cancelPeripheralConnection(connectedPeripheral)
            } else {
                resetConnectionState()
            }
        }
    }

    private func chooseCommandCharacteristic(from characteristics: [CBCharacteristic]) -> CBCharacteristic? {
        if let exactMatch = characteristics.first(where: { $0.uuid == UmbrellaBLEConstants.commandCharacteristicUUID }) {
            return exactMatch
        }

        return characteristics.first(where: {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        })
    }

    private func chooseStatusCharacteristic(from characteristics: [CBCharacteristic]) -> CBCharacteristic? {
        if let exactMatch = characteristics.first(where: { $0.uuid == UmbrellaBLEConstants.statusCharacteristicUUID }) {
            return exactMatch
        }

        return characteristics.first(where: {
            $0.properties.contains(.notify) || $0.properties.contains(.read)
        })
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
            guard isMatchingUmbrellaPeripheral(peripheral, advertisementData: advertisementData) else {
                return
            }
            discoveredPeripheral = peripheral
            discoveredDeviceName = resolvedName(for: peripheral)
            connect(to: peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            print("BLE didConnect: \(resolvedName(for: peripheral))")
            connectedPeripheral = peripheral
            connectedDeviceName = resolvedName(for: peripheral)
            connectionPhase = .connecting(connectedDeviceName)
            peripheral.discoverServices(nil)
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

            guard let services = peripheral.services, !services.isEmpty else {
                let message = "Umbrella BLE service was not found."
                lastError = message
                connectionPhase = .unavailable(message)
                return
            }

            print("BLE discovered services: \(services.map { $0.uuid.uuidString })")

            let matchingServices = services.filter { $0.uuid == UmbrellaBLEConstants.serviceUUID }
            let servicesToInspect = matchingServices.isEmpty ? services : matchingServices

            for service in servicesToInspect {
                peripheral.discoverCharacteristics(nil, for: service)
            }
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

            let discoveredCharacteristics = service.characteristics ?? []
            print(
                "BLE discovered characteristics for \(service.uuid.uuidString): " +
                "\(discoveredCharacteristics.map { "\($0.uuid.uuidString) [\($0.properties.rawValue)]" })"
            )

            if commandCharacteristic == nil {
                commandCharacteristic = chooseCommandCharacteristic(from: discoveredCharacteristics)
            }

            if statusCharacteristic == nil {
                statusCharacteristic = chooseStatusCharacteristic(from: discoveredCharacteristics)
            }

            if let statusCharacteristic, commandCharacteristic != nil {
                connectionTimeoutTask?.cancel()
                connectionTimeoutTask = nil
                connectedDeviceName = resolvedName(for: peripheral)
                connectionPhase = .connected(connectedDeviceName ?? UmbrellaBLEConstants.advertisedName)
                peripheral.setNotifyValue(true, for: statusCharacteristic)
                peripheral.readValue(for: statusCharacteristic)
            } else if peripheral.services?.allSatisfy({ $0.characteristics != nil }) == true {
                let message = "Umbrella BLE characteristics are missing."
                lastError = message
                connectionPhase = .unavailable(message)
            }
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

            if characteristic.uuid == UmbrellaBLEConstants.statusCharacteristicUUID || characteristic.uuid == statusCharacteristic?.uuid {
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

            if characteristic.uuid == UmbrellaBLEConstants.commandCharacteristicUUID || characteristic.uuid == commandCharacteristic?.uuid {
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
