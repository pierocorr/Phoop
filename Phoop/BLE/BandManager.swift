import Foundation
import CoreBluetooth
import Combine

/// Conexión con la pulsera SOOP por Bluetooth.
@MainActor
final class BandManager: NSObject, ObservableObject {

    static let shared = BandManager()

    enum ConnState: Equatable {
        case off, searching, connecting, handshaking, ready, disconnected
        var label: String {
            switch self {
            case .off: return "Bluetooth apagado"
            case .searching: return "Buscando pulsera…"
            case .connecting: return "Conectando…"
            case .handshaking: return "Saludando a la pulsera…"
            case .ready: return "Conectada"
            case .disconnected: return "Desconectada"
            }
        }
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let time = Date()
        let outgoing: Bool
        let text: String
    }

    // MARK: Estado publicado

    @Published private(set) var state: ConnState = .disconnected
    @Published private(set) var deviceName: String = "SOOP"
    @Published private(set) var battery: Int?
    @Published private(set) var charging = false
    @Published private(set) var firmware: String?
    @Published private(set) var liveHR: Int?
    @Published private(set) var liveSport: YC.RealSport?
    @Published private(set) var log: [LogLine] = []

    /// Pulso en vivo (para guardar muestras por minuto).
    let heartSubject = PassthroughSubject<Int, Never>()

    // MARK: CoreBluetooth

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var eventChar: CBCharacteristic?
    private var pedometerChar: CBCharacteristic?
    private let cmdReassembler = YC.Reassembler()
    private let evtReassembler = YC.Reassembler()
    private var readyWaiters: [CheckedContinuation<Bool, Never>] = []
    private var handshakeDone = false
    private var handshakeStarted = false

    private let savedIDKey = "phoop.peripheralID"
    private let writeTypeKey = "phoop.writeWithResponse"

    /// Algunas pulseras solo procesan un tipo de escritura; se detecta en el saludo.
    var writeWithResponse: Bool {
        get { UserDefaults.standard.object(forKey: writeTypeKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: writeTypeKey) }
    }

    override private init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "phoop.central",
                                             CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: Conexión

