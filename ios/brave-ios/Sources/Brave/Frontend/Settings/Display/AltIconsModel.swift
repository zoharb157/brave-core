// Copyright (c) 2024 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import UIKit

struct AltIcon: Identifiable {
  var assetName: String
  var displayName: String

  var id: String {
    assetName
  }

  /// Brave's alternate icons were all variants of the Brave lion; Scout ships
  /// none (the "Change App Icon" row is gated by `ScoutFeatures.alternateAppIcons`).
  static let allBraveIcons: [AltIcon] = []
}

class AltIconsModel: ObservableObject {
  @Published private(set) var selectedAltAppIcon: String?

  init() {
    self.selectedAltAppIcon = UIApplication.shared.alternateIconName
  }

  func setAlternateAppIcon(_ icon: AltIcon?, completion: ((Error?) -> Void)?) {
    if icon?.assetName == selectedAltAppIcon {
      // Nothing to do
      completion?(nil)
      return
    }
    UIApplication.shared.setAlternateIconName(icon?.assetName) { error in
      if error == nil {
        self.selectedAltAppIcon = icon?.assetName
      }
      completion?(error)
    }
  }
}
