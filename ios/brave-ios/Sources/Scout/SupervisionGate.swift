// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Something a person can do that changes how much protection is left.
public enum SupervisedAction: CaseIterable, Sendable {
  /// Turning a blocked category off.
  case relaxCategory
  /// Turning one on. Listed so the gate can say plainly that it is free.
  case tightenCategory
  /// Adding a site to the always-allow list.
  case allowSite
  /// Adding one to the always-block list.
  case blockSite
  /// "Always allow this site" on a block page.
  case alwaysAllowFromBlockPage
  case turnSupervisionOff
  /// "Continue anyway" on a block page — this visit only.
  case continueOnce
}

/// Which actions a supervised phone asks for the PIN before doing.
///
/// Only the ones that leave less protection than before. Two deliberate
/// omissions:
///
/// - `continueOnce` lasts one visit and is already recorded. Gating it makes
///   the browser unusable, and an unusable filter is one that gets switched
///   off altogether.
/// - `tightenCategory` and `blockSite` only ever add protection. A PIN there
///   is friction with nothing behind it.
public enum SupervisionGate {
  public static func needsPIN(_ action: SupervisedAction, whenSupervised supervised: Bool) -> Bool {
    guard supervised else { return false }
    switch action {
    case .relaxCategory, .allowSite, .alwaysAllowFromBlockPage, .turnSupervisionOff:
      return true
    case .tightenCategory, .blockSite, .continueOnce:
      return false
    }
  }
}
