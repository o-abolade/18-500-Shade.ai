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
    private var connectingPeripheral: CBPeripheral?
    private var connectedPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var commandCharacteristics: [CBCharacteristic] = []
    private var statusCharacteristics: [CBCharacteristic] = []
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

        if connectingPeripheral != nil || connectedPeripheral != nil {
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
        connectingPeripheral = nil
        discoveredDeviceName = nil
        connectedDeviceName = nil
        commandCharacteristic = nil
        statusCharacteristic = nil
        commandCharacteristics = []
        statusCharacteristics = []
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

        if let activePeripheral = connectedPeripheral ?? connectingPeripheral {
            centralManager.cancelPeripheralConnection(activePeripheral)
        } else {
            resetConnectionState()
            connectionPhase = .disconnected
        }
    }

    func requestStatus() {
        guard let connectedPeripheral else { return }

        if let statusCharacteristic {
            connectedPeripheral.readValue(for: statusCharacteristic)
        }

        for characteristic in statusCharacteristics where characteristic.uuid != statusCharacteristic?.uuid {
            connectedPeripheral.readValue(for: characteristic)
        }
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
        guard let connectedPeripheral else {
            lastError = "Bluetooth device is not connected yet."
            return
        }

        // Prefer the exact UUID match; fall back to discovered candidates only when needed.
        let targets: [CBCharacteristic]
        if let exact = commandCharacteristic {
            targets = [exact]
        } else if !commandCharacteristics.isEmpty {
            targets = commandCharacteristics
        } else {
            lastError = "No command characteristic found. Ensure the Pi is running ble_server.py."
            return
        }

        do {
            let data = try encoder.encode(command)
            print("BLE sending command: \(commandDebugDescription(command))")
            applyOptimisticStatusUpdate(for: command)

            for characteristic in targets {
                let writeType: CBCharacteristicWriteType =
                    characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
                print("BLE writing to characteristic: \(characteristic.uuid.uuidString) (type: \(writeType == .withResponse ? "withResponse" : "withoutResponse"))")
                connectedPeripheral.writeValue(data, for: characteristic, type: writeType)
                if writeType == .withoutResponse {
                    requestStatus()
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func connect(to peripheral: CBPeripheral) {
        guard connectingPeripheral == nil, connectedPeripheral == nil else {
            return
        }

        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        isScanning = false
        centralManager.stopScan()

        discoveredPeripheral = peripheral
        connectingPeripheral = peripheral
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
        connectingPeripheral = nil
        connectedPeripheral = nil
        commandCharacteristic = nil
        statusCharacteristic = nil
        commandCharacteristics = []
        statusCharacteristics = []
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

    private func commandDebugDescription(_ command: UmbrellaBLECommand) -> String {
        switch command.type {
        case .move:
            return "move \(command.direction ?? "unknown")"
        case .stop:
            return "stop"
        case .mode:
            return "mode \(command.value ?? "unknown")"
        case .location:
            return "location \(command.latitude ?? 0), \(command.longitude ?? 0)"
        }
    }

    private func applyOptimisticStatusUpdate(for command: UmbrellaBLECommand) {
        let currentStatus = status ?? UmbrellaStatus(
            position: nil,
            mode: nil,
            moving: false,
            connected: true
        )

        switch command.type {
        case .mode:
            status = UmbrellaStatus(
                position: currentStatus.position,
                mode: command.value ?? currentStatus.mode,
                moving: currentStatus.moving,
                connected: true
            )
        case .move:
            status = UmbrellaStatus(
                position: currentStatus.position,
                mode: currentStatus.mode,
                moving: true,
                connected: true
            )
        case .stop:
            status = UmbrellaStatus(
                position: currentStatus.position,
                mode: currentStatus.mode,
                moving: false,
                connected: true
            )
        case .location:
            break
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

            let message: String
            if connectingPeripheral != nil {
                message = "Found UmbrellaPi, but the Bluetooth connection did not complete."
            } else {
                message = "Connected to UmbrellaPi, but service discovery did not finish. Check that the Pi is running the latest ble_server.py."
            }
            lastError = message
            connectionPhase = .unavailable(message)

            if let activePeripheral = connectedPeripheral ?? connectingPeripheral {
                centralManager.cancelPeripheralConnection(activePeripheral)
            } else {
                resetConnectionState()
            }
        }
    }

    private func isCustomBLEUUID(_ uuid: CBUUID) -> Bool {
        uuid.uuidString.count > 4
    }

    private func allDiscoveredCharacteristics(from peripheral: CBPeripheral) -> [CBCharacteristic] {
        (peripheral.services ?? []).flatMap { $0.characteristics ?? [] }
    }

    private func uniqueCharacteristics(_ characteristics: [CBCharacteristic]) -> [CBCharacteristic] {
        var seen = Set<ObjectIdentifier>()
        return characteristics.filter { characteristic in
            let identifier = ObjectIdentifier(characteristic)
            return seen.insert(identifier).inserted
        }
    }

    private func preferredCharacteristics(from peripheral: CBPeripheral) -> [CBCharacteristic] {
        guard let services = peripheral.services else { return [] }

        let matchingServiceCharacteristics = services
            .filter { $0.uuid == UmbrellaBLEConstants.serviceUUID }
            .flatMap { $0.characteristics ?? [] }
        if !matchingServiceCharacteristics.isEmpty {
            return matchingServiceCharacteristics
        }

        let customServiceCharacteristics = services
            .filter { isCustomBLEUUID($0.uuid) }
            .flatMap { $0.characteristics ?? [] }
        if !customServiceCharacteristics.isEmpty {
            return customServiceCharacteristics
        }

        return services.flatMap { $0.characteristics ?? [] }
    }

    private func haveDiscoveredCharacteristicsForAllServices(on peripheral: CBPeripheral) -> Bool {
        guard let services = peripheral.services, !services.isEmpty else { return false }
        return services.allSatisfy { $0.characteristics != nil }
    }

    private func exactCommandCharacteristic(from characteristics: [CBCharacteristic]) -> CBCharacteristic? {
        characteristics.first(where: { $0.uuid == UmbrellaBLEConstants.commandCharacteristicUUID })
    }

    private func exactStatusCharacteristic(from characteristics: [CBCharacteristic]) -> CBCharacteristic? {
        characteristics.first(where: { $0.uuid == UmbrellaBLEConstants.statusCharacteristicUUID })
    }

    private func chooseCommandCharacteristic(from characteristics: [CBCharacteristic]) -> CBCharacteristic? {
        if let exactMatch = exactCommandCharacteristic(from: characteristics) {
            return exactMatch
        }

        return characteristics.first(where: {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        })
    }

    private func chooseStatusCharacteristic(
        from characteristics: [CBCharacteristic],
        excluding excludedCharacteristic: CBCharacteristic? = nil
    ) -> CBCharacteristic? {
        if let exactMatch = exactStatusCharacteristic(from: characteristics) {
            return exactMatch
        }

        let excludedIdentifier = excludedCharacteristic.map(ObjectIdentifier.init)
        return characteristics.first(where: {
            if let excludedIdentifier, ObjectIdentifier($0) == excludedIdentifier {
                return false
            }
            return $0.properties.contains(.notify) || $0.properties.contains(.read)
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
            guard case .scanning = connectionPhase else {
                return
            }
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
            connectingPeripheral = nil
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

            let preferredCharacteristics = preferredCharacteristics(from: peripheral)
            let allCharacteristics = allDiscoveredCharacteristics(from: peripheral)
            let allServiceCharacteristicsDiscovered = haveDiscoveredCharacteristicsForAllServices(on: peripheral)

            if commandCharacteristic == nil {
                commandCharacteristic =
                    exactCommandCharacteristic(from: preferredCharacteristics) ??
                    exactCommandCharacteristic(from: allCharacteristics)
            }

            if statusCharacteristic == nil {
                statusCharacteristic =
                    exactStatusCharacteristic(from: preferredCharacteristics) ??
                    exactStatusCharacteristic(from: allCharacteristics)
            }

            if allServiceCharacteristicsDiscovered {
                commandCharacteristics = uniqueCharacteristics(
                    preferredCharacteristics.filter {
                        $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
                    } +
                    allCharacteristics.filter {
                        $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
                    }
                )

                statusCharacteristics = uniqueCharacteristics(
                    preferredCharacteristics.filter {
                        $0.properties.contains(.notify) || $0.properties.contains(.read)
                    } +
                    allCharacteristics.filter {
                        $0.properties.contains(.notify) || $0.properties.contains(.read)
                    }
                )

                if commandCharacteristic == nil {
                    commandCharacteristic =
                        chooseCommandCharacteristic(from: preferredCharacteristics) ??
                        chooseCommandCharacteristic(from: allCharacteristics)
                }

                if statusCharacteristic == nil {
                    statusCharacteristic =
                        chooseStatusCharacteristic(from: preferredCharacteristics, excluding: commandCharacteristic) ??
                        chooseStatusCharacteristic(from: allCharacteristics, excluding: commandCharacteristic)
                }
            }

            if let statusCharacteristic, let commandCharacteristic {
                connectionTimeoutTask?.cancel()
                connectionTimeoutTask = nil
                connectedDeviceName = resolvedName(for: peripheral)

                let commandIsExactMatch = commandCharacteristic.uuid == UmbrellaBLEConstants.commandCharacteristicUUID
                let statusIsExactMatch = statusCharacteristic.uuid == UmbrellaBLEConstants.statusCharacteristicUUID

                print("BLE selected command characteristic: \(commandCharacteristic.uuid.uuidString) \(commandIsExactMatch ? "(exact)" : "(FALLBACK – UUID mismatch!)")")
                print("BLE selected status characteristic: \(statusCharacteristic.uuid.uuidString) \(statusIsExactMatch ? "(exact)" : "(FALLBACK – UUID mismatch!)")")
                if !commandCharacteristics.isEmpty {
                    print("BLE command candidates: \(commandCharacteristics.map { $0.uuid.uuidString })")
                }
                if !statusCharacteristics.isEmpty {
                    print("BLE status candidates: \(statusCharacteristics.map { $0.uuid.uuidString })")
                }

                if !commandIsExactMatch {
                    print("BLE ERROR: Expected command UUID \(UmbrellaBLEConstants.commandCharacteristicUUID.uuidString) — Pi is running a different script.")
                    lastError = "Pi is not running the expected ble_server.py. Re-upload the script and restart it on the Pi."
                }

                connectionPhase = .connected(connectedDeviceName ?? UmbrellaBLEConstants.advertisedName)
                peripheral.setNotifyValue(true, for: statusCharacteristic)
                peripheral.readValue(for: statusCharacteristic)
            } else if allServiceCharacteristicsDiscovered {
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

            if characteristic.uuid == UmbrellaBLEConstants.statusCharacteristicUUID
                || characteristic.uuid == statusCharacteristic?.uuid
                || statusCharacteristics.contains(where: { $0.uuid == characteristic.uuid }) {
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

            if characteristic.uuid == UmbrellaBLEConstants.commandCharacteristicUUID
                || characteristic.uuid == commandCharacteristic?.uuid
                || commandCharacteristics.contains(where: { $0.uuid == characteristic.uuid }) {
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
