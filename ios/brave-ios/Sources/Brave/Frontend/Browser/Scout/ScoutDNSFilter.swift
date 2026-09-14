// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import NetworkExtension
import Preferences
import Shared

/// Filtering for the whole phone, not just what happens inside Scout.
///
/// Scout only sees the pages opened in Scout. Other apps open links in their
/// own in-app browsers, and a native app never touches a browser at all — so a
/// child's phone stays mostly unfiltered however good the browser is. iOS has
/// no way to route that traffic through an app, but it does let one app set the
/// phone's DNS resolver: every app then resolves names through a filtering
/// resolver, and the ones that serve adult content or malware never resolve.
///
/// This is name-level filtering, so it is coarse — it can refuse a site, not
/// judge a page — and it is a complement to the guard rather than a
/// replacement. Apps that ship their own hardcoded resolver bypass it.
@MainActor
public final class ScoutDNSFilter: ObservableObject {
  public static let shared = ScoutDNSFilter()

  public enum State: Equatable {
    /// No configuration installed.
    case off
    /// Installed, but iOS needs the user to allow it in Settings before it
    /// takes effect.
    case needsApproval
    /// Filtering the whole device.
    case on
    /// The system would not accept the configuration.
    case failed(String)
  }

  @Published public private(set) var state: State = .off

  /// Cloudflare's family resolver: blocks malware and adult content at the name
  /// level, free, no logging of personal data, and no service of our own to
  /// keep running. The verdict service still decides everything inside Scout;
  /// this is the floor under the rest of the phone.
  private static let serverURL = URL(string: "https://family.cloudflare-dns.com/dns-query")!
  private static let serverAddresses = ["1.1.1.3", "1.0.0.3", "2606:4700:4700::1113", "2606:4700:4700::1003"]

  private let manager = NEDNSSettingsManager.shared()

  public func refresh() async {
    do {
      try await manager.loadFromPreferences()
      if manager.dnsSettings == nil {
        state = .off
      } else {
        state = manager.isEnabled ? .on : .needsApproval
      }
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  /// Installs the configuration. iOS then asks the user to allow it — until
  /// they do, `state` stays `.needsApproval`.
  public func enable() async {
    do {
      try await manager.loadFromPreferences()
      let settings = NEDNSOverHTTPSSettings(servers: Self.serverAddresses)
      settings.serverURL = Self.serverURL
      manager.dnsSettings = settings
      manager.localizedDescription = "Scout"
      // No on-demand rules: the point is that it applies everywhere, always.
      manager.onDemandRules = nil
      try await manager.saveToPreferences()
      await refresh()
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  public func disable() async {
    do {
      try await manager.loadFromPreferences()
      try await manager.removeFromPreferences()
      state = .off
    } catch {
      state = .failed(error.localizedDescription)
    }
  }
}
