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
      !restrictedURLs.contains(requestURL),
      await restrictYouTube(in: tab)
    {
      // Re-issue at most once per URL per tab. The cookie is expected to stick
      // and the second pass then goes straight through — but if it ever didn't
      // (a store that drops it, YouTube rewriting PREF as the page loads), an
      // unbounded re-issue would be an endless reload on the site it is
      // supposed to be protecting.
      noteRestricted(requestURL)
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
      // Nothing was fetched for this one; say so, since "did the cache decide
      // this?" is the first question when a page gets through it shouldn't.
      ScoutActivityReporter.shared.record(
        decision, for: requestURL,
        source: decision.verdict == nil ? .none : .cache, isPrivate: tab.isPrivate)
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

    // Nothing is known about this site, so a check has to run: it fetches and
    // AI-analyses the page, which takes seconds. What happens during those
    // seconds is the one place a supervised phone and a self-supervised one
    // part ways.
    switch NavigationGuard.missBehaviour(supervised: ScoutSupervision.shared.isOn) {

    // Supervised: nothing renders until the verdict lands. Show that work
    // rather than freezing the tab — cancel, show the checking page, and hand
    // the site over only once it has been judged. Not rendering before a
    // verdict is the promise supervision is sold on, and it is not tradeable
    // for speed.
    case .wait:
      ScoutPages.beginCheck(requestURL)
      showScoutPage(for: requestURL, in: tab)

      Task { @MainActor [weak self, weak tab] in
        let decision = await services.guard_.decide(requestURL)
        Self.settle(decision, for: requestURL, in: tab)
        // Only act if the tab is still showing this site's checking page; if
        // the user has moved on, the recorded decision just waits in the cache.
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

    // Unsupervised: this person chose their own blocked categories, for
    // themselves. They get the page now, and lose it if the verdict is bad.
    case .renderOptimistically:
      // Captured now, synchronously, while the tab is certainly alive — not
      // read off `tab` when the verdict lands. A private tab's store dies with
      // the tab, and the tab can be gone by then: closed by the user, or
      // closed by supervision being switched on, which shuts every private tab
      // (`ScoutSupervision.supervisionDidBegin`). Reading it late would hand
      // the shred a nil store; with no store there is nothing to delete, which
      // is the right answer, and `shredOrigin` refuses to substitute the
      // default one for it.
      let dataStore = tab.configuration?.websiteDataStore

      Task { @MainActor [weak self, weak tab] in
        let decision = await services.guard_.decide(requestURL)
        Self.settle(decision, for: requestURL, in: tab)
        // Anything the checking page would have stopped is stopped here too.
        // `.warn` and `.block` are both stops; letting a warn through only on
        // this path would mean a suspicious site, or a failed check on a phone
        // set to ask, quietly stayed open because the answer happened to be
        // slow.
        guard decision.type != .allow else { return }

        // Swap the view — but only if the tab is still on this site. If the
        // user has already moved on, replacing what they went to next would
        // take back a page nobody judged.
        //
        // `baseDomain` is nil for an address literal, and two nils comparing
        // equal would match this tab against any other hostless URL.
        if let self, let tab, let site = requestURL.baseDomain,
          tab.visibleURL?.baseDomain == site
        {
          // Note: this pushes a history entry over the live page rather than
          // replacing it, so Back returns to the blocked address and the check
          // runs again. The waiting path can use `location.replace` because it
          // is scripting its own internal page; here the live page is the
          // site's, and a web origin cannot `location.replace` to
          // `internal://`. A cached block simply blocks again on the way back;
          // an `.unavailable` warn, which is never cached, is re-checked and
          // — per the gate below — deletes nothing either way.
          showScoutPage(for: requestURL, in: tab)
        }

        // Then shred, whatever the tab ended up showing. The page ran while
        // the check was in flight — it executed its scripts, set its cookies
        // and filled its storage — and all of that exists whether or not the
        // tab is still on it. Swapping the view does not undo any of it;
        // deleting it is what makes "taken back" mean something.
        //
        // The gate is narrower than the swap above, deliberately. Stopping is
        // right for any non-allow, but deleting someone's cookies, storage and
        // saved credentials is only right when something actually judged the
        // page. `resolveFailure(.closed)` returns a `.warn` with reason
        // `.unavailable` — a timeout or a lost signal on a phone set to "ask
        // when a check fails" — and nothing judged that page at all; the
        // interstitial then offers "Continue anyway", after which the user
        // would simply be logged out for no reason. Note the asymmetry is only
        // on this path: the waiting path never deletes anything on a warn
        // either, because there the page never ran.
        guard decision.type == .block, decision.reason != .unavailable,
          let dataStore
        else { return }

        // Twice, a beat apart. `showScoutPage` only *starts* a navigation;
        // nothing awaits its commit, and `dataRecords` → `removeData` is
        // itself read-then-delete — so a response still in flight can land
        // between the read and the delete and write a fresh entry for the site
        // just cleared (observed on williamhill.com, which came back in Manage
        // Website Data with a cache entry after a shred-then-swap ordering).
        // The swap-first ordering shrank that window; it did not close it. The
        // second pass is the same answer `TabManager.forgetDataDelayed` gives
        // to the same problem, and after it the tab is long since off the site
        // and has nothing left in flight.
        await services.shredOrigin(requestURL, in: dataStore)
        try? await Task.sleep(seconds: 2)
        await services.shredOrigin(requestURL, in: dataStore)
      }
      return .allow
    }
  }

  /// The bookkeeping a settled check does, whichever path it came down: the
  /// activity log, the record of what was stopped, the result the page handler
  /// will serve, and the mark in the URL bar.
  ///
  /// The notification is posted even when the user has moved on. It says a
  /// verdict was stored, which is true regardless of what is on screen, and
  /// the toolbar simply re-reads the site it is actually showing.
  private static func settle(_ decision: Scout.Decision, for url: URL, in tab: (any TabState)?) {
    ScoutActivityReporter.shared.record(
      decision, for: url, source: .service, isPrivate: tab?.isPrivate ?? false)
    if decision.type != .allow, let tab {
      note(decision, for: url, in: tab)
    }
    ScoutPages.record(decision, for: url)
    // The mark in the URL bar reads the stored verdict; tell it there is one.
    NotificationCenter.default.post(name: ScoutServices.verdictDidChange, object: nil)
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

  /// Navigations already re-issued to carry YouTube's Restricted Mode cookie.
  ///
  /// Bounded, and ordered oldest-first so the oldest goes when it is full. It
  /// exists only to stop a reload loop on the page being re-issued, which is a
  /// question about the last few navigations; kept as a plain set it grew for
  /// every distinct video watched in a tab and was never emptied.
  private var restrictedURLs: Set<URL> = []
  private var restrictedOrder: [URL] = []
  /// Far more than a loop needs, far less than a long watching session makes.
  private static let maxRestrictedURLs = 50

  private func noteRestricted(_ url: URL) {
    guard restrictedURLs.insert(url).inserted else { return }
    restrictedOrder.append(url)
    if restrictedOrder.count > Self.maxRestrictedURLs {
      restrictedURLs.remove(restrictedOrder.removeFirst())
    }
  }

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

