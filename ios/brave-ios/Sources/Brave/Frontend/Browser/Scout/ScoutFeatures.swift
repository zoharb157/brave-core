// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import Foundation
import Shared

// Gates for the two hidden features whose availability check is Objective-C++
// and so cannot be edited in Swift. See `ScoutFeatures` in `Shared`.

extension BraveWalletAPI {
  /// Use instead of `isAllowed` at every wallet UI entry point.
  var isAllowedInScout: Bool {
    ScoutFeatures.wallet && isAllowed
  }
}

extension AIChatUtils {
  /// Use instead of `isAIChatEnabled(for:)` at every AI Chat (Leo) entry point.
  static func isEnabledInScout(for prefs: any PrefService) -> Bool {
    ScoutFeatures.aiChat && isAIChatEnabled(for: prefs)
  }
}
