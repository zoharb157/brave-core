// Copyright (c) 2025 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveUI
import DesignSystem
import SwiftUI

/// A View that renders what is basically the Brave app icon
struct BraveAppIcon: View {
  struct MatchedGeometryInfo {
    var namespace: Namespace.ID
    var isSource: Bool = true
  }

  var size: CGFloat
  var matchedGeometryInfo: MatchedGeometryInfo?
  /// Whether to draw the rounded plate and its shadow behind the mark.
  ///
  /// On the illustrations it must: those are pictures of a home screen, and
  /// an icon there sits on a tile. At the top of an onboarding page it must
  /// not — the mark is the app introducing itself, not a screenshot of it,
  /// and the plate read as a sticker pasted onto the page. Scout's mark is a
  /// circle, so the plate was also the only square thing on the screen.
  var showsTile: Bool = true

  var body: some View {
    Image(sharedName: "brave.logo")
      .resizable()
      .padding(showsTile ? (size * 0.02).rounded() : 0)
      .background {
        if showsTile {
          RoundedRectangle(cornerRadius: size / 4.44, style: .continuous)
            .fill(
              Color(braveSystemName: .containerBackground)
                .shadow(.drop(color: Color(braveSystemName: .elevationSecondary), radius: 4, y: 8))
                .shadow(.drop(color: Color(braveSystemName: .elevationPrimary), radius: 0, y: 1))
            )
        }
      }
      .matchedGeometryEffect(
        id: "logo",
        in: matchedGeometryInfo?.namespace ?? Namespace().wrappedValue,
        isSource: matchedGeometryInfo?.isSource ?? true
      )
      .frame(width: size, height: size)
  }
}
