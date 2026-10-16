import Foundation

/// Capture rates the native engines accept. Values outside are clamped.
/// `HarshyEngine.start` and `startPreview` clamp with the same literals; keep them in step.
public let harshyImuHzRange = 5...100
public let harshyLocationIntervalMsRange = 200...5_000

/// Detector config from a loosely typed map, such as remote configuration or decoded JSON, layered on `base`.
///
/// Keys use the `HarshyDetectorConfig` field names. Unknown keys are ignored. A value that is not a number
/// (a string or a boolean included), is not finite, or breaks the bounds of the `@harshy/core` schema keeps
/// the `base` value, so one bad key never discards the rest. `speedingMps` may be `NSNull` to switch
/// speeding off. A nested `score` map updates the score weights the same way.
public func harshyDetectorConfig(
  fromMap raw: [String: Any]?,
  base: HarshyDetectorConfig = .default
) -> HarshyDetectorConfig {
  var config = harshyMergeDetectorConfig(base)
  guard let raw else {
    return config
  }
  for rule in harshyDetectorRules {
    if let value = rule.value(raw[rule.key]) {
      config[keyPath: rule.path] = value
    }
  }
  if raw.keys.contains("speedingMps") {
    let value = raw["speedingMps"]
    if harshyIsNull(value) {
      config.speedingMps = nil
    } else if let speed = harshyFiniteDouble(value), speed > 0 {
      config.speedingMps = speed
    }
  }
  if let scoreRaw = harshyStringKeyed(raw["score"]) {
    for rule in harshyScoreRules {
      if let value = rule.value(scoreRaw[rule.key]) {
        config.score[keyPath: rule.path] = value
      }
    }
  }
  return config
}

/// Capture options from a loosely typed map, layered on `base`. `imuHz` and `locationIntervalMs` are
/// rounded and clamped to `harshyImuHzRange` and `harshyLocationIntervalMsRange`. Every other key,
/// including `background` and `trigger`, is ignored and keeps the `base` value: a remote config tunes
/// rates only.
public func harshyNativeStartOptions(
  fromMap raw: [String: Any]?,
  base: HarshyNativeStartOptions = HarshyNativeStartOptions()
) -> HarshyNativeStartOptions {
  guard let raw else {
    return base
  }
  var options = base
  if let hz = harshyFiniteDouble(raw["imuHz"]) {
    options.imuHz = harshyClampedRound(hz, harshyImuHzRange)
  }
  if let intervalMs = harshyFiniteDouble(raw["locationIntervalMs"]) {
    options.locationIntervalMs = harshyClampedRound(intervalMs, harshyLocationIntervalMsRange)
  }
  return options
}

// MARK: Parsing

/// Clamp in the Double domain first: converting an out-of-range Double to Int traps.
private func harshyClampedRound(_ value: Double, _ range: ClosedRange<Int>) -> Int {
  Int(min(max(value, Double(range.lowerBound)), Double(range.upperBound)).rounded())
}

/// A finite number, or nil. Strings and booleans are rejected: `JSONSerialization` hands `true` back as an
/// `NSNumber`, which would otherwise read as 1.
func harshyFiniteDouble(_ value: Any?) -> Double? {
  guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
    return nil
  }
  let double = number.doubleValue
  return double.isFinite ? double : nil
}

private func harshyIsNull(_ value: Any?) -> Bool {
  guard let value else { return true }
  if value is NSNull { return true }
  // An optional that is nil, boxed in `Any`.
  let mirror = Mirror(reflecting: value)
  return mirror.displayStyle == .optional && mirror.children.isEmpty
}

// MARK: Rules

private enum HarshyBound {
  case any
  case positive
  case nonNegative
}

/// One accepted key: where it lands, the schema bound, and an optional upper limit.
private struct HarshyRule<Root> {
  let key: String
  let path: WritableKeyPath<Root, Double>
  let bound: HarshyBound
  let max: Double?

  init(_ key: String, _ path: WritableKeyPath<Root, Double>, _ bound: HarshyBound, max: Double? = nil) {
    self.key = key
    self.path = path
    self.bound = bound
    self.max = max
  }

  func value(_ raw: Any?) -> Double? {
    guard let value = harshyFiniteDouble(raw) else { return nil }
    switch bound {
    case .any: break
    case .positive: if value <= 0 { return nil }
    case .nonNegative: if value < 0 { return nil }
    }
    if let max, value > max { return nil }
    return value
  }
}

