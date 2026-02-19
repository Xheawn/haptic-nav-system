//
//  BLEManager.swift
//  navigationTest
//
//  Minimal BLE Central Manager — scans for the ESP32-S3 peripheral,
//  connects, discovers the writable characteristic, and exposes
//  sendCommand(_:) for the rest of the app.
//

import Foundation
import CoreBluetooth

// Must match the ESP32 firmware exactly
private let kServiceUUID        = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
private let kCharacteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

class BLEManager: NSObject {

    static let shared = BLEManager()

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    /// Call once (e.g. in viewDidLoad) to power on the radio and begin scanning.
    func start() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
        // Scanning begins automatically in centralManagerDidUpdateState
        // once Bluetooth is powered on.
    }

    /// Write a raw Data packet to the ESP32 characteristic.
    /// Uses .withoutResponse for low-latency haptic commands.
    func sendCommand(_ data: Data) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            // Not connected yet — silently drop
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    // MARK: - Private helpers

    private func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        print("[BLE] Scanning for XIAO_ESP32S3...")
        centralManager.scanForPeripherals(withServices: [kServiceUUID], options: nil)
    }

    private override init() {
        super.init()
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BLE] Bluetooth powered on")
            startScanning()
        case .poweredOff:
            print("[BLE] Bluetooth is off — please enable it")
        case .unauthorized:
            print("[BLE] Bluetooth permission not granted")
        case .unsupported:
            print("[BLE] BLE not supported on this device")
        default:
            print("[BLE] Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        print("[BLE] Discovered \(peripheral.name ?? "unknown") RSSI=\(RSSI)")
        // Stop scanning once we find our device
        centralManager.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                         didConnect peripheral: CBPeripheral) {
        print("[BLE] Connected to \(peripheral.name ?? "unknown")")
        peripheral.discoverServices([kServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                         didFailToConnect peripheral: CBPeripheral,
                         error: Error?) {
        print("[BLE] Failed to connect: \(error?.localizedDescription ?? "unknown")")
        // Retry
        startScanning()
    }

    func centralManager(_ central: CBCentralManager,
                         didDisconnectPeripheral peripheral: CBPeripheral,
                         error: Error?) {
        print("[BLE] Disconnected — will rescan")
        connectedPeripheral = nil
        writeCharacteristic = nil
        // Auto-reconnect
        startScanning()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral,
                     didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == kServiceUUID {
            print("[BLE] Found service \(service.uuid)")
            peripheral.discoverCharacteristics([kCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didDiscoverCharacteristicsFor service: CBService,
                     error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == kCharacteristicUUID {
            print("[BLE] Found characteristic \(char.uuid) — ready to send commands")
            writeCharacteristic = char
        }
    }
}
