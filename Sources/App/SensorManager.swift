import CoreBluetooth
import SwiftUI

struct NearbySensor: Identifiable {
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int?
    var id: UUID { peripheral.identifier }
}

// Core Bluetooth delivers every callback to the explicitly selected main queue.
final class SensorManager: NSObject, ObservableObject, CBCentralManagerDelegate,
    CBPeripheralDelegate
{
    @Published private(set) var devices: [NearbySensor] = []
    @Published private(set) var status = "Choose Scan to enable Bluetooth, or explore a demo."
    @Published private(set) var scanning = false
    @Published private(set) var connecting = false
    @Published private(set) var connected = false
    @Published private(set) var demo = false
    @Published private(set) var sessionIsDemo = false
    @Published private(set) var samples: [SensorSample] = []
    @Published private(set) var latest: HeartRateMeasurement?
    @Published private(set) var battery: Int?
    @Published private(set) var deviceName: String?
    @Published var error: String?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var scanRequested = false
    private var disconnectRequested = false
    private var scanTimeout: Timer?
    private var connectionTimeout: Timer?
    private var demoTimer: Timer?
    private var sampleIndex = 0
    private let heartService = CBUUID(string: "180D")
    private let heartCharacteristic = CBUUID(string: "2A37")
    private let batteryService = CBUUID(string: "180F")
    private let batteryCharacteristic = CBUUID(string: "2A19")

    func scan() {
        guard !connected, !connecting, !demo else { return }
        scanRequested = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        } else {
            updateState()
        }
    }
    private func beginScan() {
        guard !connected, !connecting, !demo else { return }
        stopScan()
        devices = []
        scanning = true
        status = "Searching for heart-rate sensors…"
        central?.scanForPeripherals(
            withServices: [heartService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scanTimeout = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            self?.stopScan()
            self?.status =
                self?.devices.isEmpty == true
                ? "No sensors found. Wake your sensor and try again."
                : "Choose a sensor to connect."
        }
    }
    func stopScan() {
        scanRequested = false
        central?.stopScan()
        scanTimeout?.invalidate()
        scanTimeout = nil
        scanning = false
    }
    func connect(_ device: NearbySensor) {
        guard !connected, !connecting, !demo, central?.state == .poweredOn else { return }
        stopScan()
        disconnectRequested = false
        resetSession(isDemo: false)
        peripheral = device.peripheral
        peripheral?.delegate = self
        deviceName = device.name
        connecting = true
        status = "Connecting to \(device.name)…"
        central?.connect(device.peripheral)
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) {
            [weak self] _ in
            guard let self else { return }
            self.disconnect()
            self.error = "The sensor did not become ready in time. Move closer and retry."
        }
    }
    func disconnect() {
        stopScan()
        demoTimer?.invalidate()
        demoTimer = nil
        demo = false
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        connected = false
        if let peripheral {
            disconnectRequested = true
            connecting = true
            status = "Disconnecting sensor…"
            central?.cancelPeripheralConnection(peripheral)
        } else {
            connecting = false
            status = "Session ended. Readings remain available for export."
        }
    }
    func pauseForBackground() { if scanning || connecting || connected || demo { disconnect() } }
    func startDemo() {
        guard !connected, !connecting else { return }
        stopScan()
        demoTimer?.invalidate()
        resetSession(isDemo: true)
        demo = true
        deviceName = "Demo heart-rate sensor"
        battery = 86
        status = "Simulated readings · no Bluetooth connection"
        for _ in 0..<20 { appendDemo(date: Date().addingTimeInterval(Double(sampleIndex - 20))) }
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.appendDemo(date: Date())
        }
    }
    private func resetSession(isDemo: Bool) {
        samples = []
        latest = nil
        battery = nil
        sampleIndex = 0
        sessionIsDemo = isDemo
        error = nil
    }
    private func appendDemo(date: Date) {
        let bpm = 72 + Int(9 * sin(Double(sampleIndex) / 6))
        sampleIndex += 1
        if let measurement = try? HeartRateMeasurement.decode(Data([0, UInt8(bpm)])) {
            append(measurement, date: date)
        }
    }
    private func append(_ value: HeartRateMeasurement, date: Date = Date()) {
        latest = value
        samples.append(
            SensorSample(date: date, bpm: value.beatsPerMinute, rrIntervals: value.rrIntervals))
        if samples.count > 3_600 { samples.removeFirst(samples.count - 3_600) }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { updateState() }
    private func updateState() {
        guard let central, !demo else { return }
        if central.state == .poweredOn {
            status = "Bluetooth ready."
            if scanRequested { beginScan() }
            return
        }
        stopScan()
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        peripheral = nil
        connected = false
        connecting = false
        switch central.state {
        case .poweredOff: status = "Bluetooth is off. Turn it on in Settings, then scan again."
        case .unauthorized: status = "Bluetooth access is denied. Allow access in Settings to scan."
        case .unsupported:
            status = "Bluetooth LE is unavailable here. Demo mode works in the simulator."
        case .resetting: status = "Bluetooth is resetting. Try scanning again shortly."
        default:
            status = "Waiting for Bluetooth to become available…"
            scanRequested = true
        }
    }
    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        guard scanning else { return }
        let name =
            advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
            ?? "Unnamed heart-rate sensor"
        let item = NearbySensor(
            peripheral: peripheral, name: name, rssi: RSSI.intValue == 127 ? nil : RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == item.id }) {
            devices[index] = item
        } else {
            devices.append(item)
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !disconnectRequested, self.peripheral?.identifier == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        status = "Discovering sensor services…"
        peripheral.discoverServices([heartService, batteryService])
    }
    func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) { end(peripheral, error: error?.localizedDescription ?? "Could not connect to the sensor.") }
    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) { end(peripheral, error: error?.localizedDescription) }
    private func end(_ peripheral: CBPeripheral, error: String?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        self.peripheral = nil
        connected = false
        connecting = false
        status = "Sensor disconnected. Readings remain available for export."
        if let error { self.error = error }
    }
    private func fail(_ message: String) {
        disconnect()
        error = message
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard !disconnectRequested, self.peripheral?.identifier == peripheral.identifier else {
            return
        }
        if let error {
            fail(error.localizedDescription)
            return
        }
        guard let services = peripheral.services,
            services.contains(where: { $0.uuid == heartService })
        else {
            fail("This device does not expose the Heart Rate service.")
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(
                service.uuid == heartService ? [heartCharacteristic] : [batteryCharacteristic],
                for: service)
        }
    }
    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        guard !disconnectRequested, self.peripheral?.identifier == peripheral.identifier else {
            return
        }
        if let error {
            if service.uuid == heartService { fail(error.localizedDescription) }
            return
        }
        if service.uuid == heartService {
            guard
                let value = service.characteristics?.first(where: { $0.uuid == heartCharacteristic }
                ), value.properties.contains(.notify)
            else {
                fail("The sensor does not support heart-rate notifications.")
                return
            }
            peripheral.setNotifyValue(true, for: value)
        } else if let value = service.characteristics?.first(where: {
            $0.uuid == batteryCharacteristic
        }) {
            if value.properties.contains(.read) { peripheral.readValue(for: value) }
            if value.properties.contains(.notify) { peripheral.setNotifyValue(true, for: value) }
        }
    }
    func peripheral(
        _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard !disconnectRequested, self.peripheral?.identifier == peripheral.identifier,
            characteristic.uuid == heartCharacteristic
        else { return }
        if let error {
            fail(error.localizedDescription)
            return
        }
        guard characteristic.isNotifying else {
            fail("The sensor stopped heart-rate notifications.")
            return
        }
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        connecting = false
        connected = true
        status = "Connected · waiting for readings"
    }
    func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard !disconnectRequested, self.peripheral?.identifier == peripheral.identifier else {
            return
        }
        if let error {
            self.error = error.localizedDescription
            return
        }
        guard let data = characteristic.value else { return }
        if characteristic.uuid == heartCharacteristic {
            do {
                append(try HeartRateMeasurement.decode(data))
                status = "Receiving heart-rate measurements"
            } catch { self.error = error.localizedDescription }
        } else if characteristic.uuid == batteryCharacteristic, data.count == 1,
            let value = data.first, value <= 100
        {
            battery = Int(value)
        }
    }
    func export() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Sensor-\(UUID()).csv")
        try SensorCSV.encode(samples, demo: sessionIsDemo).write(
            to: url, atomically: true, encoding: .utf8)
        return url
    }
    deinit {
        scanTimeout?.invalidate()
        connectionTimeout?.invalidate()
        demoTimer?.invalidate()
    }
}
