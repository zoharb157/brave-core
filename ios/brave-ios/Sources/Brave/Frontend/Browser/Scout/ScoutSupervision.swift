// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import Scout
import Strings
import UIKit

/// Whether a parent is watching this phone, and the PIN that goes with it.
///
/// Supervision is turned on *from the phone being supervised*, never remotely.
/// A parent gets a read-only link and a way to lose it; they get no way to
/// reach in. That asymmetry is the whole design: the lever that ends a watch
/// belongs to the phone.
@MainActor
public final class ScoutSupervision: ObservableObject {
  public static let shared = ScoutSupervision()

  private static let pinKey = "supervision-pin"
  private static let host = "https://many-apps-30-day-challenge.fly.dev/api/kid-safe"
  /// Where a parent types the code. Shown on the phone so it can be read out.
  public static let watchURL = "many-apps-30-day-challenge.fly.dev/api/kid-safe/watch"

  private let session: URLSession

  private init(session: URLSession = .shared) {
    self.session = session
  }

  public var isOn: Bool { Preferences.Scout.supervised.value }

  /// Whether `pin` is the one set when supervision was turned on.
  ///
  /// Compared in full every time rather than bailing on the first wrong digit —
  /// four characters is not worth leaking a timing signal over, and the
  /// constant-time habit is cheaper to keep than to remember to apply.
  public func verify(pin: String) -> Bool {
    guard let stored = ScoutCredentials.string(forKey: Self.pinKey),
      stored.utf8.count == pin.utf8.count
    else { return false }
    var difference: UInt8 = 0
    for (a, b) in zip(stored.utf8, pin.utf8) { difference |= a ^ b }
    return difference == 0
  }

  /// Whether this action should ask for the PIN right now.
  public func needsPIN(_ action: SupervisedAction) -> Bool {
    SupervisionGate.needsPIN(action, whenSupervised: isOn)
  }

  public func turnOn(pin: String) {
    ScoutCredentials.set(pin, forKey: Self.pinKey)
    Preferences.Scout.supervised.value = true
    objectWillChange.send()
    // Private tabs stop being offered from here on, so any already open would
    // otherwise sit there unreachable by the control that made them.
    NotificationCenter.default.post(name: Self.supervisionDidBegin, object: nil)
  }

  /// Posted when supervision starts, so open private tabs can be closed.
  public static let supervisionDidBegin = Notification.Name("scout.supervision-did-begin")

  /// Ends supervision, and every watch with it.
  ///
  /// Sharing stops first: a link that outlived the supervision that created it
  /// would be the one thing here nobody could take back.
  public func turnOff() async {
    await stopSharing()
    ScoutCredentials.set(nil, forKey: Self.pinKey)
    Preferences.Scout.supervised.value = false
    objectWillChange.send()
  }

  /// A fresh code for a parent to type, or nil if the phone can't reach Scout.
  public func pairingCode() async -> String? {
    guard let token = await ScoutActivityReporter.shared.deviceToken() else { return nil }
    guard let body = try? JSONSerialization.data(withJSONObject: ["deviceToken": token]),
      let object = await post("supervision/code", body: body),
      let code = object["code"] as? String
    else { return nil }
    return code
  }

  /// Revokes every link a parent holds for this phone, at once.
  public func stopSharing() async {
    guard let token = await ScoutActivityReporter.shared.deviceToken(),
      let body = try? JSONSerialization.data(withJSONObject: ["deviceToken": token])
    else { return }
    _ = await post("supervision/revoke", body: body)
  }

  private func post(_ path: String, body: Data) async -> [String: Any]? {
    guard let url = URL(string: "\(Self.host)/\(path)") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    guard let (data, response) = try? await session.data(for: request),
      let http = response as? HTTPURLResponse, http.statusCode == 200
    else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  /// The controller actually on screen, starting from `presenter`.
  ///
  /// Settings and the menu are presented on top of the browser, so the
  /// controller a caller has to hand is often not the one in front. Presenting
  /// on a covered controller does nothing at all — no alert, no error — which
  /// is how a gate can look like it is not firing when it is.
  private static func topmost(from presenter: UIViewController?) -> UIViewController? {
    var current = presenter
    while let next = current?.presentedViewController, !next.isBeingDismissed {
      current = next
    }
    return current
  }

  /// Asks for the PIN if this action needs one, then runs `perform`.
  ///
  /// Nothing happens on a wrong PIN or a cancel — deliberately silent rather
  /// than scolding, because the person who does not know it is not the person
  /// this is protecting.
  public func gate(
    _ action: SupervisedAction,
    from presenter: UIViewController?,
    perform: @escaping () -> Void
  ) {
    guard needsPIN(action) else {
      perform()
      return
    }
    guard let presenter = Self.topmost(from: presenter) else { return }
    let alert = UIAlertController(
      title: Strings.ScoutProtection.supervisionEnterPIN,
      message: nil,
      preferredStyle: .alert
    )
    alert.addTextField { field in
      field.isSecureTextEntry = true
      field.keyboardType = .numberPad
      field.textContentType = .oneTimeCode
    }
    alert.addAction(UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel))
    alert.addAction(
      UIAlertAction(title: Strings.done, style: .default) { [weak alert] _ in
        guard let entered = alert?.textFields?.first?.text, self.verify(pin: entered) else { return }
        perform()
      }
    )
    presenter.present(alert, animated: true)
  }
}
