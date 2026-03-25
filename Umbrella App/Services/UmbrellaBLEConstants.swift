//
//  UmbrellaBLEConstants.swift
//  Umbrella App
//
//  Shared BLE UUIDs for the umbrella service.
//

import CoreBluetooth

enum UmbrellaBLEConstants {
    static let serviceUUID = CBUUID(string: "A4F1C6A0-7D5F-4E3D-8A91-102E88D13001")
    static let commandCharacteristicUUID = CBUUID(string: "A4F1C6A0-7D5F-4E3D-8A91-102E88D13002")
    static let statusCharacteristicUUID = CBUUID(string: "A4F1C6A0-7D5F-4E3D-8A91-102E88D13003")

    static let advertisedName = "UmbrellaPi"
}
