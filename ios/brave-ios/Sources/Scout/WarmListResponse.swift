import Foundation

/// What to do with a reply from the warm-list endpoint.
///
/// Reading the reply is the whole of the interesting logic in downloading a
/// warm list — the rest is a URL request and a file write — and it is where
/// both of this feature's shipped bugs lived. It is separated out here so it
/// can be exercised without a network, a disk or a preference store.
public enum WarmListUpdate: Equatable {
  /// A list came down. Install it, and let it age from `builtAt`.
  case install(version: String, builtAt: TimeInterval)
  /// The server re-asserted the list this phone already holds. Nothing to
  /// download — but the confirmation has to be recorded, or the held list
  /// ages out and never recovers.
  case stillCurrent(builtAt: TimeInterval)
  /// Nothing usable. Keep whatever is held; a stale list beats none.
  case ignore
}

public enum WarmListResponse {
  /// Reads a reply body.
  ///
  /// Three things are refused rather than acted on: a reply with no build
  /// date, since the age check would then be measuring when this phone
  /// downloaded something rather than when the data was made; an empty entry
  /// list, which the server sends when nothing is common enough to publish
  /// and which would otherwise replace a real list with nothing; and anything
  /// that does not parse.
  public static func read(_ data: Data) -> WarmListUpdate {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let builtAt = object["builtAt"] as? TimeInterval, builtAt > 0
    else { return .ignore }

    guard let rows = object["entries"] as? [[String: Any]] else {
      return .stillCurrent(builtAt: builtAt)
    }
    guard !rows.isEmpty, let version = object["version"] as? String else { return .ignore }
    return .install(version: version, builtAt: builtAt)
  }

  /// Whether the phone should ask for a newer list.
  ///
  /// `lastCheckedAt` is seconds since the epoch, 0 meaning never. A stamp in
  /// the future — a clock that moved backwards, a restored backup — counts as
  /// due rather than as "wait", so a wrong clock cannot switch refreshing off
  /// for as long as it stays wrong.
  public static func isRefreshDue(
    lastCheckedAt: TimeInterval, now: Date, interval: TimeInterval
  ) -> Bool {
    let elapsed = now.timeIntervalSince1970 - lastCheckedAt
    return elapsed < 0 || elapsed > interval
  }
}
