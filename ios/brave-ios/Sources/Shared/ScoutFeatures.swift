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
  /// "Report a Broken Site" files the report with Brave's webcompat service.
  /// Gated in the page menu (`ShareActivity`) and the Shields panel.
  public static let webcompatReporter = false
  /// Brave Sync runs through Brave's sync servers. Gated in Settings, the
  /// synced-tabs Siri shortcut and the tab tray's synced-tabs panel.
  public static let sync = false
  /// P3A, the daily usage ping, crash reports and the survey panel all report
  /// to Brave. Their Settings toggles, the metrics onboarding step and its
  /// callout are gated (the prefs themselves default to off).
  public static let braveTelemetry = false
  /// Brave Search's promotion card in the URL bar's suggestions.
  public static let braveSearchPromotion = false
  /// Whether this build carries Apple's managed `com.apple.developer.web-browser`
  /// entitlement. Without it Scout cannot appear in Settings → Default Apps, so
  /// the browser doesn't ask to be made default. Turn on together with the
  /// entitlement in `App/iOS/Entitlements` once Apple grants the request.
  public static let defaultBrowserEntitlement = false
}

/// Where Scout users reach Zaatar Tech.
public enum ScoutContact {
  /// Scout's public site, hosted on Fly until the zaatar-site Worker can serve
  /// scout.zaatar.tech. These are also the App Store Connect URLs (support,
  /// privacy policy, marketing), so the in-app links match the listing.
  public static let site = URL(string: "https://zaatar-scout.fly.dev/")!
  /// The support page (it also carries the contact email).
  public static let supportURL = site.appending(path: "support")
  public static let privacyURL = site.appending(path: "privacy")
  public static let termsURL = site.appending(path: "terms")

  /// Scout's own public pages: never put through the safety check.
  public static let ownHosts = ["zaatar-scout.fly.dev", "scout.zaatar.tech"]
}