    func start() {
        guard central.state == .poweredOn else { return }
        if let p = peripheral {
            if p.state != .connected && p.state != .connecting { connect(p) }
            return
        }
        if let idString = UserDefaults.standard.string(forKey: savedIDKey),
           let id = UUID(uuidString: idString),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p)
            return
        }
        if let p = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: YC.heartService)])
            .first(where: { ($0.name ?? "").uppercased().hasPrefix("SOOP") }) {
            connect(p)
            return
        }
        state = .searching
        central.scanForPeripherals(withServices: [CBUUID(string: YC.heartService)], options: nil)
    }

    func forgetDevice() {
        UserDefaults.standard.removeObject(forKey: savedIDKey)
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        handshakeDone = false
        state = .disconnected
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        state = .connecting
        central.connect(p, options: nil)
    }

    /// Espera hasta que la pulsera esté lista (o se agote el tiempo).
    func waitUntilReady(timeout: TimeInterval = 20) async -> Bool {
        if state == .ready { return true }
        start()
        return await withCheckedContinuation { cont in
            readyWaiters.append(cont)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.resolveReadyWaiters(self.state == .ready)
            }
        }
    }

    private func resolveReadyWaiters(_ ok: Bool) {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        waiters.forEach { $0.resume(returning: ok) }
    }

    // MARK: Envío de comandos

    private struct Pending {
        let id = UUID()
        let match: (YC.Packet) -> Bool
        let cont: CheckedContinuation<YC.Packet?, Never>
    }
    private var pending: Pending?

    private func write(_ data: Data) {
        guard let p = peripheral, let c = commandChar else { return }
        let canNoResp = c.properties.contains(.writeWithoutResponse)
        let type: CBCharacteristicWriteType = (writeWithResponse || !canNoResp) ? .withResponse : .withoutResponse
        p.writeValue(data, for: c, type: type)
        appendLog(outgoing: true, YC.hex(data))
    }

    /// Envía un comando y espera la respuesta con el mismo grupo/comando.
    func request(_ data: Data, timeout: TimeInterval = 3) async -> YC.Packet? {
        let g = data[0], k = data[1]
        return await request(data, timeout: timeout) { $0.group == g && $0.key == k }
    }

    func request(_ data: Data, timeout: TimeInterval, match: @escaping (YC.Packet) -> Bool) async -> YC.Packet? {
        if let old = pending { pending = nil; old.cont.resume(returning: nil) }
        return await withCheckedContinuation { cont in
            let entry = Pending(match: match, cont: cont)
            pending = entry
            write(data)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let p = self.pending, p.id == entry.id {
                    self.pending = nil
                    p.cont.resume(returning: nil)
                }
            }
        }
    }

    // MARK: Saludo inicial (igual que la app oficial)

    private func handshake() async {
        state = .handshaking
        var name = await request(YC.Cmd.getName())
        if name == nil {
            // Probar el otro tipo de escritura.
            writeWithResponse.toggle()
            appendLog(outgoing: false, "Sin respuesta; probando escritura \(writeWithResponse ? "con" : "sin") respuesta")
            name = await request(YC.Cmd.getName())
        }
        if let n = name, let s = String(bytes: n.payload.prefix { $0 != 0 }, encoding: .utf8), !s.isEmpty {
            deviceName = s
        }
        _ = await request(YC.Cmd.setTime())
        _ = await request(YC.Cmd.getFunctions())
        _ = await request(YC.Cmd.getChip())
        await refreshDeviceInfo()
        handshakeDone = true
        state = .ready
        resolveReadyWaiters(true)
    }

    func refreshDeviceInfo() async {
        if let info = await request(YC.Cmd.getDeviceInfo()), let d = YC.parseDeviceInfo(info.payload) {
            battery = d.battery
            charging = d.charging
            firmware = d.firmware
        }
    }

    func send(_ data: Data) { write(data) }

    // MARK: Historial

    private var historyKind: YC.HistoryKind?
    private var historyBuffer: [UInt8] = []
    private var historyCont: CheckedContinuation<[UInt8]?, Never>?
    private var historyActivity = Date()
    private var historyToken = UUID()

    /// Descarga un tipo de historial completo. Devuelve los bytes unidos o nil si falló.
    func fetchHistory(_ kind: YC.HistoryKind, timeout: TimeInterval = 30) async -> [UInt8]? {
        guard state == .ready else { return nil }
        if let c = historyCont { historyCont = nil; c.resume(returning: nil) }
        historyKind = kind
        historyBuffer = []
        historyActivity = Date()
        let token = UUID()
        historyToken = token
        return await withCheckedContinuation { cont in
            historyCont = cont
            write(YC.Cmd.history(kind))
            Task { @MainActor in
                // Se corta si pasan 6 s sin datos nuevos o se supera el máximo.
                let started = Date()
                while self.historyCont != nil && self.historyToken == token {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    let idle = Date().timeIntervalSince(self.historyActivity)
                    if idle > 6 || Date().timeIntervalSince(started) > timeout {
                        self.finishHistory(nil)
                    }
                }
            }
        }
    }

    private func finishHistory(_ result: [UInt8]?) {
        guard let c = historyCont else { return }
        historyCont = nil
        historyKind = nil
        c.resume(returning: result)
    }

    private func handleHistory(_ p: YC.Packet) {
        guard let kind = historyKind else { return }
        historyActivity = Date()
        if p.key == kind.rawValue {
            // Cabecera: [registros 2B][paquetes 4B][bytes 4B]. Sin datos si es corta.
            if p.payload.count <= 9 || YC.u16(p.payload, 0) == 0 { finishHistory([]) }
            historyBuffer = []
        } else if p.key == 0x80 {
            guard p.payload.count >= 6 else { finishHistory(historyBuffer); return }
            let expected = UInt16(YC.u16(p.payload, 4))
            let ok = YC.crc16(historyBuffer) == expected
            write(YC.Cmd.historyAck(ok: ok))
            appendLog(outgoing: false, "Historial \(kind.label): \(historyBuffer.count) bytes, CRC \(ok ? "OK" : "ERROR")")
            finishHistory(ok ? historyBuffer : nil)
        } else if !p.isError {
            historyBuffer.append(contentsOf: p.payload)
        } else {
            finishHistory(nil)
        }
    }

    // MARK: Paquetes entrantes

    private func handle(_ p: YC.Packet) {
        // La pulsera repite su dirección MAC (02 02) cada ~20 s: no ensuciar el registro.
        let isMacEcho = p.group == 2 && p.key == 2 && pending?.match(p) != true
        if !isMacEcho { appendLog(outgoing: false, "\(String(format: "%02X %02X", p.group, p.key)) · \(YC.hex(p.payload))\(p.crcOK ? "" : " (CRC!)")") }

        if p.group == YC.Group.health.rawValue, historyKind != nil {
            handleHistory(p)
            return
        }
        if p.group == YC.Group.real.rawValue {
            if p.key == 0x00, let s = YC.parseRealSport(p.payload) { liveSport = s }
            if p.key == 0x01, let hr = p.payload.first, hr > 0 { setHR(Int(hr)) }
        }
        if let w = pending, w.match(p) {
            pending = nil
            w.cont.resume(returning: p)
        }
    }

    private func setHR(_ v: Int) {
        liveHR = v
        heartSubject.send(v)
    }

    private func appendLog(outgoing: Bool, _ text: String) {
        log.append(LogLine(outgoing: outgoing, text: text))
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    var logText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return log.map { "[\(f.string(from: $0.time))] \($0.outgoing ? "→" : "←") \($0.text)" }.joined(separator: "\n")
    }

    func readPedometer() {
        if let p = peripheral, let c = pedometerChar { p.readValue(for: c) }
    }
}

