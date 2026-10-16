import XCTest
@testable import HarshyMath

/// Mirrors `ConfigMapsTest.kt`, plus the cases that only exist in Swift: `NSNumber` booleans from
/// `JSONSerialization`, and a guard that every config field can be set from a map.
final class HarshyConfigMapsTests: XCTestCase {
  private let base = HarshyDetectorConfig.default

  func testNilOrEmptyMapKeepsTheBase() {
    XCTAssertEqual(harshyDetectorConfig(fromMap: nil), base)
    XCTAssertEqual(harshyDetectorConfig(fromMap: [:]), base)
  }

  func testAppliesKnownKeysAndAcceptsAnyNumberType() {
    let config = harshyDetectorConfig(fromMap: [
      "harshBrakeMps2": 3.5,
      "cooldownMs": 4000,
      "harshMediumX": Float(1.25),
      "harshHeavyX": NSNumber(value: 2.5),
    ])
    XCTAssertEqual(config.harshBrakeMps2, 3.5)
    XCTAssertEqual(config.cooldownMs, 4000)
    XCTAssertEqual(config.harshMediumX, 1.25)
    XCTAssertEqual(config.harshHeavyX, 2.5)
    XCTAssertEqual(config.harshAccelMps2, base.harshAccelMps2)
  }

  func testIgnoresUnknownKeysAndInvalidValues() {
    let config = harshyDetectorConfig(fromMap: [
      "notAKey": 1.0,
      "harshAccelMps2": "3",
      "harshBrakeMps2": -1.0,
      "minSpeedMps": Double.nan,
      "cooldownMs": Double.infinity,
      "impactVerticalMax": 1.5,
      "speedingExitX": 1.01,
    ])
    XCTAssertEqual(config, base)
  }

  func testZeroIsAllowedOnlyWhereTheSchemaAllowsIt() {
    let config = harshyDetectorConfig(fromMap: ["minSpeedMps": 0, "harshCornerMps2": 0])
    XCTAssertEqual(config.minSpeedMps, 0)
    XCTAssertEqual(config.harshCornerMps2, base.harshCornerMps2)
  }

  func testUpperLimitsAreInclusive() {
    let config = harshyDetectorConfig(fromMap: ["speedingExitX": 1.0, "impactVerticalMax": 1.0, "handheldBaselineAlpha": 1.0])
    XCTAssertEqual(config.speedingExitX, 1.0)
    XCTAssertEqual(config.impactVerticalMax, 1.0)
    XCTAssertEqual(config.handheldBaselineAlpha, 1.0)
  }

  func testSpeedingCanBeSetAndSwitchedOff() {
    let on = harshyDetectorConfig(fromMap: ["speedingMps": 22.0])
    XCTAssertEqual(on.speedingMps, 22.0)
    XCTAssertNil(harshyDetectorConfig(fromMap: ["speedingMps": NSNull()], base: on).speedingMps)
    XCTAssertEqual(harshyDetectorConfig(fromMap: ["speedingMps": 0], base: on).speedingMps, 22.0)
    XCTAssertEqual(harshyDetectorConfig(fromMap: ["speedingMps": "fast"], base: on).speedingMps, 22.0)
    XCTAssertEqual(harshyDetectorConfig(fromMap: [:], base: on).speedingMps, 22.0, "an absent key is not null")
  }

  func testLayersOnTheGivenBase() {
    var custom = HarshyDetectorConfig.default
    custom.harshAccelMps2 = 2.0
    let config = harshyDetectorConfig(fromMap: ["harshBrakeMps2": 4.0], base: custom)
    XCTAssertEqual(config.harshAccelMps2, 2.0)
    XCTAssertEqual(config.harshBrakeMps2, 4.0)
  }

  func testUpdatesScoreWeightsFromANestedMap() {
    let config = harshyDetectorConfig(fromMap: ["score": ["harshBrake": 10, "refDistanceKm": -1.0, "swerve": 0]])
    XCTAssertEqual(config.score.harshBrake, 10)
    XCTAssertEqual(config.score.swerve, 0, "score weights accept zero")
    XCTAssertEqual(config.score.refDistanceKm, base.score.refDistanceKm)
  }

  func testScoreMapAcceptsOptionalValuedAndObjectiveCDictionaries() {
    let optionalValued: [String: Any?] = ["harshBrake": 11.0]
    XCTAssertEqual(harshyDetectorConfig(fromMap: ["score": optionalValued]).score.harshBrake, 11)
    let nsDictionary: NSDictionary = ["harshBrake": 12.0]
    XCTAssertEqual(harshyDetectorConfig(fromMap: ["score": nsDictionary]).score.harshBrake, 12)
  }

  // MARK: Swift-specific

