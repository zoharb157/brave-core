// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Brave features Scout does not ship.
///
/// On iOS these cannot be removed at build time: `is_brave_origin_branded`
/// asserts `!is_ios`, and the feature targets are hard dependencies of the iOS
/// framework. So each is hidden at the one availability check every UI entry
/// point already consults. Lives in `Shared` because every feature module
/// that owns such a check imports it.
public enum ScoutFeatures {
  /// Gated in `BraveRewards.isSupported`.
  public static let rewards = false
  /// Gated via `BraveWalletAPI.isAllowedInScout`.
  public static let wallet = false
  /// Gated in `PrefService.isBraveTalkAvailable`.
  public static let braveTalk = false
  /// Gated in `PrefService.isBraveNewsAvailable`.
  public static let braveNews = false
  /// Gated in `PrefService.isBraveVPNAvailable`.
  public static let vpn = false
  /// Gated via `AIChatUtils.isEnabledInScout(for:)`.
  public static let aiChat = false
  /// Sponsored new-tab-page backgrounds (ads) — contrary to an ad-blocking
  /// browser. Gated in `Preferences.NewTabPage.backgroundMediaType`.
  public static let sponsoredImages = false
  /// Brave's alternate app icons are all variants of the Brave lion.
  /// Gated where Settings adds its "Change App Icon" row.
  public static let alternateAppIcons = false
}

/// Where Scout users reach Zaatar Tech — the public contact used across its apps.
public enum ScoutContact {
  public static let email = "inquiries@zaatar.tech"

  /// A pre-addressed bug-report email carrying the app version.
  public static func bugReportURL(appVersion: String) -> URL? {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = email
    components.queryItems = [
      URLQueryItem(name: "subject", value: "Scout bug report"),
      URLQueryItem(name: "body", value: "\n\n—\nScout \(appVersion)"),
    ]
    return components.url
  }
}