// MARK: - CBCentralManagerDelegate

extension BandManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn { start() } else { state = .off }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
                peripheral = p
                p.delegate = self
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
            guard name.uppercased().hasPrefix("SOOP") else { return }
            central.stopScan()
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: savedIDKey)
            connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: savedIDKey)
            appendLog(outgoing: false, "Conectado a \(peripheral.name ?? "pulsera")")
            cmdReassembler.reset(); evtReassembler.reset()
            handshakeDone = false
            handshakeStarted = false
            peripheral.discoverServices([CBUUID(string: YC.commandService),
                                         CBUUID(string: YC.heartService),
                                         CBUUID(string: YC.pedometerService)])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            state = .disconnected
            appendLog(outgoing: false, "No se pudo conectar: \(error?.localizedDescription ?? "-")")
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            state = .disconnected
            commandChar = nil; eventChar = nil
            handshakeDone = false
            handshakeStarted = false
            liveHR = nil
            appendLog(outgoing: false, "Desconectada")
            finishHistory(nil)
            if let w = pending { pending = nil; w.cont.resume(returning: nil) }
            // Reconexión automática: iOS la completa cuando la pulsera vuelve a estar cerca.
            central.connect(peripheral, options: nil)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BandManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            for s in peripheral.services ?? [] {
                peripheral.discoverCharacteristics(nil, for: s)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] {
                switch c.uuid {
                case CBUUID(string: YC.commandChar):
                    commandChar = c
                    peripheral.setNotifyValue(true, for: c)
                case CBUUID(string: YC.eventChar):
                    eventChar = c
                    peripheral.setNotifyValue(true, for: c)
                case CBUUID(string: YC.heartMeasure):
                    peripheral.setNotifyValue(true, for: c)
                case CBUUID(string: YC.pedometerChar):
                    pedometerChar = c
                    peripheral.setNotifyValue(true, for: c)
                    peripheral.readValue(for: c)
                default: break
                }
            }
            if commandChar != nil, eventChar != nil, !handshakeDone, !handshakeStarted {
                handshakeStarted = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000) // dejar que se activen las indicaciones
                    await self.handshake()
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let data = characteristic.value else { return }
            switch characteristic.uuid {
            case CBUUID(string: YC.commandChar):
                cmdReassembler.feed(data).forEach(handle)
            case CBUUID(string: YC.eventChar):
                evtReassembler.feed(data).forEach(handle)
            case CBUUID(string: YC.heartMeasure):
                if let hr = YC.parseHeartMeasurement(data), hr > 0 { setHR(hr) }
            case CBUUID(string: YC.pedometerChar):
                if let s = YC.parsePedometer(data) { liveSport = s }
            default: break
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if let error { appendLog(outgoing: false, "Error al escribir: \(error.localizedDescription)") }
        }
    }
}