  func testDecodedJsonBooleansAreNotNumbersButZeroAndOneAre() throws {
    let json = #"{"minSpeedMps": 0, "harshBrakeMps2": true, "cooldownMs": 1, "harshAccelMps2": false, "speedingMps": null}"#
    let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let config = harshyDetectorConfig(fromMap: raw, base: HarshyDetectorConfig(speedingMps: 30))
    XCTAssertEqual(config.minSpeedMps, 0, "a real 0 must not be mistaken for false")
    XCTAssertEqual(config.cooldownMs, 1, "a real 1 must not be mistaken for true")
    XCTAssertEqual(config.harshBrakeMps2, base.harshBrakeMps2, "true is not a number")
    XCTAssertEqual(config.harshAccelMps2, base.harshAccelMps2, "false is not a number")
    XCTAssertNil(config.speedingMps, "JSON null switches speeding off")
  }

  func testSwiftBooleansAreRejectedToo() {
    XCTAssertEqual(harshyDetectorConfig(fromMap: ["harshBrakeMps2": true]).harshBrakeMps2, base.harshBrakeMps2)
  }

  func testAnOptionalNilBoxedInAnyIsTreatedAsNull() {
    let missing: Double? = nil
    let raw: [String: Any] = ["speedingMps": missing as Any]
    XCTAssertNil(harshyDetectorConfig(fromMap: raw, base: HarshyDetectorConfig(speedingMps: 30)).speedingMps)
  }

  func testTheSdksOwnJsonRoundTripsThroughTheMapReader() {
    var custom = HarshyDetectorConfig.default
    custom.harshBrakeMps2 = 3.7
    custom.speedingMps = 25
    custom.score.harshAccel = 9
    custom.handheldBaselineAlpha = 0.5
    // Catches a key typo in the reader: the writer and reader must agree on every name.
    XCTAssertEqual(harshyDetectorConfig(fromMap: custom.toJSONObject()), custom)
    XCTAssertEqual(harshyDetectorConfig(fromMap: HarshyDetectorConfig.default.toJSONObject()), HarshyDetectorConfig.default)
  }

  func testEveryNumericConfigFieldCanBeSetFromAMap() {
    // Fails when someone adds a field to the config struct and forgets to register its key.
    for (label, value) in Mirror(reflecting: HarshyDetectorConfig.default).children {
      guard let label, let current = value as? Double else { continue }
      let target = current == 0.5 ? 0.25 : 0.5
      let config = harshyDetectorConfig(fromMap: [label: target])
      let after = Mirror(reflecting: config).children.first { $0.label == label }?.value as? Double
      XCTAssertEqual(after, target, "config field \(label) is not readable from a map")
    }
    for (label, value) in Mirror(reflecting: HarshyDetectorScoreWeights()).children {
      guard let label, let current = value as? Double else { continue }
      let target = current == 0.5 ? 0.25 : 0.5
      let config = harshyDetectorConfig(fromMap: ["score": [label: target]])
      let after = Mirror(reflecting: config.score).children.first { $0.label == label }?.value as? Double
      XCTAssertEqual(after, target, "score field \(label) is not readable from a map")
    }
  }

  // MARK: Capture options

  func testCaptureOptionsAreClampedAndLayered() {
    let start = HarshyNativeStartOptions(imuHz: 25, locationIntervalMs: 1_000, background: false)
    XCTAssertEqual(harshyNativeStartOptions(fromMap: nil, base: start), start)
    let parsed = harshyNativeStartOptions(
      fromMap: ["imuHz": 500, "locationIntervalMs": 50, "background": true, "trigger": "auto"],
      base: start
    )
    XCTAssertEqual(parsed.imuHz, 100)
    XCTAssertEqual(parsed.locationIntervalMs, 200)
    XCTAssertEqual(parsed.background, false, "a remote config tunes rates only")
    XCTAssertNil(parsed.trigger)
    XCTAssertEqual(harshyNativeStartOptions(fromMap: ["imuHz": 40.7], base: start).imuHz, 41)
    XCTAssertEqual(harshyNativeStartOptions(fromMap: ["imuHz": 2], base: start).imuHz, 5)
    XCTAssertEqual(harshyNativeStartOptions(fromMap: ["locationIntervalMs": "fast"], base: start).locationIntervalMs, 1_000)
    XCTAssertEqual(harshyNativeStartOptions(fromMap: ["imuHz": true], base: start).imuHz, 25)
  }

  func testCaptureOptionsNeverTrapOnExtremeNumbers() {
    let start = HarshyNativeStartOptions(imuHz: 25, locationIntervalMs: 1_000)
    // Int(Double) traps outside Int's range; the reader must clamp first.
    let huge = harshyNativeStartOptions(fromMap: ["imuHz": 1e300, "locationIntervalMs": -1e300], base: start)
    XCTAssertEqual(huge.imuHz, 100)
    XCTAssertEqual(huge.locationIntervalMs, 200)
    let notFinite = harshyNativeStartOptions(fromMap: ["imuHz": Double.nan, "locationIntervalMs": Double.infinity], base: start)
    XCTAssertEqual(notFinite, start)
  }

  /// Pins the published ranges. `HarshyEngine` clamps with its own literals (`clampInt` in `start` and
  /// `startPreview`) and imports UIKit, so this package cannot compile it: keep the two in step by hand.
  func testCaptureRangesArePinned() {
    XCTAssertEqual(harshyImuHzRange, 5...100)
    XCTAssertEqual(harshyLocationIntervalMsRange, 200...5_000)
  }
}
