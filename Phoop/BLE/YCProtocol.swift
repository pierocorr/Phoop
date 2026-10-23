import Foundation

/// Protocolo de la pulsera SOOP (SDK Yucheng "ycbtsdk").
/// Paquete: [grupo][comando][largo_lo][largo_hi][datos...][crc_lo][crc_hi]
/// `largo` es la longitud total del paquete. CRC16 Nordic (init 0xFFFF).
enum YC {

    // MARK: UUIDs

    static let commandService  = "BE940000-7333-BE46-B7AE-689E71722BD5"
    static let commandChar     = "BE940001-7333-BE46-B7AE-689E71722BD5" // escribir + respuestas (Indicate)
    static let bulkChar        = "BE940002-7333-BE46-B7AE-689E71722BD5"
    static let eventChar       = "BE940003-7333-BE46-B7AE-689E71722BD5" // avisos espontáneos (Indicate)
    static let heartService    = "180D"
    static let heartMeasure    = "2A37"
    static let pedometerService = "FEE7"
    static let pedometerChar   = "FEA1"

    // MARK: Grupos

    enum Group: UInt8 {
        case setting = 1, get = 2, appControl = 3, devControl = 4, health = 5, real = 6
    }

    // MARK: CRC + frames

    static func crc16(_ data: [UInt8]) -> UInt16 {
        var s: UInt16 = 0xFFFF
        for b in data {
            s = (s << 8) | (s >> 8)
            s ^= UInt16(b)
            s ^= (s & 0xFF) >> 4
            s ^= s << 12
            s ^= (s & 0xFF) << 5
        }
        return s
    }

    static func frame(_ group: UInt8, _ key: UInt8, _ payload: [UInt8] = []) -> Data {
        let total = payload.count + 6
        var body: [UInt8] = [group, key, UInt8(total & 0xFF), UInt8((total >> 8) & 0xFF)]
        body.append(contentsOf: payload)
        let c = crc16(body)
        body.append(UInt8(c & 0xFF))
        body.append(UInt8(c >> 8))
        return Data(body)
    }

    struct Packet {
        let group: UInt8
        let key: UInt8
        let payload: [UInt8]
        let crcOK: Bool
        var id: UInt16 { UInt16(group) << 8 | UInt16(key) }

        /// Respuesta de error de 1 byte (0xFB…0xFF).
        var isError: Bool { payload.count == 1 && payload[0] >= 0xFB }
    }

    /// Une fragmentos de indicaciones en paquetes completos usando el campo de largo.
    final class Reassembler {
        private var buffer: [UInt8] = []

        func feed(_ data: Data) -> [Packet] {
            buffer.append(contentsOf: data)
            var out: [Packet] = []
            while buffer.count >= 6 {
                let len = Int(buffer[2]) | (Int(buffer[3]) << 8)
                if len < 6 || len > 4096 { buffer.removeAll(); break } // basura: descartar
                if buffer.count < len { break }
                let bytes = Array(buffer[0..<len])
                buffer.removeFirst(len)
                let crcGot = UInt16(bytes[len - 2]) | (UInt16(bytes[len - 1]) << 8)
                let crcCalc = YC.crc16(Array(bytes[0..<(len - 2)]))
                out.append(Packet(group: bytes[0], key: bytes[1],
                                  payload: Array(bytes[4..<(len - 2)]),
                                  crcOK: crcGot == crcCalc))
            }
            return out
        }

        func reset() { buffer.removeAll() }
    }

    // MARK: Comandos

    enum Cmd {
        static func getName() -> Data { frame(2, 0x03, [0x47, 0x50]) }            // "GP"
        static func getFunctions() -> Data { frame(2, 0x01, [0x47, 0x46]) }       // "GF"
        static func getChip() -> Data { frame(2, 0x1B) }
        static func getDeviceInfo() -> Data { frame(2, 0x00, [0x47, 0x43]) }      // "GC"
        static func getAllReal() -> Data { frame(2, 0x20) }

        static func setTime(_ date: Date = Date()) -> Data {
            let cal = Calendar(identifier: .gregorian)
            let c = cal.dateComponents(in: TimeZone.current, from: date)
            let y = c.year ?? 2026
            let weekday = c.weekday ?? 1                // 1 = domingo
            let devWeekday = weekday == 1 ? 6 : weekday - 2 // 0 = lunes … 6 = domingo
            return frame(1, 0x00, [UInt8(y & 0xFF), UInt8(y >> 8), UInt8(c.month ?? 1), UInt8(c.day ?? 1),
                                   UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0),
                                   UInt8(devWeekday)])
        }

