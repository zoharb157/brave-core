// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import UIKit

/// Scout's palette.
///
/// It lives here, in the design system, rather than beside the screens that
/// use it. These values had been written out by hand in three targets — the
/// accent alone four times — and every copy is a chance for one screen to
/// drift from the rest.
///
/// They are not Nala tokens. Those ship as a prebuilt xcframework generated
/// from Brave's Figma, so nothing in this repository can retint one, which is
/// why the primary button stayed Brave's blurple long after everything around
/// it had become Scout's. Anything Scout needs to control lives here instead.
extension Color {
  /// The brand colour: the app icon's ground, every primary action, and the
  /// status card.
  public static let scoutAccent = Color(red: 0x54 / 255, green: 0x40 / 255, blue: 0x96 / 255)
  /// The lighter violet the icon's gradient starts from.
  public static let scoutAccentLight = Color(red: 0x85 / 255, green: 0x70 / 255, blue: 0xD2 / 255)
  /// Checked and fine.
  public static let scoutMint = Color(red: 0x7E / 255, green: 0xC8 / 255, blue: 0xA8 / 255)
  /// Unfinished rather than wrong — a check that could not be completed, or a
  /// protection the user went around. Not a design-system orange: those are
  /// tuned to sit on a page background, not on the accent itself.
  public static let scoutAmber = Color(red: 0xF5 / 255, green: 0xC2 / 255, blue: 0x6B / 255)
  /// A block. The same rose the block page uses, so the page that stopped a
  /// site and the list recording it agree on sight.
  public static let scoutRose = Color(red: 0xB3 / 255, green: 0x62 / 255, blue: 0x6B / 255)
  /// The same rose lifted for dark, translucent surfaces — the new tab card
  /// floats on whatever wallpaper is behind it, while `scoutRose` is tuned to
  /// sit on a white list row.
  public static let scoutRoseOnDark = Color(red: 0xE0 / 255, green: 0x8F / 255, blue: 0x98 / 255)
}

extension UIColor {
  public static let scoutAccent = UIColor(
    red: 0x54 / 255, green: 0x40 / 255, blue: 0x96 / 255, alpha: 1)
}
