// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveShared
import Foundation
import Onboarding
import Preferences
import Scout
import Shared
import UIKit

/// Owns the guard's collaborators for the app.
///
/// One policy store and one verdict cache are shared across tabs, so a site
/// checked in one tab is instant in the next. The policy store is injected into
/// the guard as `PolicyProviding`, which is what lets a server-synced provider
/// replace it later without touching the guard.
@MainActor
public final class ScoutServices {
  public static let shared = ScoutServices()

  /// The same backend the Kid Safe app uses. It returns content categories and
  /// a `security` status; `Verdict.parse` still defaults a missing `security`
  /// to `.safe` so an older server cannot make the guard block everything.
  private static let checkEndpoint = URL(
    string: "https://many-apps-30-day-challenge.fly.dev/api/kid-safe/check")!

  /// The spec's budget is 400 ms, on the assumption that a precheck warms the
  /// cache before navigation. Precheck is not built yet, and the live service
  /// measures 2.7-10.2 s (it fetches and AI-analyses the page), so at 400 ms
  /// every unknown host times out and fails open — the guard would never block
  /// on a live verdict.
  ///
  /// Until precheck lands this is deliberately generous so the verdict actually
  /// arrives. It is NOT the shipping value: blocking a navigation for seconds is
  /// unacceptable UX, and the real fix is precheck plus the verdict cache.
  private static let checkTimeout: TimeInterval = 12.0

  /// Sites where the pages are written by whoever signs up, so one page's
  /// verdict says nothing about the next: a video, a subreddit or a free
  /// hosting subdomain is checked as a page, not as a site. Everywhere else a
  /// verdict covers the whole domain, which is what keeps browsing fast.
  static let perPageHosts: Set<String> = [
    // Social and user-posted content
    "reddit.com", "x.com", "twitter.com", "tumblr.com", "facebook.com", "instagram.com",
    "tiktok.com", "snapchat.com", "vk.com", "pinterest.com", "quora.com", "discord.com",
    "twitch.tv", "4chan.org", "deviantart.com", "imgur.com",
    // Video and story platforms
    "youtube.com", "youtu.be", "dailymotion.com", "vimeo.com", "wattpad.com",
    "archiveofourown.org", "fanfiction.net",
    // Publishing and free hosting: anyone can put a page under these
    "medium.com", "substack.com", "blogspot.com", "wordpress.com", "wixsite.com",
    "weebly.com", "github.io", "pages.dev", "netlify.app", "vercel.app", "glitch.me",
  ]

  /// Lists, scheme rules and fail mode (server-synced later).
  public let policy: PolicyStore
  /// What the guard decides with: `policy`, but with blocked categories read
  /// live from the user's choice (onboarding / Settings → Blocked Content).
  public let decisionPolicy: PolicyProviding
  private let cache: VerdictCache
  /// Sites first seen in a private tab. They stay in the in-memory cache for the
  /// session but are never written to disk — a private visit leaves no trace.
  private var privateOnlyKeys: Set<String> = []
  private let checker: SafetyChecker
  public let guard_: NavigationGuard

  private init() {
    var base = Policy.makeDefault()
    base.allow = ScoutContact.ownHosts
    policy = PolicyStore(policy: base)
    decisionPolicy = UserCategoryPolicy(
      base: policy, blockedCategories: { Preferences.ScoutBlocking.chosen })
    cache = VerdictCache(maxEntries: 2000, now: { Date() }, perPageHosts: Self.perPageHosts)
    checker = CoalescingSafetyChecker(
      transport: NetworkSafetyTransport(endpoint: Self.checkEndpoint),
      // Same key the cache uses, so two pages that are cached apart are also
      // checked apart rather than sharing one in-flight request.
      key: { VerdictCache.cacheKey(for: $0, perPageHosts: ScoutServices.perPageHosts) })
    guard_ = NavigationGuard(
      policy: decisionPolicy, cache: cache, checker: checker, timeout: Self.checkTimeout,
      // With no network the check can only time out, and the page is about to
      // fail to load anyway — don't spend the timeout on a checking screen.
      isReachable: { Reachability.shared.status.connectionType != .offline })

    load()
    observeLifecycle()
  }

  // MARK: - Keeping verdicts between launches

  /// Checking an unknown site takes seconds, so a cache that died with the app
  /// meant every site paid that price again on the next launch. Verdicts are
  /// re-derivable, so they live in Caches; they expire on their own (7 days
  /// safe, 24 hours otherwise) and are dropped when the user clears history.
  private static var storeURL: URL? {
    try? FileManager.default.url(
      for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent("scout-verdicts.json")
  }

  private func load() {
    guard let url = Self.storeURL, let data = try? Data(contentsOf: url) else { return }
    cache.deserialize(data)
  }

  public func save() {
    guard let url = Self.storeURL else { return }
    try? cache.serialize(excludingKeys: privateOnlyKeys).write(to: url, options: .atomic)
  }

  /// Called for every checked navigation in a private tab.
  public func notePrivateNavigation(to url: URL) {
    privateOnlyKeys.insert(VerdictCache.cacheKey(for: url, perPageHosts: Self.perPageHosts))
  }

  /// The cache keys are the sites the user visited, so clearing history clears
  /// them too.
  public func forgetVerdicts() {
    cache.removeAll()
    privateOnlyKeys.removeAll()
    if let url = Self.storeURL {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private func observeLifecycle() {
    let center = NotificationCenter.default
    for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
      center.addObserver(forName: name, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { ScoutServices.shared.save() }
      }
    }
    center.addObserver(forName: .privateDataClearedHistory, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated { ScoutServices.shared.forgetVerdicts() }
    }
  }
}
