import Foundation

/// Who asked for a navigation.
public enum NavigationOrigin: Equatable, Sendable {
  /// The user did something that asks for a page: tapped a link, went back or
  /// forward, submitted a form, reloaded.
  case user
  /// The page, the server, or the browser itself asked: a redirect, a meta
  /// refresh, a script navigation — and also a load the browser issues on the
  /// user's behalf, such as an address typed into the bar. WebKit reports
  /// those the same way, which is why origin alone cannot end a permit.
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

/// What one tab remembers about a "Continue anyway".
///
/// The rule it encodes: continuing past a block is a decision about one page,
/// not about a site, a tab or an afternoon. It covers the address the user
/// approved and wherever that address redirects to, and it ends when that
/// navigation arrives.
///
/// Ending it on arrival is the part that matters, and the part a first attempt
/// got wrong. At the WebKit layer an address typed into the bar is a
/// programmatic load — not user-initiated, navigation type `.other` — exactly
/// like a redirect, so no property of the request tells them apart. What tells
/// them apart is when they happen: a redirect arrives before the navigation
/// responds, and whatever the user asks for next arrives after it.
public struct ContinueApproval: Equatable, Sendable {
  private var permit: ContinuePermit?

  /// The page the user chose to see despite a block.
  ///
  /// Not permission to navigate, and never consulted by the guard. It exists
  /// so a check that judges a page *after* it renders — the title check — does
  /// not immediately take back the page the user just asked for. It names one
  /// address, so the next page is judged normally.
  public private(set) var chosenPage: URL?

  public init() {}

  /// Records "Continue anyway" on `url`.
  public mutating func approve(_ url: URL) {
    permit = ContinuePermit(url: url)
    chosenPage = url
  }

  /// Whether the permit covers this request, moving with it if it does.
  public mutating func allows(_ url: URL, origin: NavigationOrigin) -> Bool {
    guard let held = permit else { return false }
    // A fresh ask from the user ends the permit, whatever it was for. This is
    // the line the old per-tab, per-domain allow did not draw at all. It is a
    // second net rather than the main one: the loads that need stopping most
    // do not announce themselves as the user's.
    if origin == .user {
      permit = nil
      return false
    }
    if held.url == url {
      chosenPage = url
      return true
    }
    guard held.hops < ContinuePermit.maxHops else {
      permit = nil
      return false
    }
    permit = ContinuePermit(url: url, hops: held.hops + 1)
    chosenPage = url
    return true
  }

  /// The navigation responded. A permit lives only while its own navigation is
  /// in flight, so this spends it.
  ///
  /// Sub-frame responses are ignored: an image arriving partway through a
  /// redirect chain is not the navigation arriving.
  public mutating func noteArrival(isMainFrame: Bool) {
    guard isMainFrame else { return }
    permit = nil
  }
}
