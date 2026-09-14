// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Onboarding
import Preferences
import Scout
import Shared
import Web

/// Retains the guard for a tab.
///
/// `AnyTabPolicyDecider` holds deciders **weakly**, so a decider nothing else
/// owns is silently dropped and the guard never runs — a failure that looks
/// exactly like "the browser isn't checking anything". Storing the helper in
/// `TabDataValues` is how Brave's own helpers stay alive; we follow that.
extension TabDataValues {
  private struct ScoutTabHelperKey: TabDataKey {
    static var defaultValue: ScoutTabHelper?
  }
  public var scoutTabHelper: ScoutTabHelper? {
    get { self[ScoutTabHelperKey.self] }
    set { self[ScoutTabHelperKey.self] = newValue }
  }
}

@MainActor
public class ScoutTabHelper: TabPolicyDecider {
  weak var tab: (any TabState)?

  public init(tab: some TabState) {
    self.tab = tab
    tab.addPolicyDecider(self)
  }

  public func tab(
    _ tab: some TabState,
    shouldAllowRequest request: URLRequest,
    requestInfo: WebRequestInfo
  ) async -> WebPolicyDecision {
    guard let requestURL = request.url else { return .allow }

    // Only gate top-level document loads. `requestInfo.isMainFrame` is the
    // reliable test — Brave's Shields decider documents that
    // `sourceFrame.isMainFrame` is unreliable on session restore.
    guard ["http", "https", "data", "blob", "file"].contains(requestURL.scheme),
      requestInfo.isMainFrame
    else { return .allow }

    // Never gate internal pages (our own interstitial, error pages, NTP).
    if InternalURL(requestURL) != nil {
      return .allow
    }

    // Reuse Brave's existing per-tab "user proceeded" set rather than adding a
    // parallel one — the interstitial's proceed action writes into it.
    if let etldP1 = requestURL.baseDomain,
      tab.proceedAnywaysDomainList?.contains(etldP1) == true
    {
      return .allow
    }

    // The navigation we re-issued ourselves after an allow. Let it through
    // exactly once — even a fail-open allow, which is never cached.
    if approvedURL == requestURL {
      approvedURL = nil
      return .allow
    }

    // A results page is a wall of thumbnails and snippets: unfiltered, it shows
    // explicit material before anything is clicked. Someone who blocks adult
    // content gets the engine's own filter pinned on.
    if Preferences.Scout.safeSearch.value,
      let filtered = SafeSearch.enforced(requestURL)
    {
      tab.loadRequest(URLRequest(url: filtered))
      return .cancel
    }

    // YouTube's own Restricted Mode, asserted before the page loads. Re-asserted
    // on every visit rather than set once: YouTube rewrites this cookie when
    // anyone turns the switch off inside the site, and a filter a child can
    // switch off from the page it is filtering is not one.
    if Preferences.Scout.safeSearch.value, RestrictedMode.governs(requestURL),
      await restrictYouTube(in: tab)
    {
      tab.loadRequest(request)
      return .cancel
    }

    let services = ScoutServices.shared

    // A site first seen in a private tab is checked like any other, but its
    // verdict is never written to disk.
    if tab.isPrivate {
      services.notePrivateNavigation(to: requestURL)
    }

    // Known already (policy list or cached verdict): no checking page at all.
    if let decision = services.guard_.decideImmediately(requestURL) {
      // The verdict was past its life but inside the grace window: it decided
      // this navigation, and a fresh one lands before the next.
      if decision.isStale {
        Task { await services.guard_.refresh(requestURL) }
      }
      if decision.type == .allow { return .allow }
      Self.note(decision, for: requestURL, in: tab)
      ScoutPages.record(decision, for: requestURL)
      showScoutPage(for: requestURL, in: tab)
      return .cancel
    }

    // The service fetches and AI-analyses the page, which takes seconds. Show
    // that work rather than freezing the tab: cancel, show the checking page,
    // and resolve when the decision lands.
    ScoutPages.beginCheck(requestURL)
    showScoutPage(for: requestURL, in: tab)

    Task { @MainActor [weak self, weak tab] in
      let decision = await services.guard_.decide(requestURL)
      if decision.type != .allow, let tab {
        Self.note(decision, for: requestURL, in: tab)
      }
      ScoutPages.record(decision, for: requestURL)
      // Only act if the tab is still showing this site's checking page; if the
      // user has moved on, the recorded decision just waits in the cache.
      guard let self, let tab, ScoutPages.siteURL(fromPageURL: tab.visibleURL) == requestURL
      else { return }

      if decision.type == .allow {
        approvedURL = requestURL
        replaceCheckingPage(with: requestURL, in: tab)
      } else {
        // Same URL as the checking page, so it replaces it in history; the
        // page handler now serves the recorded result.
        showScoutPage(for: requestURL, in: tab)
      }
    }
    return .cancel
  }

  /// Records a stopped navigation, so Settings → Protection can show what
  /// happened. A private tab is excluded: the point of one is that the visit
  /// leaves no trace, and a log naming the site would be exactly that trace.
  private static func note(_ decision: Scout.Decision, for url: URL, in tab: some TabState) {
    guard !tab.isPrivate, let host = url.host else { return }
    ScoutServices.shared.blockLog.record(
      site: host, reason: decision.reason, categories: decision.matchedCategories)
  }

  /// One-shot pass for the navigation this helper re-issues after an allow.
  private var approvedURL: URL?

  /// Writes YouTube's Restricted Mode into the cookie the site itself reads.
  ///
  /// - Returns: whether anything changed, and so whether the navigation has to
  ///   be made again to carry the new cookie. A visit that is already
  ///   restricted returns false and goes straight through.
  private func restrictYouTube(in tab: some TabState) async -> Bool {
    guard let store = tab.configuration?.websiteDataStore.httpCookieStore else { return false }
    let existing = await store.allCookies().first {
      $0.name == RestrictedMode.cookieName && $0.domain.hasSuffix("youtube.com")
    }
    if let existing, RestrictedMode.isRestricted(existing.value) { return false }

    let value = RestrictedMode.restricting(existing?.value ?? "")
    guard
      let cookie = HTTPCookie(properties: [
        .name: RestrictedMode.cookieName,
        .value: value,
        .domain: RestrictedMode.cookieDomain,
        .path: "/",
        .secure: true,
        // Two years, which is what YouTube itself sets. A session cookie would
        // drop the setting the next time the app is relaunched.
        .expires: Date().addingTimeInterval(2 * 365 * 24 * 3600),
      ])
    else { return false }
    await store.setCookie(cookie)
    return true
  }

  private func showScoutPage(for siteURL: URL, in tab: some TabState) {
    guard let request = ScoutPages.pageRequest(for: siteURL) else { return }
    tab.loadRequest(request)
  }

  /// Hand the allowed site over in place of the checking page, so Back skips
  /// the checking page.
  private func replaceCheckingPage(with siteURL: URL, in tab: some TabState) {
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: siteURL.absoluteString, options: .fragmentsAllowed),
      let literal = String(data: data, encoding: .utf8)
    else {
      tab.loadRequest(URLRequest(url: siteURL))
      return
    }
    tab.evaluateJavaScriptUnsafe("location.replace(\(literal))")
  }
}

