// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
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

  /// The same backend the Kid Safe app uses. It returns content categories
  /// today; the `security` field is pending backend work, and `Verdict.parse`
  /// defaults it to `.safe` when absent.
  private static let checkEndpoint = URL(
    string: "https://many-apps-30-day-challenge.fly.dev/api/kid-safe/check")!

  /// Phase 1 budget. On-device policy and cache decide most navigations with no
  /// network at all; only an unknown host waits, and never longer than this.
  private static let checkTimeout: TimeInterval = 0.4

  public let policy: PolicyStore
  private let cache: VerdictCache
  private let checker: SafetyChecker
  public let guard_: NavigationGuard

  private init() {
    policy = PolicyStore(policy: .makeDefault())
    cache = VerdictCache(maxEntries: 2000, now: { Date() })
    checker = CoalescingSafetyChecker(
      transport: NetworkSafetyTransport(endpoint: Self.checkEndpoint))
    guard_ = NavigationGuard(
      policy: policy, cache: cache, checker: checker, timeout: Self.checkTimeout)
  }

  /// Replaces the active policy (onboarding and settings call this).
  public func apply(blockedCategories: Set<ContentCategory>) {
    var updated = Policy.makeDefault()
    updated.blockedCategories = blockedCategories
    policy.setPolicy(updated)
  }
}
