// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveShared
import Foundation
import Scout
import Shared

/// Scout's checking and block pages live at `internal://local/scout?url=<site>`,
/// the same scheme Brave uses for its own blocked-domain page. That gives them
/// Brave's internal origin (never the blocked site's), and lets the address
/// bar show the site being checked instead of `about:blank` — see
/// `URL.displayURL`.
@MainActor
enum ScoutPages {
  /// The internal URL standing in for `siteURL`.
  static func pageURL(for siteURL: URL) -> URL? {
    siteURL.encodeEmbeddedInternalURL(for: .scout)
  }

  /// The site a Scout page is standing in for, if `url` is one.
  nonisolated static func siteURL(fromPageURL url: URL?) -> URL? {
    guard let url, let internalURL = InternalURL(url), internalURL.isScoutPage else { return nil }
    return internalURL.extractedUrlParam
  }

  static func pageRequest(for siteURL: URL) -> URLRequest? {
    pageURL(for: siteURL).map { PrivilegedRequest(url: $0) as URLRequest }
  }

  static func checkingHTML(for siteURL: URL) -> String {
    channelled(ScoutInterstitial.checkingHTML(host: host(of: siteURL)))
  }

  static func resultHTML(for decision: Scout.Decision, siteURL: URL) -> String {
    // The decision already carries what it matched. Recomputing it from the
    // verdict used to give the same answer and now doesn't: a block decided
    // from the address alone has no verdict to recompute from, and the page
    // read "This page matched: ." with nothing in it.
    return channelled(
      ScoutInterstitial.html(
        type: decision.type,
        verdict: decision.verdict,
        reason: decision.reason,
        matchedCategories: decision.matchedCategories,
        host: host(of: siteURL)
      )
    )
  }

  // MARK: - What the handler should serve

  /// Decisions the live flow already reached, so the page handler can serve
  /// the result — including fail-closed warnings, which are never cached.
  private static var recent: [URL: Scout.Decision] = [:]
  private static var recentOrder: [URL] = []
  private static let recentLimit = 50

  /// Sites the live flow is checking right now: serve the checking page.
  private static var inFlight: Set<URL> = []

  static func beginCheck(_ siteURL: URL) {
    inFlight.insert(siteURL)
  }

  static func record(_ decision: Scout.Decision, for siteURL: URL) {
    inFlight.remove(siteURL)
    if recent.updateValue(decision, forKey: siteURL) == nil {
      recentOrder.append(siteURL)
    }
    if recentOrder.count > recentLimit {
      recent.removeValue(forKey: recentOrder.removeFirst())
    }
  }

  /// The page for `internal://local/scout?url=<site>`.
  ///
  /// Known decision: the result (or, if allowed, a hand-off to the site).
  /// Being checked: the checking page — the live flow reloads this URL once
  /// the decision lands. Neither (back/forward or restore after the cache
  /// dropped it): check now, then answer.
  static func html(for siteURL: URL) async -> String {
    if let decision = knownDecision(for: siteURL) {
      return settled(decision, siteURL: siteURL)
    }
    if inFlight.contains(siteURL) {
      return checkingHTML(for: siteURL)
    }
    let decision = await ScoutServices.shared.guard_.decide(siteURL)
    record(decision, for: siteURL)
    return settled(decision, siteURL: siteURL)
  }

  /// The decision a page for `siteURL` would serve now, or nil when none is
  /// known yet.
  private static func knownDecision(for siteURL: URL) -> Scout.Decision? {
    if let recorded = recent[siteURL], let verdict = recorded.verdict {
      // Re-resolve against the current choice: the user may have changed
      // what Scout blocks since this was recorded.
      return NavigationGuard.resolve(
        verdict, blockedCategories: ScoutServices.shared.decisionPolicy.blockedCategories)
    }
    return recent[siteURL] ?? ScoutServices.shared.guard_.decideImmediately(siteURL)
  }

  /// What a Scout page is showing in place of its site.
  enum Showing {
    case checking
    case stopped(Scout.Decision)
  }

  /// What the page at `pageURL` shows, or nil when it is not a Scout page or
  /// is only handing over to an allowed site.
  ///
  /// For the address bar, which is handed the site's address rather than the
  /// page's and so cannot tell a blocked page from the site itself.
  static func showing(onPage pageURL: URL?) -> Showing? {
    guard let siteURL = siteURL(fromPageURL: pageURL) else { return nil }
    if let decision = knownDecision(for: siteURL) {
      return decision.type == .allow ? nil : .stopped(decision)
    }
    return inFlight.contains(siteURL) ? .checking : nil
  }

  private static func settled(_ decision: Scout.Decision, siteURL: URL) -> String {
    guard decision.type == .allow else {
      return resultHTML(for: decision, siteURL: siteURL)
    }
    let target = ScoutInterstitial.htmlEscaped(siteURL.absoluteString)
    return "<!doctype html><meta http-equiv=\"refresh\" content=\"0;url=\(target)\">"
  }

  private static func host(of siteURL: URL) -> String {
    siteURL.host ?? siteURL.absoluteString
  }

  /// The generated pages post to a fixed channel name; rewrite it to the script
  /// handler's real (UUID-suffixed) name so the buttons reach native.
  private static func channelled(_ html: String) -> String {
    html.replacingOccurrences(
      of: "webkit.messageHandlers.scout",
      with: "webkit.messageHandlers.\(ScoutScriptHandler.messageHandlerName)"
    )
  }
}

/// Serves every Scout page. The live flow navigates the tab to the page URL
/// with a `PrivilegedRequest`, exactly as Brave's blocked-domain page does.
public class ScoutPageHandler: InternalSchemeResponse {
  public static let path = InternalURL.Path.scout.rawValue

  public init() {}

  public func response(forRequest request: URLRequest) async -> (URLResponse, Data)? {
    guard let url = request.url, let internalURL = InternalURL(url),
      let siteURL = ScoutPages.siteURL(fromPageURL: url)
    else { return nil }
    let html = await ScoutPages.html(for: siteURL)
    return (InternalSchemeHandler.response(forUrl: internalURL.url), Data(html.utf8))
  }
}
