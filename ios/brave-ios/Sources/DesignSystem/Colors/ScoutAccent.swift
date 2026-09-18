// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import UIKit

/// Scout's accent — the colour of the app icon, the status card and every
/// primary action.
///
/// It lives here, in the design system, rather than beside the screens that
/// use it. The same value had been written out four times in three targets,
/// each copy a chance for one screen to drift.
///
/// It is not a Nala token. Those ship as a prebuilt xcframework generated from
/// Brave's Figma, so `buttonBackground` cannot be retinted from this
/// repository — which is why the primary button stayed Brave's blurple long
/// after everything around it had become Scout's.
extension Color {
  public static let scoutAccent = Color(red: 0x54 / 255, green: 0x40 / 255, blue: 0x96 / 255)
}

extension UIColor {
  public static let scoutAccent = UIColor(
    red: 0x54 / 255, green: 0x40 / 255, blue: 0x96 / 255, alpha: 1)
}
