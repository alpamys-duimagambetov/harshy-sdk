import Foundation

/// Compact GPS sample: keeps time, position, speed, accuracy, road RMS and the mapped speed limit.
/// Drops altitude, course and altitude accuracy. Matches `compactLocationSample` in `@harshy/core`
/// and Kotlin; the dropped fields are left out of the JSON, as `stringifySessionExport` does.
public func harshyCompactLocationSample(_ sample: HarshyLocationSample) -> HarshyLocationSample {
  var compact = sample
  compact.altitudeM = nil
  compact.courseDeg = nil
  compact.altitudeAccuracyM = nil
  return compact
}

/// Session without raw IMU and with compact location samples. Every location sample is kept.
/// Matches `compactSessionExport` in `@harshy/core` and Kotlin.
public func harshyCompactSessionExport(_ session: HarshySessionExport) -> HarshySessionExport {
  var compact = session
  compact.location = session.location.map(harshyCompactLocationSample)
  compact.imu = []
  return compact
}
