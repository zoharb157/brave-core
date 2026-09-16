import Foundation

/// Who asked for a navigation.
///
/// The distinction decides how far a "Continue anyway" reaches, so it is named
/// rather than left as a pair of booleans at the call site.
public enum NavigationOrigin: Equatable, Sendable {
  /// The user asked for this one: a link tapped, an address typed, back or
  /// forward, a form submitted.
  case user
  /// The page or the server asked for it: a redirect, a meta refresh, a script
  /// navigation. Part of the navigation already under way.
  case page
}

/// Permission to complete the one navigation the user chose to continue into.
///
/// It travels with the navigation: as the address redirects, the permit moves
/// to wherever it went, counting hops so a redirect loop cannot turn a single
/// approval into an open door.
public struct ContinuePermit: Equatable, Sendable {
  public let url: URL
  public let hops: Int

  /// Redirects one navigation may follow. Beyond this it is a loop, not a
  /// navigation.
  public static let maxHops = 5

  public init(url: URL, hops: Int = 0) {
    self.url = url
    self.hops = hops
  }
}

public enum ContinueRuling: Equatable, Sendable {
  /// Let it through, and hold this permit for the rest of the chain.
  case allow(ContinuePermit)
  /// Not covered by the permit. Check this navigation like any other, and
  /// drop whatever permit was held.
  case check
}

public enum ContinueApproval {
  /// Whether a held permit covers the navigation now being requested.
  ///
  /// The rule this encodes: continuing past a block is a decision about one
  /// page, not about a site, a tab or an afternoon. It covers the address the
  /// user approved and wherever that address redirects to — and stops at the
  /// next thing the user asks for, even if that is the same address again,
  /// because that is a new navigation and deserves a new answer.
  public static func rule(
    on permit: ContinuePermit?, requesting url: URL, origin: NavigationOrigin
  ) -> ContinueRuling {
    guard let permit else { return .check }
    // A fresh ask from the user ends the permit, whatever it is for. This is
    // the line the old per-tab, per-domain allow did not draw.
    if origin == .user { return .check }
    if permit.url == url { return .allow(permit) }
    guard permit.hops < ContinuePermit.maxHops else { return .check }
    return .allow(ContinuePermit(url: url, hops: permit.hops + 1))
  }
}
