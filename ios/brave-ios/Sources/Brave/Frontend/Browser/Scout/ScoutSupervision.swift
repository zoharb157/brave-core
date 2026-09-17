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
  /// Seconds before another PIN may be tried, or zero.
  ///
  /// Persisted rather than held in memory: a count that a force-quit clears is
  /// no count at all, and force-quitting is the first thing anyone working
  /// through PINs would find.
  ///
  /// Measured on a clock the phone's user cannot set. It used to be a date on
  /// the phone's own clock, so moving the date forward in Settings ended the
  /// wait and every guess after the first five was free.
  public var pinWait: TimeInterval {
    PINThrottle.wait(Self.attempts, now: PINThrottle.clock())
  }

  private static var attempts: PINAttempts {
    get {
      PINAttempts(
        failures: Preferences.Scout.pinFailures.value,
        lockSeconds: Preferences.Scout.pinLockSeconds.value,
        lockedAt: Preferences.Scout.pinLockedAt.value)
    }
    set {
      Preferences.Scout.pinFailures.value = newValue.failures
      Preferences.Scout.pinLockSeconds.value = newValue.lockSeconds
      Preferences.Scout.pinLockedAt.value = newValue.lockedAt
    }
  }

  /// Checks a PIN, counting the attempt.
  ///
  /// Refuses outright while a wait is running, so the cost cannot be skipped
  /// by simply asking again — and the comparison is constant-time, so a wrong
  /// answer does not say how much of it was right.
  public func verify(pin: String) -> Bool {
    guard pinWait == 0 else { return false }
    guard let stored = ScoutCredentials.string(forKey: Self.pinKey),
      stored.utf8.count == pin.utf8.count
    else {
      Self.attempts = PINThrottle.afterFailure(Self.attempts, now: PINThrottle.clock())
      return false
    }
    var difference: UInt8 = 0
    for (a, b) in zip(stored.utf8, pin.utf8) { difference |= a ^ b }
    guard difference == 0 else {
      Self.attempts = PINThrottle.afterFailure(Self.attempts, now: PINThrottle.clock())
      return false
    }
    Self.attempts = PINThrottle.afterSuccess()
    return true
  }

  /// Whether this action should ask for the PIN right now.
  public func needsPIN(_ action: SupervisedAction) -> Bool {
    SupervisionGate.needsPIN(action, whenSupervised: isOn)
  }

  public func turnOn(pin: String) {
    ScoutCredentials.set(pin, forKey: Self.pinKey)
    Self.attempts = PINThrottle.afterSuccess()
    Preferences.Scout.supervised.value = true
    // "Private browsing only" would otherwise keep the whole browser in a
    // mode supervision does not offer.
    Preferences.Privacy.privateBrowsingOnly.value = false
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
  ///
  /// A token the server no longer knows is dropped and replaced once. Tokens
  /// expire, and a phone that kept asking with a dead one told the person it
  /// had no internet.
  public func pairingCode() async -> String? {
    for attempt in 0..<2 {
      guard let token = await ScoutActivityReporter.shared.deviceToken(),
        let body = try? JSONSerialization.data(withJSONObject: ["deviceToken": token])
      else { return nil }
      switch await post("supervision/code", body: body) {
      case .ok(let object):
        return object["code"] as? String
      case .unauthorized where attempt == 0:
        ScoutActivityReporter.shared.forgetDeviceToken()
      case .unauthorized, .failed:
        return nil
      }
    }
    return nil
  }

  /// Revokes every link a parent holds for this phone, at once.
  public func stopSharing() async {
    guard let token = await ScoutActivityReporter.shared.deviceToken(),
      let body = try? JSONSerialization.data(withJSONObject: ["deviceToken": token])
    else { return }
    // The server deletes this phone's token along with the parent's links.
    // Keeping it would make the next code request, and the next batch of
    // activity, fail on a token that no longer exists.
    if case .ok = await post("supervision/revoke", body: body) {
      ScoutActivityReporter.shared.forgetDeviceToken()
    }
  }

  private enum Reply {
    case ok([String: Any])
    case unauthorized
    case failed
  }

  private func post(_ path: String, body: Data) async -> Reply {
    guard let url = URL(string: "\(Self.host)/\(path)") else { return .failed }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    guard let (data, response) = try? await session.data(for: request),
      let http = response as? HTTPURLResponse
    else { return .failed }
    if http.statusCode == 401 { return .unauthorized }
    guard http.statusCode == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return .failed }
    return .ok(object)
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

  /// "5 minutes", "30 seconds" — enough to know whether to wait or put the
  /// phone down.
  private static func spell(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds < 60 ? [.second] : [.minute]
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 1
    return formatter.string(from: max(seconds, 1)) ?? "a moment"
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

    // Silence is right for a wrong PIN — the person who does not know it is
    // not the person this protects — but not for a locked one. There the
    // correct PIN fails too, and someone who knows it would be left tapping
    // Done at a prompt that does nothing and says nothing.
    let waiting = pinWait
    if waiting > 0 {
      let locked = UIAlertController(
        title: Strings.ScoutProtection.supervisionEnterPIN,
        message: String(
          format: Strings.ScoutProtection.supervisionPINWait, Self.spell(waiting)),
        preferredStyle: .alert
      )
      locked.addAction(UIAlertAction(title: Strings.OKString, style: .default))
      presenter.present(locked, animated: true)
      return
    }

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
