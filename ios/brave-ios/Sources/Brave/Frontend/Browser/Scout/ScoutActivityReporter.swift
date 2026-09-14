// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import Scout
import Shared
import UIKit

extension Preferences.Scout {
  /// An anonymous id for this installation of Scout.
  ///
  /// Not an account and not a device identifier: a random value made on first
  /// use, belonging to this install alone, and gone when the app is removed.
  /// It exists so the activity log can be read back for one phone rather than
  /// pooled across everyone.
  public static let installId = Preferences.Option<String>(
    key: "scout.install-id",
    default: ""
  )
}

/// Sends the browser's decisions to the activity log.
///
/// Every link Scout is asked to open produces one of these: what was asked
/// for, what happened, why, and whether the verdict behind it was already on
/// hand. That record is what lets a parent see what their child ran into, and
/// what lets a page that slipped through be traced back to the verdict that
/// allowed it.
///
/// It is strictly after the fact. Reporting is batched, never awaited by a
/// navigation, and a failure is dropped rather than retried forever — a log
/// must not be able to slow down or break the browsing it describes.
@MainActor
public final class ScoutActivityReporter {
  public static let shared = ScoutActivityReporter()

  private static let endpoint = URL(
    string: "https://many-apps-30-day-challenge.fly.dev/api/kid-safe/navigations")!
  /// Send once this many are waiting, so a burst of links doesn't sit unsent.
  private static let batchSize = 20
  /// …or once this long has passed, so the last few don't wait for a burst.
  private static let flushAfter: TimeInterval = 15
  /// The server takes 50 at a time; beyond this the oldest are dropped rather
  /// than allowed to grow without bound while offline.
  private static let maxPending = 200

  private var pending: [[String: Any]] = []
  private var flushTask: Task<Void, Never>?
  private let session: URLSession

  private init(session: URLSession = .shared) {
    self.session = session
    observeLifecycle()
  }

  /// This install's id, made on first use.
  public static var installId: String {
    let existing = Preferences.Scout.installId.value
    if !existing.isEmpty { return existing }
    let fresh = UUID().uuidString
    Preferences.Scout.installId.value = fresh
    return fresh
  }

  /// Records one decision.
  public func record(
    _ decision: Scout.Decision,
    for url: URL,
    source: VerdictSource,
    isPrivate: Bool,
    continued: Bool = false
  ) {
    var event: [String: Any] = [
      "installId": Self.installId,
      "url": String(url.absoluteString.prefix(2048)),
      "decision": Self.wire(decision.type),
      "reason": decision.reason.wire,
      "source": source.rawValue,
      "isPrivate": isPrivate,
      "continued": continued,
    ]
    if !decision.matchedCategories.isEmpty {
      event["categories"] = ContentCategory.wire(decision.matchedCategories)
    }
    enqueue(event)
  }

  /// Marks the most recent report for `url` as one the user went through.
  ///
  /// Sent as its own event rather than amending the last: by the time someone
  /// taps "continue" the original may already be on the server, and a log that
  /// rewrites its own history is worse than one with two rows.
  public func recordContinued(_ url: URL, isPrivate: Bool) {
    enqueue([
      "installId": Self.installId,
      "url": String(url.absoluteString.prefix(2048)),
      "decision": "allow",
      "reason": "policy-list",
      "source": "none",
      "isPrivate": isPrivate,
      "continued": true,
    ])
  }

  /// Where the verdict behind a decision came from.
  public enum VerdictSource: String {
    /// Already on hand — no request was made.
    case cache
    /// Fetched for this navigation.
    case service
    /// No verdict was involved: a rule, a scheme, or the address itself.
    case none
  }

  // MARK: - Sending

  private func enqueue(_ event: [String: Any]) {
    pending.append(event)
    if pending.count > Self.maxPending {
      pending.removeFirst(pending.count - Self.maxPending)
    }
    if pending.count >= Self.batchSize {
      flush()
    } else {
      scheduleFlush()
    }
  }

  private func scheduleFlush() {
    guard flushTask == nil else { return }
    flushTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(Self.flushAfter))
      self?.flushTask = nil
      self?.flush()
    }
  }

  public func flush() {
    flushTask?.cancel()
    flushTask = nil
    guard !pending.isEmpty else { return }
    let batch = Array(pending.prefix(50))
    pending.removeFirst(batch.count)

    guard
      let body = try? JSONSerialization.data(withJSONObject: ["events": batch])
    else { return }
    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    Task { [session] in
      // Dropped on failure, deliberately. A retry queue here would mean the
      // browser holding on to a list of everywhere it has been, which is
      // exactly what this should not become.
      _ = try? await session.data(for: request)
    }
  }

  private func observeLifecycle() {
    let center = NotificationCenter.default
    for name in [
      UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification,
    ] {
      center.addObserver(forName: name, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { ScoutActivityReporter.shared.flush() }
      }
    }
  }

  private static func wire(_ type: DecisionType) -> String {
    switch type {
    case .allow: return "allow"
    case .warn: return "warn"
    case .block: return "block"
    }
  }
}