        /// Monitoreo automático de pulso: on/off + intervalo en minutos.
        static func heartMonitor(on: Bool, minutes: Int) -> Data {
            frame(1, 0x0C, [on ? 1 : 0, UInt8(clamping: minutes)])
        }

        /// Monitoreo automático de SpO₂ y de temperatura (on/off + intervalo en minutos).
        static func spo2Monitor(on: Bool, minutes: Int) -> Data {
            frame(1, 0x26, [on ? 1 : 0, UInt8(clamping: minutes)])
        }
        static func tempMonitor(on: Bool, minutes: Int) -> Data {
            frame(1, 0x20, [on ? 1 : 0, UInt8(clamping: minutes)])
        }

        /// Meta diaria de pasos (la pulsera vibra al alcanzarla).
        static func stepGoal(_ steps: Int) -> Data {
            let s = UInt32(clamping: steps)
            return frame(1, 0x02, [0, UInt8(s & 0xFF), UInt8((s >> 8) & 0xFF), UInt8((s >> 16) & 0xFF), UInt8(s >> 24), 0, 0])
        }

        /// Datos de usuario: altura cm, peso kg, sexo (0 hombre, 1 mujer), edad.
        static func userInfo(heightCm: Int, weightKg: Int, female: Bool, age: Int) -> Data {
            frame(1, 0x03, [UInt8(clamping: heightCm), UInt8(clamping: weightKg), female ? 1 : 0, UInt8(clamping: age)])
        }

        static func history(_ kind: HistoryKind) -> Data { frame(5, kind.rawValue) }
        static func deleteHistory(_ kind: HistoryKind) -> Data { frame(5, kind.deleteKey) }
        static func historyAck(ok: Bool) -> Data { frame(5, 0x80, [ok ? 0 : 4]) }

        /// Alarma de pulso: avisa si supera `max` (o baja de `min`, 0 = sin mínimo).
        static func heartAlarm(on: Bool, max: Int, min: Int = 0) -> Data {
            frame(1, 0x0B, [on ? 1 : 0, UInt8(clamping: max), UInt8(clamping: min)])
        }

        /// Hace vibrar la pulsera: [on, repeticiones, intervalo].
        static func findBand() -> Data { frame(3, 0x00, [1, 5, 2]) }

        /// Medición manual en la pulsera.
        static func measure(_ type: MeasureType, start: Bool) -> Data { frame(3, 0x2F, [start ? 1 : 0, type.rawValue]) }

        /// Modo entrenamiento (pulso continuo): [1 inicio / 0 fin, deporte].
        static func workoutMode(start: Bool, sport: UInt8 = 0) -> Data { frame(3, 0x0C, [start ? 1 : 0, sport]) }

        /// Pasos actuales del día: respuesta [pasos 3B][kcal 2B][distancia 2B].
        static func nowSteps() -> Data { frame(2, 0x0C) }

        /// Lectura instantánea de temperatura ("entero.decimal") y SpO₂ ([midiendo, valor]).
        static func realTemp() -> Data { frame(2, 0x0E) }
        static func realSpO2() -> Data { frame(2, 0x11, [0x49, 0x53]) }

        /// Transmisión en vivo (pulso y pasos) mientras la app está abierta.
        static func realtime(_ on: Bool) -> Data { frame(3, 0x09, [on ? 1 : 0, 0, 2]) }

        /// Modo cámara remota en la pulsera.
        static func cameraMode(_ on: Bool) -> Data { frame(3, 0x0E, [on ? 1 : 0]) }

