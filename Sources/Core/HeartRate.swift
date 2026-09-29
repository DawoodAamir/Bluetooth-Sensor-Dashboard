import Foundation

public struct HeartRateMeasurement: Equatable {
    public let beatsPerMinute: Int
    public let contactDetected: Bool?
    public let energyExpended: Int?
    public let rrIntervals: [Double]
    public static func decode(_ data: Data) throws -> HeartRateMeasurement {
        let bytes = Array(data)
        guard let flags = bytes.first else { throw PacketError.truncated }
        var cursor = 1
        func byte() throws -> Int {
            guard cursor < bytes.count else { throw PacketError.truncated }
            defer { cursor += 1 }
            return Int(bytes[cursor])
        }
        func word() throws -> Int {
            let low = try byte()
            return low | ((try byte()) << 8)
        }
        let bpm = try flags & 1 != 0 ? word() : byte()
        let contact: Bool? = flags & 4 != 0 ? flags & 2 != 0 : nil
        let energy = try flags & 8 != 0 ? word() : nil
        var rr: [Double] = []
        if flags & 16 != 0 {
            guard cursor < bytes.count else { throw PacketError.truncated }
            while cursor < bytes.count { rr.append(Double(try word()) / 1024) }
        }
        guard cursor == bytes.count else { throw PacketError.unexpectedData }
        return HeartRateMeasurement(
            beatsPerMinute: bpm, contactDetected: contact, energyExpended: energy, rrIntervals: rr)
    }
}
public enum PacketError: LocalizedError {
    case truncated, unexpectedData
    public var errorDescription: String? {
        switch self {
        case .truncated: return "The sensor sent an incomplete heart-rate packet."
        case .unexpectedData: return "The sensor packet has an unsupported payload."
        }
    }
}
public struct SensorSample: Codable, Identifiable {
    public var id = UUID()
    public let date: Date
    public let bpm: Int
    public let rrIntervals: [Double]
    public init(date: Date = Date(), bpm: Int, rrIntervals: [Double] = []) {
        self.date = date
        self.bpm = bpm
        self.rrIntervals = rrIntervals
    }
}
public enum SensorCSV {
    public static func encode(_ samples: [SensorSample], demo: Bool) -> String {
        let formatter = ISO8601DateFormatter()
        return "timestamp,bpm,rr_seconds,source\r\n"
            + samples.map {
                "\(formatter.string(from: $0.date)),\($0.bpm),\($0.rrIntervals.map { String($0) }.joined(separator: ";")),\(demo ? "demo" : "bluetooth")"
            }.joined(separator: "\r\n") + "\r\n"
    }
}
