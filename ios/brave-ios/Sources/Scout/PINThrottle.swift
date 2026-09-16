import Foundation

/// How many wrong PINs have been entered in a row, and how long the latest one
/// costs. Persisted by the browser, because a count that lives in memory is
/// cleared by force-quitting the app — which is the first thing anyone trying
/// PINs would discover.
///
/// The wait is kept as a length and a starting reading of `PINThrottle.clock()`
/// rather than as a date. It used to be a date, measured against the phone's
/// clock, and the person trying PINs can set that clock: moving it forward past
/// the end of the wait ended the wait.
public struct PINAttempts: Equatable, Sendable {
  public var failures: Int
  /// The wait the latest failure earned, in seconds. Zero when there is none.
  public var lockSeconds: TimeInterval
  /// `PINThrottle.clock()` when that wait began.
  public var lockedAt: TimeInterval

  public init(failures: Int = 0, lockSeconds: TimeInterval = 0, lockedAt: TimeInterval = 0) {
    self.failures = failures
    self.lockSeconds = lockSeconds
    self.lockedAt = lockedAt
  }
}

/// What a wrong PIN costs.
///
/// The PIN is the only thing between a supervised phone and an unsupervised
/// one, and whoever wants it switched off is holding the phone. Four digits is
/// ten thousand combinations — a few hours of patient tapping — and people do
/// not choose PINs uniformly, so a short list of guesses covers a large share
/// of real ones. Unlimited attempts make the PIN decorative.
///
/// The shape is the familiar one: a few free tries so a parent mistyping their
/// own PIN is not punished, then a wait that grows quickly and then stops. At
/// the cap an attacker gets one guess an hour, which turns an afternoon into
/// months; past the cap the wait would only be indistinguishable from a broken
/// phone.
public enum PINThrottle {
  /// Wrong entries before any wait. Mistyping is ordinary.
  public static let freeAttempts = 5

  /// The wait earned by the 1st, 2nd, 3rd… failure past `freeAttempts`.
  /// The last value repeats.
  private static let waits: [TimeInterval] = [60, 300, 900, 3600]

  /// Seconds on a clock the person holding the phone cannot set.
  ///
  /// It keeps counting while the phone sleeps, so a wait ends when it should
  /// with the screen off, and changing the date in Settings does not move it.
  /// It does start again from zero when the phone restarts; `wait` accounts
  /// for that.
  public static func clock() -> TimeInterval {
    TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
  }

  public static func afterFailure(_ state: PINAttempts, now: TimeInterval) -> PINAttempts {
    let failures = state.failures + 1
    let over = failures - freeAttempts
    guard over > 0 else { return PINAttempts(failures: failures) }
    let wait = waits[min(over, waits.count) - 1]
    return PINAttempts(failures: failures, lockSeconds: wait, lockedAt: now)
  }

  /// The right PIN ends it. Nothing is held against someone who knows it.
  public static func afterSuccess() -> PINAttempts {
    PINAttempts()
  }

  /// Seconds to wait before another attempt is allowed. Zero means now.
  ///
  /// Never more than the wait that was earned, and never less than it minus
  /// the time that has certainly passed. A reading below the one the wait
  /// started at means the phone has restarted, which resets the clock; then
  /// only the time since the restart is certain, so only that is counted.
  /// Restarting the phone therefore costs the attacker the restart and gains
  /// nothing.
  public static func wait(_ state: PINAttempts, now: TimeInterval) -> TimeInterval {
    guard state.lockSeconds > 0 else { return 0 }
    let elapsed = max(0, now >= state.lockedAt ? now - state.lockedAt : now)
    return max(0, state.lockSeconds - elapsed)
  }
}
