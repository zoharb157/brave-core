// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import Foundation

/// Brave features Scout does not ship.
///
/// On iOS these cannot be removed at build time: `is_brave_origin_branded`
/// asserts `!is_ios`, and `enable_brave_rewards` / `enable_brave_wallet` are
/// hard dependencies of the iOS framework targets. They are hidden here
/// instead, at the choke points every UI entry already goes through.
enum ScoutFeatures {
  /// Rewards: toolbar BAT button, panel, onboarding, settings row, NTP widget.
  /// Gated inside `BraveRewards.isSupported`, which every entry point checks.
  static let rewards = false

  /// Wallet: menu item, settings row, URL-bar button, web3 provider
  /// injection, dapp prompts, web3 name resolution, widget shortcut.
  /// Gated via `BraveWalletAPI.isAllowedInScout`.
  static let wallet = false
}

extension BraveWalletAPI {
  /// Use instead of `isAllowed` at every wallet UI entry point.
  var isAllowedInScout: Bool {
    ScoutFeatures.wallet && isAllowed
  }
}
