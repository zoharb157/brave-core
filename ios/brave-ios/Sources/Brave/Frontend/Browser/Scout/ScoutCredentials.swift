// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Security

/// Scout's secrets, kept in the keychain rather than app-group defaults.
///
/// The device token is what this phone presents to read its own activity. It
/// lives here and not in Preferences because a plist is readable from a device
/// backup, and this one value stands between a stranger and a browsing record.
/// The install id used to be that value; it no longer is.
public enum ScoutCredentials {
  private static let service = "com.zaatar.scout.credentials"

  public static func string(forKey key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
      let data = out as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Writes, or clears when `value` is nil. Replaces rather than updates: one
  /// item per key, and no stale copy left behind if the key already existed.
  public static func set(_ value: String?, forKey key: String) {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(base as CFDictionary)
    guard let value, let data = value.data(using: .utf8) else { return }
    var add = base
    add[kSecValueData as String] = data
    // After first unlock so a background flush can still read it, and this
    // device only so a backup restored onto another phone carries no
    // credential for the first phone's browsing record.
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(add as CFDictionary, nil)
  }
}
