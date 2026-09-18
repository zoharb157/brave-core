// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import Scout
import Shared
import Web

/// The guard for the web views that live outside the tab strip: a long-press
/// preview and Quick View.
///
/// Those tabs have no `ScoutTabHelper`, and cannot use one. It answers an
/// unknown site with Scout's own pages — a checking page, a block page — and
/// neither kind of tab can show them: a preview has no way to act on a button,
/// and Quick View sends every internal page off to a new tab, where the
/// checking page would wait for a hand-off that only the Quick View tab knew
/// to make.
///
/// So this one is stricter and simpler. It lets a page load only when Scout
/// already knows it may, without a check and without changing the address.
/// Anything else is stopped here, its check is started, and the owner decides
/// what to do with it: a preview shows nothing, and Quick View hands the load
/// to a real tab, which checks it properly.
///
/// Judging only the address the preview was opened for was not enough. The
/// page loads, redirects, and the redirect was never looked at, so a search
/// engine's click-through link previewed whatever it pointed at.
///
/// Policy deciders are held weakly by the tab, so the owner keeps this alive.
@MainActor
final class ScoutDetachedTabGate: TabPolicyDecider {
  /// Called with each load this gate stopped, and whether it came from a
  /// private tab.
  private let onStopped: ((URLRequest, Bool) -> Void)?
  /// For the engines someone added, which Scout cannot filter. Held the way
  /// `ScoutTabHelper` holds it, and from the same profile.
  private weak var searchEngines: SearchEngines?

  init(searchEngines: SearchEngines?, onStopped: ((URLRequest, Bool) -> Void)? = nil) {
    self.searchEngines = searchEngines
    self.onStopped = onStopped
  }

  func tab(
    _ tab: some TabState,
    shouldAllowRequest request: URLRequest,
    requestInfo: WebRequestInfo
  ) async -> WebPolicyDecision {
    guard let url = request.url, requestInfo.isMainFrame, InternalURL(url) == nil
    else { return .allow }

    // A scheme this does not understand is stopped, not waved through. It
    // read the other way round: anything that was not http, https, data, blob
    // or file skipped the gate entirely and loaded, which is the opposite of
    // what Scout decides for those elsewhere — `decideImmediately` blocks a
    // scheme no rule names. A preview or a Quick View is the last place to be
    // the lenient one, since neither can show a block page to say what
    // happened. Quick View hands it to a real tab, which handles it the way
    // the browser normally does.
    guard ["http", "https", "data", "blob", "file"].contains(url.scheme) else {
      onStopped?(request, tab.isPrivate)
      return .cancel
    }

    if Self.admits(url, isPrivate: tab.isPrivate, engines: searchEngines) {
      return .allow
    }
    onStopped?(request, tab.isPrivate)
    return .cancel
  }

  /// Whether `url` may load, as it is, in a tab Scout cannot hold on a
  /// checking page. If not, its check is started, so asking again once it has
  /// been allowed gets a yes.
  ///
  /// Only a known allow will do. A page that needs its address changed first
  /// — a search pinned to its safe mode, YouTube's Restricted Mode — is also a
  /// no: a real tab makes that change on the way in, and nothing here can.
  static func admits(_ url: URL, isPrivate: Bool, engines: SearchEngines?) -> Bool {
    let services = ScoutServices.shared
    if isPrivate {
      services.notePrivateNavigation(to: url)
    }
    if Preferences.Scout.safeSearch.value,
      SafeSearch.enforced(url) != nil || RestrictedMode.governs(url)
    {
      return false
    }
    // The engines the user added are named in `engines` and nowhere else, so
    // asking without them says "nothing here to filter" about exactly the
    // engines that cannot be filtered. An engine added before supervision
    // began would then render its unfiltered results inside a preview or a
    // Quick View, on a phone where the same results are blocked in a tab.
    if ScoutSearchFilter.block(for: url, engines: engines) != nil {
      return false
    }
    guard let decision = services.guard_.decideImmediately(url) else {
      services.warm(url, isPrivate: isPrivate)
      return false
    }
    if decision.isStale {
      Task { await services.refresh(url, isPrivate: isPrivate) }
    }
    return decision.type == .allow
  }
}