        /// Prueba de ECG.
        static func ecg(start: Bool) -> Data { frame(3, 0x02, [start ? 2 : 0]) }
    }

    enum MeasureType: UInt8, CaseIterable, Identifiable {
        case heart = 0, spo2 = 2, temp = 4, hrv = 10, stress = 12
        var id: UInt8 { rawValue }
        var label: String {
            switch self {
            case .heart: return "Pulso"
            case .spo2: return "SpO₂"
            case .temp: return "Temperatura"
            case .hrv: return "HRV"
            case .stress: return "Estrés"
            }
        }
        var icon: String {
            switch self {
            case .heart: return "heart.fill"
            case .spo2: return "drop.fill"
            case .temp: return "thermometer.medium"
            case .hrv: return "waveform.path.ecg"
            case .stress: return "brain.head.profile"
            }
        }
        /// Historial que hay que descargar al terminar.
        var history: HistoryKind {
            switch self {
            case .heart: return .heart
            case .stress: return .body
            default: return .all
            }
        }
    }

    enum HistoryKind: UInt8, CaseIterable {
        case sport = 0x02, sleep = 0x04, heart = 0x06, all = 0x09, body = 0x33

        var deleteKey: UInt8 {
            switch self {
            case .sport: return 0x40
            case .sleep: return 0x41
            case .heart: return 0x42
            case .all:   return 0x44
            case .body:  return 0x4E
            }
        }

        var label: String {
            switch self {
            case .sport: return "actividad"
            case .sleep: return "sueño"
            case .heart: return "pulso"
            case .all:   return "salud (HRV/SpO₂/temp)"
            case .body:  return "estrés y energía"
            }
        }
    }

    // MARK: Tiempo de la pulsera

    /// Segundos desde 2000-01-01 en hora LOCAL → Date.
    static func date(fromDevice raw: UInt32) -> Date {
        let tz = TimeZone.current.secondsFromGMT()
        return Date(timeIntervalSince1970: TimeInterval(Int(raw) + 946_684_800 - tz))
    }

    // MARK: Lectura de enteros little-endian

    static func u16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    static func u24(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 }
    static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    // MARK: Decodificadores

    struct DeviceInfo { let battery: Int; let charging: Bool; let firmware: String }

    static func parseDeviceInfo(_ p: [UInt8]) -> DeviceInfo? {
        guard p.count >= 6 else { return nil }
        let sub = Int(p[2]), main = Int(p[3])
        let fw = sub < 10 ? "\(main).0\(sub)" : "\(main).\(sub)"
        return DeviceInfo(battery: Int(p[5]), charging: p[4] != 0, firmware: fw)
    }

    struct RealSport { let steps: Int; let distanceM: Int; let kcal: Int }

    static func parseRealSport(_ p: [UInt8]) -> RealSport? {
        guard p.count >= 6 else { return nil }
        return RealSport(steps: u16(p, 0), distanceM: u16(p, 2), kcal: u16(p, 4))
    }

    /// Característica FEA1: [flag][pasos 3B][distancia 3B][kcal 3B]
    static func parsePedometer(_ d: Data) -> RealSport? {
        let b = [UInt8](d)
        guard b.count >= 10 else { return nil }
        return RealSport(steps: u24(b, 1), distanceM: u24(b, 4), kcal: u24(b, 7))
    }

    /// Característica estándar 2A37.
    static func parseHeartMeasurement(_ d: Data) -> Int? {
        let b = [UInt8](d)
        guard b.count >= 2 else { return nil }
        if b[0] & 0x01 == 0 { return Int(b[1]) }
        guard b.count >= 3 else { return nil }
        return u16(b, 1)
    }

    // Historial

    struct SportRecord { let start: Date; let end: Date; let steps: Int; let distanceM: Int; let kcal: Int }
    struct HeartRecord { let time: Date; let bpm: Int }
    struct HealthRecord {
        let time: Date
        let steps: Int
        let bpm: Int
        let sbp: Int, dbp: Int
        let spo2: Int
        let respiration: Int
        let hrv: Int
        let tempC: Double?
    }
    struct BodyRecord {
        let time: Date
        let load: Double, hrv: Double, stress: Double, energy: Double, sympathetic: Double
        let sdnn: Int, vo2max: Int, pnn50: Int, rmssd: Int, lfhf: Double
    }

    /// Estrés / energía (historial 0x33), registros de 28 bytes.
    static func parseBody(_ b: [UInt8]) -> [BodyRecord] {
        var out: [BodyRecord] = []
        var i = 0
        func dec(_ a: UInt8, _ f: UInt8) -> Double { Double("\(a).\(f)") ?? Double(a) }
        while i + 28 <= b.count {
            out.append(BodyRecord(time: date(fromDevice: u32(b, i)),
                                  load: dec(b[i + 4], b[i + 5]), hrv: dec(b[i + 6], b[i + 7]),
                                  stress: dec(b[i + 8], b[i + 9]), energy: dec(b[i + 10], b[i + 11]),
                                  sympathetic: dec(b[i + 12], b[i + 13]),
                                  sdnn: u16(b, i + 14), vo2max: Int(b[i + 16]), pnn50: Int(b[i + 17]),
                                  rmssd: u16(b, i + 18), lfhf: Double(b[i + 24]) / 10))
            i += 28
        }
        return out
    }

    /// Datos combinados en vivo (06 03): [sistólica, diastólica, pulso, hrv?, spo2?, temp?]
    struct RealCombined { let sbp: Int; let dbp: Int; let bpm: Int; let hrv: Int?; let spo2: Int?; let tempC: Double? }
    static func parseRealCombined(_ p: [UInt8]) -> RealCombined? {
        guard p.count >= 3 else { return nil }
        let hrv = p.count > 3 ? Int(p[3]) : nil
        let spo2 = p.count > 4 ? Int(p[4]) : nil
        let temp = p.count > 6 && p[5] > 0 ? Double("\(p[5]).\(p[6])") : nil
        return RealCombined(sbp: Int(p[0]), dbp: Int(p[1]), bpm: Int(p[2]), hrv: hrv, spo2: spo2, tempC: temp)
    }

    /// Muestras de ECG (06 05): enteros de 24 bits con signo.
    static func parseECG(_ p: [UInt8]) -> [Int] {
        var out: [Int] = []
        var i = 0
        while i + 2 < p.count {
            var v = Int(p[i]) | Int(p[i + 1]) << 8 | Int(p[i + 2]) << 16
            if p[i + 2] & 0x80 != 0 { v -= 1 << 24 }
            out.append(v)
            i += 3
        }
        return out
    }
    struct SleepStage { let type: Int; let start: Date; let seconds: Int } // 241 profundo, 242 ligero, 243 REM, 244 despierto
    struct SleepRecord { let start: Date; let end: Date; let stages: [SleepStage] }

    static func parseSport(_ b: [UInt8]) -> [SportRecord] {
        var out: [SportRecord] = []
        var i = 0
        while i + 14 <= b.count {
            out.append(SportRecord(start: date(fromDevice: u32(b, i)), end: date(fromDevice: u32(b, i + 4)),
                                   steps: u16(b, i + 8), distanceM: u16(b, i + 10), kcal: u16(b, i + 12)))
            i += 14
        }
        return out
    }

    static func parseHeart(_ b: [UInt8]) -> [HeartRecord] {
        var out: [HeartRecord] = []
        var i = 0
        while i + 6 <= b.count {
            let bpm = Int(b[i + 5])
            if bpm > 0 { out.append(HeartRecord(time: date(fromDevice: u32(b, i)), bpm: bpm)) }
            i += 6
        }
        return out
    }

    static func parseAll(_ b: [UInt8]) -> [HealthRecord] {
        var out: [HealthRecord] = []
        var i = 0
        while i + 20 <= b.count {
            let tInt = Int(b[i + 13]), tDec = Int(b[i + 14])
            let temp: Double? = tInt > 0 ? Double("\(tInt).\(tDec)") : nil
            out.append(HealthRecord(time: date(fromDevice: u32(b, i)),
                                    steps: u16(b, i + 4),
                                    bpm: Int(b[i + 6]),
                                    sbp: Int(b[i + 7]), dbp: Int(b[i + 8]),
                                    spo2: Int(b[i + 9]),
                                    respiration: Int(b[i + 10]),
                                    hrv: Int(b[i + 11]),
                                    tempC: temp))
            i += 20
        }
        return out
    }

    static func parseSleep(_ b: [UInt8]) -> [SleepRecord] {
        var out: [SleepRecord] = []
        var i = 0
        while i + 20 <= b.count {
            let blockLen = u16(b, i + 2)
            guard blockLen >= 20 else { break }
            let start = date(fromDevice: u32(b, i + 4))
            let end = date(fromDevice: u32(b, i + 8))
            var stages: [SleepStage] = []
            let segStart = i + 20
            var j = segStart
            while (j - segStart) + 8 <= blockLen - 20, j + 8 <= b.count {
                let type = Int(b[j])
                let t = date(fromDevice: u32(b, j + 1))
                let secs = u24(b, j + 5)
                if !stages.contains(where: { $0.start == t }) {
                    stages.append(SleepStage(type: type, start: t, seconds: secs))
                }
                j += 8
            }
            out.append(SleepRecord(start: start, end: end, stages: stages))
            i = max(j, i + 20)
        }
        return out
    }

    static func hex(_ d: Data) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }
    static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }
}
