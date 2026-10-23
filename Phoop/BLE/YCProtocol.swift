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
    }

    enum HistoryKind: UInt8, CaseIterable {
        case sport = 0x02, sleep = 0x04, heart = 0x06, all = 0x09

        var deleteKey: UInt8 {
            switch self {
            case .sport: return 0x40
            case .sleep: return 0x41
            case .heart: return 0x42
            case .all:   return 0x44
            }
        }

        var label: String {
            switch self {
            case .sport: return "actividad"
            case .sleep: return "sueño"
            case .heart: return "pulso"
            case .all:   return "salud (HRV/SpO₂/temp)"
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
