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

  /// When the warm list was last asked about, so it is asked once a day and
  /// not once a navigation.
  public static let warmListCheckedAt = Preferences.Option<Double>(
    key: "scout.warm-list-checked-at", default: 0)

  /// The `builtAt` from the last "you're current" reply, in seconds since the
  /// epoch — the server's own timestamp, never this phone's clock.
  ///
  /// The list's entry set is hash-stable and moves slowly, so a phone that
  /// installs weeks after the build sends its bundled version, is told it is
  /// current, and is handed no new `builtAt` to age from. Held here, that
  /// reply re-asserts the list this phone already has; without it the list
  /// ages out for good and the daily refresh can never repair it.
  public static let warmListConfirmedCurrentAt = Preferences.Option<Double>(
    key: "scout.warm-list-confirmed-current-at", default: 0)

  /// How many links Scout has checked, and how many it stopped, for the life
  /// of this install.
  ///
  /// Kept as their own counters rather than read off the verdict cache and the
  /// block list. Those two are a purgeable cache and a capped list: the first
  /// empties whenever iOS reclaims disk, the second stops growing once it is
  /// full, so the card could say "0 sites checked, 2 blocked" — three numbers
  /// that look like one series and are not.
  public static let sitesChecked = Preferences.Option<Int>(key: "scout.tally.checked", default: 0)
  public static let sitesBlocked = Preferences.Option<Int>(key: "scout.tally.blocked", default: 0)
  /// Blocks the user chose to walk through. The Protection card showed the
  /// size of the standing allow list in this slot, which is a different thing
  /// and is nearly always zero — so the one figure that says protection was
  /// bypassed read zero however often it happened.
  public static let sitesContinued = Preferences.Option<Int>(key: "scout.tally.continued", default: 0)
  /// Wrong PINs in a row, and the wait the latest one earned. Kept here rather
  /// than in memory so force-quitting the app does not hand back a clean slate.
  public static let pinFailures = Preferences.Option<Int>(key: "scout.pin.failures", default: 0)
  /// The wait's length, and `PINThrottle.clock()` when it began. New keys
  /// rather than the old "locked-until" one: that held a date on the phone's
  /// own clock, and read as a clock reading it would mean something else.
  public static let pinLockSeconds = Preferences.Option<Double>(
    key: "scout.pin.lock-seconds", default: 0)
  public static let pinLockedAt = Preferences.Option<Double>(
    key: "scout.pin.locked-at-monotonic", default: 0)
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

  /// Stamps an event with the moment it happened, not the moment it is sent.
  private static let stamp: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private var pending: [[String: Any]] = []
  /// Folds a redirect chain back into the one attempt a person made.
  private var coalescer = ActivityCoalescer()
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
    // Typing a bare host loads `http://…`, the site redirects to `https://…`,
    // and both come through here — the first checked, the second answered from
    // the cache a moment later. That is one attempt, and the log says one.
    guard coalescer.shouldReport(url: url, decision: decision.type) else { return }
    // Counted here because this is the one place every decision passes through
    // after redirects have been folded together, so a single tap counts once.
    // A private tab is left out: the point of one is that the visit leaves no
    // trace, and a number that moves is a trace.
    if isPrivate {
      // Nothing about a private visit is reported. The supervision design
      // refused "log it and label it" in so many words — logging a private
      // visit is a worse answer than not offering privacy the product does
      // not intend to honour — and the report carried the whole URL, kept it
      // for thirty days, and showed it on the parent's page unlabelled.
      //
      // Supervised phones have no private tab, so this is about the other
      // case: browsing done privately while unsupervised, still sitting in
      // the log if supervision is turned on afterwards.
      return
    }
    Preferences.Scout.sitesChecked.value += 1
    if decision.type == .block { Preferences.Scout.sitesBlocked.value += 1 }
    var event: [String: Any] = [
      "url": String(url.absoluteString.prefix(2048)),
      "decision": Self.wire(decision.type),
      "reason": decision.reason.wire,
      "source": source.rawValue,
      "isPrivate": isPrivate,
      "continued": continued,
      // Reports are batched, so the server only knows when a batch arrived.
      // Without this every link in a burst reads as one instant and the log
      // cannot say what happened when.
      "at": Self.stamp.string(from: Date()),
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
    // Nothing leaves a private tab, the count included: the point of one is
    // that the visit leaves no trace, and a number that moves is a trace.
    guard !isPrivate else { return }
    Preferences.Scout.sitesContinued.value += 1
    enqueue([
      "url": String(url.absoluteString.prefix(2048)),
      "decision": "allow",
      "reason": "policy-list",
      "source": "none",
      "isPrivate": isPrivate,
      "continued": true,
      "at": Self.stamp.string(from: Date()),
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

  // MARK: - Reading it back

  /// One decision as it reads back from the log.
  public struct ActivityRecord: Identifiable, Sendable {
    public let id = UUID()
    public let url: String
    /// The site the verdict behind this was keyed under.
    public let site: String
    public let decision: DecisionType
    public let reason: DecisionReason
    public let source: VerdictSource
    public let categories: Set<ContentCategory>
    public let continued: Bool
    public let isPrivate: Bool
    public let date: Date
  }

  private static let readEndpoint = URL(
    string: "https://many-apps-30-day-challenge.fly.dev/api/kid-safe/navigations/read")!
  private static let mintEndpoint = URL(
    string: "https://many-apps-30-day-challenge.fly.dev/api/kid-safe/device-token")!
  private static let tokenKey = "device-token"
  /// The token the server last turned down, kept as proof this is the same
  /// phone when asking for the next one.
  private static let previousTokenKey = "device-token-previous"

  /// A mint in flight, so callers that need a token at once share one request.
  private var minting: Task<String?, Never>?

  /// This phone's credential for reading its own record, minted on first use.
  ///
  /// Kept in the keychain, not in the app group: the install id used to be the
  /// credential, and it sat in a plist that travels in a backup.
  public func deviceToken() async -> String? {
    if let existing = ScoutCredentials.string(forKey: Self.tokenKey) { return existing }
    if let minting { return await minting.value }
    let task = Task { await self.mint() }
    minting = task
    let token = await task.value
    minting = nil
    return token
  }

  /// Asks for a token, showing the last one when there is one.
  ///
  /// The server no longer mints on the install id alone for an install that
  /// already has a token — anyone could name the install. It answers 409
  /// instead, which for this phone means its own token is gone for good (a
  /// restore that left the keychain behind, say). The only way on is a new
  /// install id: the record under the old one stays unreadable, which is the
  /// point.
  private func mint() async -> String? {
    let previous = ScoutCredentials.string(forKey: Self.previousTokenKey)
    switch await requestToken(installId: Self.installId, currentToken: previous) {
    case .issued(let token):
      store(token)
      return token
    case .refused:
      Preferences.Scout.installId.value = UUID().uuidString
      guard case .issued(let token) = await requestToken(installId: Self.installId, currentToken: nil)
      else { return nil }
      store(token)
      return token
    case .failed:
      return nil
    }
  }

  private enum MintResult {
    case issued(String)
    case refused
    case failed
  }

  private func requestToken(installId: String, currentToken: String?) async -> MintResult {
    var request = URLRequest(url: Self.mintEndpoint)
    request.httpMethod = "POST"
    request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = ["installId": installId]
    if let currentToken { body["currentToken"] = currentToken }
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (data, response) = try? await session.data(for: request),
      let http = response as? HTTPURLResponse
    else { return .failed }
    if http.statusCode == 409 { return .refused }
    guard http.statusCode == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let token = object["token"] as? String
    else { return .failed }
    return .issued(token)
  }

  private func store(_ token: String) {
    ScoutCredentials.set(token, forKey: Self.tokenKey)
    ScoutCredentials.set(nil, forKey: Self.previousTokenKey)
  }

  /// Sets the stored token aside so the next call mints a fresh one.
  ///
  /// Tokens expire, and turning sharing off burns this phone's along with the
  /// parent's links. Neither is an error worth telling anyone about — the
  /// phone just asks again, showing this one as proof it is the same phone.
  public func forgetDeviceToken() {
    if let current = ScoutCredentials.string(forKey: Self.tokenKey) {
      ScoutCredentials.set(current, forKey: Self.previousTokenKey)
    }
    ScoutCredentials.set(nil, forKey: Self.tokenKey)
  }

  /// This install's recent activity, newest first.
  ///
  /// Anything still waiting to be sent is flushed first, so opening the screen
  /// right after browsing doesn't show a list that is missing the last minute
  /// of it.
  public func recentActivity(limit: Int = 200) async throws -> [ActivityRecord] {
    flush()
    var request = URLRequest(url: Self.readEndpoint)
    request.httpMethod = "POST"
    request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    guard let token = await deviceToken() else { throw URLError(.userAuthenticationRequired) }
    request.httpBody = try JSONSerialization.data(
      withJSONObject: ["deviceToken": token, "limit": limit])

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rows = object["records"] as? [[String: Any]]
    else { throw URLError(.cannotParseResponse) }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()

    return rows.compactMap { row -> ActivityRecord? in
      guard let url = row["url"] as? String,
        let decision = (row["decision"] as? String).flatMap(Self.decision(fromWire:)),
        let reason = (row["reason"] as? String).flatMap(DecisionReason.init(wire:)),
        let stamp = row["createdAt"] as? String
      else { return nil }
      let date = formatter.date(from: stamp) ?? plain.date(from: stamp)
      guard let date else { return nil }
      return ActivityRecord(
        url: url,
        site: row["key"] as? String ?? "",
        decision: decision,
        reason: reason,
        source: (row["source"] as? String).flatMap(VerdictSource.init(rawValue:)) ?? .none,
        categories: ContentCategory.set(fromWire: row["categories"] as? [String] ?? []),
        continued: row["continued"] as? Bool ?? false,
        isPrivate: row["isPrivate"] as? Bool ?? false,
        date: date)
    }
  }

  private static func decision(fromWire wire: String) -> DecisionType? {
    switch wire {
    case "allow": return .allow
    case "warn": return .warn
    case "block": return .block
    default: return nil
    }
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

    Task { [session] in
      // The token says whose record this is. The install id used to travel
      // with each event and be believed, which made the log writable by
      // anyone who could name an install.
      guard let token = await self.deviceToken(),
        let body = try? JSONSerialization.data(
          withJSONObject: [
            "deviceToken": token,
            "events": batch,
            // The parent's page shows each visit on this phone's clock. The
            // server runs in UTC and has no other way to know which day a
            // late-evening visit belongs to.
            "timeZone": TimeZone.current.identifier,
          ])
      else { return }
      var request = URLRequest(url: Self.endpoint)
      request.httpMethod = "POST"
      request.setValue("kid-safe", forHTTPHeaderField: "x-app-id")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body

      // Dropped on failure, deliberately. A retry queue here would mean the
      // browser holding on to a list of everywhere it has been, which is
      // exactly what this should not become.
      guard let (_, response) = try? await session.data(for: request) else { return }
      // A token can expire, or be burned by turning sharing off. Minting a
      // fresh one costs nothing and is what the phone would do on next launch
      // anyway; doing it here means one rejected batch rather than a log that
      // quietly stops for ninety days.
      if (response as? HTTPURLResponse)?.statusCode == 401 { await self.forgetDeviceToken() }
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
