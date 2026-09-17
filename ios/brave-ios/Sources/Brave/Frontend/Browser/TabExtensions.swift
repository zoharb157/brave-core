// Copyright (c) 2025 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import Data
import FaviconModels
import Foundation
import OSLog
import Shared
import UIKit
import Web

extension TabState {
  var displayTitle: String {
    if let url = self.visibleURL, url.isNewTabURL {
      return Strings.Hotkey.newTabTitle
    }

    if let displayTabTitle = fetchDisplayTitle(using: visibleURL, title: title) {
      return displayTabTitle
    }

    if let url = self.visibleURL, !InternalURL.isValid(url: url),
      let shownUrl = url.displayURL?.absoluteString, isWebViewCreated
    {
      return shownUrl
    }

    guard let lastTitle = data.browserData?.lastTitle, !lastTitle.isEmpty,
      !Self.isInternalAddress(lastTitle)
    else {
      // FF uses url?.displayURL?.absoluteString ??  ""
      if let title = addressTitle {
        return title
      } else if let tab = SessionTab.from(tabId: id) {
        if tab.title.isEmpty {
          return Strings.Hotkey.newTabTitle
        }
        return tab.title
      }

      return ""
    }

    return lastTitle
  }

  /// The tab's address, as a title of last resort.
  ///
  /// An internal page — a Scout block or checking page, an error page — stands
  /// in for a site, and its own address means nothing to the person looking
  /// at the tab list. A restored tab that had not loaded yet was listed as
  /// `internal://local/scout?url=…`.
  private var addressTitle: String? {
    guard let url = visibleURL else { return nil }
    if InternalURL.isValid(url: url), let shown = url.displayURL {
      return shown.absoluteDisplayString
    }
    return url.absoluteString
  }

  /// Restoring a tab can store its internal address as its title.
  private static func isInternalAddress(_ title: String) -> Bool {
    URL(string: title).map { InternalURL.isValid(url: $0) } ?? false
  }

  /// This property is for fetching the actual URL for the Tab
  /// In private browsing the URL is in memory but this is not the case for normal mode
  /// For Normal  Mode Tab information is fetched using Tab ID from
  var fetchedURL: URL? {
    if isPrivate {
      if let url = visibleURL, url.isWebPage() {
        return url
      }
    } else {
      if let tabUrl = visibleURL, tabUrl.isWebPage() {
        return tabUrl
      } else if let fetchedTab = SessionTab.from(tabId: id), fetchedTab.url?.isWebPage() == true {
        return visibleURL
      }
    }

    return nil
  }

  func fetchDisplayTitle(using url: URL?, title: String?) -> String? {
    if let tabTitle = title, !tabTitle.isEmpty {
      var displayTitle = tabTitle

      // Checking host is "localhost" || host == "127.0.0.1"
      // or hostless URL (iOS forwards hostless URLs (e.g., http://:6571) to localhost.)
      // DisplayURL will retrieve original URL even it is redirected to Error Page
      if let isLocal = url?.displayURL?.isLocal, isLocal {
        displayTitle = ""
      }

      return displayTitle
    }

    return nil
  }

  func hideContent(_ animated: Bool = false) {
    view.isUserInteractionEnabled = false
    if animated {
      UIView.animate(
        withDuration: 0.25,
        animations: { () -> Void in
          self.view.alpha = 0.0
        }
      )
    } else {
      view.alpha = 0.0
    }
  }

  func showContent(_ animated: Bool = false) {
    view.isUserInteractionEnabled = true
    if animated {
      UIView.animate(
        withDuration: 0.25,
        animations: { () -> Void in
          self.view.alpha = 1.0
        }
      )
    } else {
      view.alpha = 1.0
    }
  }

  var containsWebPage: Bool {
    if let url = visibleURL {
      return url.isWebPage()
    }

    return false
  }
}

extension SecureContentState {
  public var shouldDisplayWarning: Bool {
    switch self {
    case .unknown, .invalidCertificate, .missingSSL, .mixedContent:
      return true
    case .localhost, .secure:
      return false
    }
  }
}