/// Bounds mirror `detectorConfigSchema` in `@harshy/core/src/schemas.ts` and Kotlin `ConfigMaps.kt`.
private let harshyDetectorRules: [HarshyRule<HarshyDetectorConfig>] = [
  HarshyRule("harshAccelMps2", \.harshAccelMps2, .positive),
  HarshyRule("harshBrakeMps2", \.harshBrakeMps2, .positive),
  HarshyRule("harshCornerMps2", \.harshCornerMps2, .positive),
  HarshyRule("harshMediumX", \.harshMediumX, .positive),
  HarshyRule("harshHeavyX", \.harshHeavyX, .positive),
  HarshyRule("harshSwerveRadps", \.harshSwerveRadps, .positive),
  HarshyRule("harshSwerveJerkRadps2", \.harshSwerveJerkRadps2, .positive),
  HarshyRule("swerveMinSpeedMps", \.swerveMinSpeedMps, .nonNegative),
  HarshyRule("swerveMaxElevatedMs", \.swerveMaxElevatedMs, .positive),
  HarshyRule("speedingExitX", \.speedingExitX, .positive, max: 1),
  HarshyRule("minSpeedMps", \.minSpeedMps, .nonNegative),
  HarshyRule("cooldownMs", \.cooldownMs, .nonNegative),
  HarshyRule("compoundWindowMs", \.compoundWindowMs, .nonNegative),
  HarshyRule("jerkSettleMs", \.jerkSettleMs, .nonNegative),
  HarshyRule("gpsAccelWindowMs", \.gpsAccelWindowMs, .positive),
  HarshyRule("maxLocationAccuracyM", \.maxLocationAccuracyM, .positive),
  HarshyRule("impactFloorMps2", \.impactFloorMps2, .positive),
  HarshyRule("impactPeakMps2", \.impactPeakMps2, .positive),
  HarshyRule("impactPeakHighMps2", \.impactPeakHighMps2, .positive),
  HarshyRule("impactPulseMaxMs", \.impactPulseMaxMs, .positive),
  HarshyRule("impactSpeedDeltaMps", \.impactSpeedDeltaMps, .nonNegative),
  HarshyRule("impactLookaheadMs", \.impactLookaheadMs, .positive),
  HarshyRule("impactCooldownMs", \.impactCooldownMs, .nonNegative),
  HarshyRule("impactVerticalMax", \.impactVerticalMax, .nonNegative, max: 1),
  HarshyRule("impactFreeFallMps2", \.impactFreeFallMps2, .positive),
  HarshyRule("impactFreeFallLookbackMs", \.impactFreeFallLookbackMs, .nonNegative),
  HarshyRule("impactRolloverDeg", \.impactRolloverDeg, .positive),
  HarshyRule("handheldTiltDeg", \.handheldTiltDeg, .positive),
  HarshyRule("handheldExitTiltDeg", \.handheldExitTiltDeg, .positive),
  HarshyRule("handheldGyroRadps", \.handheldGyroRadps, .positive),
  HarshyRule("handheldMotionMps2", \.handheldMotionMps2, .positive),
  HarshyRule("handheldQuietGyroRadps", \.handheldQuietGyroRadps, .positive),
  HarshyRule("handheldQuietMotionMps2", \.handheldQuietMotionMps2, .positive),
  HarshyRule("handheldStableMs", \.handheldStableMs, .nonNegative),
  HarshyRule("handheldConfirmMs", \.handheldConfirmMs, .nonNegative),
  HarshyRule("handheldExitMs", \.handheldExitMs, .nonNegative),
  HarshyRule("handheldCooldownMs", \.handheldCooldownMs, .nonNegative),
  HarshyRule("handheldBaselineAlpha", \.handheldBaselineAlpha, .positive, max: 1),
]

private let harshyScoreRules: [HarshyRule<HarshyDetectorScoreWeights>] = [
  HarshyRule("start", \.start, .any),
  HarshyRule("harshAccel", \.harshAccel, .any),
  HarshyRule("harshBrake", \.harshBrake, .any),
  HarshyRule("harshCorner", \.harshCorner, .any),
  HarshyRule("swerve", \.swerve, .any),
  HarshyRule("speeding", \.speeding, .any),
  HarshyRule("jerk", \.jerk, .any),
  HarshyRule("compound", \.compound, .any),
  HarshyRule("smoothAccel", \.smoothAccel, .nonNegative),
  HarshyRule("smoothBrake", \.smoothBrake, .nonNegative),
  HarshyRule("smoothCorner", \.smoothCorner, .nonNegative),
  HarshyRule("refDistanceKm", \.refDistanceKm, .positive),
  HarshyRule("refDurationMin", \.refDurationMin, .positive),
  HarshyRule("minDistanceKm", \.minDistanceKm, .positive),
  HarshyRule("minDurationMin", \.minDurationMin, .positive),
]
