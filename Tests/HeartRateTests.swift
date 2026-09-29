import XCTest

@testable import SensorCore

final class HeartRateTests: XCTestCase {
    func testEightBitMeasurementWithoutContactSupport() throws {
        let result = try HeartRateMeasurement.decode(Data([0, 72]))
        XCTAssertEqual(result.beatsPerMinute, 72)
        XCTAssertNil(result.contactDetected)
        XCTAssertTrue(result.rrIntervals.isEmpty)
    }
    func testSixteenBitEnergyContactAndMultipleRRIntervals() throws {
        let result = try HeartRateMeasurement.decode(Data([0x1F, 0x2C, 0x01, 0x0A, 0, 0, 4, 0, 2]))
        XCTAssertEqual(result.beatsPerMinute, 300)
        XCTAssertEqual(result.energyExpended, 10)
        XCTAssertEqual(result.contactDetected, true)
        XCTAssertEqual(result.rrIntervals, [1, 0.5])
    }
    func testLostContactIsDifferentFromUnsupportedContact() throws {
        XCTAssertEqual(try HeartRateMeasurement.decode(Data([4, 60])).contactDetected, false)
    }
    func testTruncatedOptionalFieldsAreRejected() {
        for bytes: [UInt8] in [[], [0], [1, 90], [8, 90, 1], [16, 90], [16, 90, 1]] {
            XCTAssertThrowsError(try HeartRateMeasurement.decode(Data(bytes)))
        }
    }
    func testUnexpectedTrailingBytesAreRejected() {
        XCTAssertThrowsError(try HeartRateMeasurement.decode(Data([0, 72, 1])))
    }
    func testExportLabelsSimulatedData() {
        let csv = SensorCSV.encode(
            [SensorSample(date: Date(timeIntervalSince1970: 0), bpm: 72, rrIntervals: [1, 0.5])],
            demo: true)
        XCTAssertTrue(csv.contains("1970-01-01T00:00:00Z,72,1.0;0.5,demo"))
        XCTAssertFalse(csv.contains(",bluetooth"))
    }
}
