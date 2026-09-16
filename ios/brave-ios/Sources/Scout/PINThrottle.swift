import Foundation

/// How many wrong PINs have been entered in a row, and until when that costs
/// time. Persisted by the browser, because a count that lives in memory is
/// cleared by force-quitting the app — which is the first thing anyone trying
/// PINs would discover.
public struct PINAttempts: Equatable, Sendable {
  public var failures: Int
  public var lockedUntil: Date?

  public init(failures: Int = 0, lockedUntil: Date? = nil) {
    self.failures = failures
    self.lockedUntil = lockedUntil
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

  public static func afterFailure(_ state: PINAttempts, now: Date) -> PINAttempts {
    let failures = state.failures + 1
    let over = failures - freeAttempts
    guard over > 0 else { return PINAttempts(failures: failures, lockedUntil: nil) }
    let wait = waits[min(over, waits.count) - 1]
    return PINAttempts(failures: failures, lockedUntil: now.addingTimeInterval(wait))
  }

  /// The right PIN ends it. Nothing is held against someone who knows it.
  public static func afterSuccess() -> PINAttempts {
    PINAttempts()
  }

  /// Seconds to wait before another attempt is allowed. Zero means now.
  ///
  /// Clamped to the longest wait the state could have earned, so winding the
  /// clock back — the first thing anyone tries — cannot turn a short lock into
  /// an endless one, and cannot shorten it either.
  public static func wait(_ state: PINAttempts, now: Date) -> TimeInterval {
    guard let until = state.lockedUntil else { return 0 }
    let remaining = until.timeIntervalSince(now)
    guard remaining > 0 else { return 0 }
    return min(remaining, waits[waits.count - 1])
  }
}
