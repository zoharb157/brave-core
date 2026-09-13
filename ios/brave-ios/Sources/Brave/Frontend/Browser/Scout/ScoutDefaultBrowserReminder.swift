// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Onboarding
import Preferences
import Shared
import UIKit

/// Keeps asking until Scout is the default browser.
///
/// The guard only sees a link when the system hands it over, so a Scout that
/// isn't the default checks whatever the child opens *inside* Scout and nothing
/// else — the protection a parent thinks they installed is simply off. iOS
/// gives no way to set the default from code, and an app can't refuse to run;
/// what it can do is ask again every time it comes forward, and keep asking
/// until the system says Scout is the default.
@MainActor
enum ScoutDefaultBrowserReminder {
  /// Don't re-ask within this long of the last ask, so that flicking between
  /// apps doesn't produce a wall of prompts.
  static let minimumGap: TimeInterval = 15 * 60

  /// Whether the prompt can lead anywhere. Until Apple grants the managed
  /// `com.apple.developer.web-browser` entitlement, Scout isn't listed in
  /// Settings → Default Apps at all, so asking would send the user to a screen
  /// they can't act on. Flip this on with the entitlement (see
  /// `App/iOS/Entitlements`).
  static var canBecomeDefaultBrowser: Bool { ScoutFeatures.defaultBrowserEntitlement }

  static func shouldAsk(status: DefaultBrowserHelper.Status, now: Date = .now) -> Bool {
    guard canBecomeDefaultBrowser else { return false }
    switch status {
    case .defaulted, .likely:
      // `likely` means a link was handed to Scout recently, which only happens
      // when it is the default.
      return false
    case .notDefaulted, .unknown:
      break
    }
    guard let asked = Preferences.Scout.lastDefaultBrowserPrompt.value else { return true }
    return now.timeIntervalSince(asked) >= minimumGap
  }
}

extension Preferences {
  public final class Scout {
    /// When the default-browser prompt was last shown.
    static let lastDefaultBrowserPrompt = Option<Date?>(
      key: "scout.last-default-browser-prompt",
      default: nil
    )
  }
}
