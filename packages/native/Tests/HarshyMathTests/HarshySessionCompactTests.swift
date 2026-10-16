import XCTest
@testable import HarshyMath

/// Mirrors `SessionCompactTest.kt` and the compact rules in `@harshy/core` (`session-compact.ts`).
final class HarshySessionCompactTests: XCTestCase {
  private let fix = HarshyLocationSample(
    t: 1,
    lat: 32,
    lon: 34,
    altitudeM: 10,
    speedMps: 10,
    courseDeg: 90,
    accuracyM: 5,
    altitudeAccuracyM: 2,
    roadRmsMps2: 1.4,
    speedLimitMps: 13.9
  )

  private func session(trigger: String = "auto") -> HarshySessionExport {
    var locations: [HarshyLocationSample] = []
    for index in 0..<30 {
      var sample = fix
      sample.t = 1_700_000_000_000 + Double(index) * 1000
      sample.lat = 59.437 + Double(index) * 0.0002
      sample.lon = 24.7536
      sample.speedMps = 12 + Double(index % 5)
      locations.append(sample)
    }
    let imu = (0..<20).map { index in
      HarshyImuSample(
        t: 1_700_000_000_000 + Double(index) * 20,
        accel: HarshyVec3(x: 0.1, y: 0.2, z: 9.8),
        gyro: HarshyVec3(x: 0, y: 0, z: 0.01)
      )
    }
    return harshyAnalyzeTrip(
      location: locations,
      imu: imu,
      sessionId: "trip-1",
      startedAtMs: 1_700_000_000_000,
      endedAtMs: 1_700_000_030_000,
      device: HarshyDeviceInfo(platform: "ios", model: "test"),
      trigger: trigger,
      capture: HarshyNativeStartOptions(imuHz: 25, locationIntervalMs: 1_000, background: true)
    )
  }

  func testCompactLocationKeepsSpeedAccuracyRoadRmsAndLimit() {
    XCTAssertEqual(
      harshyCompactLocationSample(fix),
      HarshyLocationSample(t: 1, lat: 32, lon: 34, speedMps: 10, accuracyM: 5, roadRmsMps2: 1.4, speedLimitMps: 13.9)
    )
  }

  func testCompactSessionDropsImuAndKeepsEveryLocationSample() {
    let original = session()
    XCTAssertFalse(original.imu.isEmpty, "the fixture must have IMU to drop")
    let compact = harshyCompactSessionExport(original)
    XCTAssertTrue(compact.imu.isEmpty)
    XCTAssertEqual(compact.location.map(\.t), original.location.map(\.t))
    XCTAssertTrue(compact.location.allSatisfy { $0.altitudeM == nil && $0.courseDeg == nil && $0.altitudeAccuracyM == nil })
  }

  func testCompactSessionLeavesEverythingElseUntouched() {
    let original = session()
    let compact = harshyCompactSessionExport(original)
    XCTAssertEqual(compact.schemaVersion, original.schemaVersion)
    XCTAssertEqual(compact.sdkVersion, original.sdkVersion)
    XCTAssertEqual(compact.sessionId, original.sessionId)
    XCTAssertEqual(compact.startedAt, original.startedAt)
    XCTAssertEqual(compact.endedAt, original.endedAt)
    XCTAssertEqual(compact.config, original.config)
    XCTAssertEqual(compact.metrics, original.metrics)
    XCTAssertEqual(compact.device, original.device)
    XCTAssertEqual(compact.trigger, original.trigger)
    XCTAssertEqual(compact.capture, original.capture)
    XCTAssertEqual(compact.events.map(\.id), original.events.map(\.id))
  }

  func testCompactingDoesNotMutateTheInputAndIsIdempotent() {
    let original = session()
    let once = harshyCompactSessionExport(original)
    XCTAssertFalse(original.imu.isEmpty, "the input keeps its IMU")
    XCTAssertEqual(original.location.first?.altitudeM, 10, "the input keeps its altitude")
    let twice = harshyCompactSessionExport(once)
    XCTAssertEqual(twice.location, once.location)
    XCTAssertTrue(twice.imu.isEmpty)
  }

  func testCompactJsonOmitsTheDroppedFieldsAndKeepsTheRest() throws {
    var noRoad = fix
    noRoad.roadRmsMps2 = nil
    noRoad.speedLimitMps = nil
    noRoad.speedMps = nil
    noRoad.accuracyM = nil
    var original = session()
    original.location = [fix, noRoad]
    let json = harshyCompactSessionExport(original).toJSONObject()
    let locations = try XCTUnwrap(json["location"] as? [[String: Any]])

    // Same rule as `stringifySessionExport` in core: altitudeM, altitudeAccuracyM, courseDeg,
    // roadRmsMps2 and speedLimitMps are omitted when empty; speedMps and accuracyM stay as null.
    XCTAssertEqual(Set(locations[0].keys), ["t", "lat", "lon", "speedMps", "accuracyM", "roadRmsMps2", "speedLimitMps"])
    XCTAssertEqual(Set(locations[1].keys), ["t", "lat", "lon", "speedMps", "accuracyM"])
    XCTAssertTrue(locations[1]["speedMps"] is NSNull)
    XCTAssertTrue(locations[1]["accuracyM"] is NSNull)
    XCTAssertEqual((json["imu"] as? [Any])?.count, 0)
  }

  func testCompactJsonIsValidSmallerAndStillCarriesTheBackendEnvelopeFields() throws {
    let original = session()
    let full = try original.toJSONString()
    let compact = try harshyCompactSessionExport(original).toJSONString()
    XCTAssertLessThan(compact.utf8.count, full.utf8.count)
    let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(compact.utf8)) as? [String: Any])
    for key in ["schemaVersion", "sdkVersion", "sessionId", "startedAt", "endedAt", "config", "location", "imu", "events", "metrics", "device", "trigger", "capture"] {
      XCTAssertNotNil(parsed[key], "missing \(key)")
    }
    XCTAssertEqual(parsed["trigger"] as? String, "auto")
    XCTAssertEqual(parsed["sessionId"] as? String, "trip-1")
  }
}
