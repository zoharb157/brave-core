// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Onboarding
import Preferences
import Scout

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

  /// Lists, scheme rules and fail mode (server-synced later).
  public let policy: PolicyStore
  /// What the guard decides with: `policy`, but with blocked categories read
  /// live from the user's choice (onboarding / Settings → Blocked Content).
  public let decisionPolicy: PolicyProviding
  private let cache: VerdictCache
  private let checker: SafetyChecker
  public let guard_: NavigationGuard

  private init() {
    policy = PolicyStore(policy: .makeDefault())
    decisionPolicy = UserCategoryPolicy(
      base: policy, blockedCategories: { Preferences.ScoutBlocking.chosen })
    cache = VerdictCache(maxEntries: 2000, now: { Date() })
    checker = CoalescingSafetyChecker(
      transport: NetworkSafetyTransport(endpoint: Self.checkEndpoint))
    guard_ = NavigationGuard(
      policy: decisionPolicy, cache: cache, checker: checker, timeout: Self.checkTimeout)
  }
}
