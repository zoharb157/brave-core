// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Decides which navigation reports are the *same* attempt seen twice.
///
/// One thing a person does produces more than one navigation. Typing a bare
/// host gives `http://…`, the site answers with a redirect to `https://…`, and
/// the browser asks about both. Each is a real decision — the first checked
/// against the service, the second answered from the cache a millisecond later
/// — but a log that prints both rows tells a parent their child opened the
/// page twice, which is not what happened.
///
/// So reports are keyed by what a person would call the same page — the
/// address without its scheme — and a repeat inside a short window is folded
/// into the one before it. The window is deliberately small: a minute later is
/// a second visit and says so.
public struct ActivityCoalescer: Sendable {
  /// How close two reports for the same page have to be to count as one.
  ///
  /// Long enough to cover a redirect chain and a person double-tapping a link;
  /// short enough that going back to a page still shows up as going back to it.
  public static let window: TimeInterval = 5

  private var last: (key: String, at: Date)?

  public init() {}

  /// Whether this report should be sent, given what came just before it.
  ///
  /// Calling this records the report as the new most recent one when it is
  /// accepted, so it is not a pure query — ask once per report.
  public mutating func shouldReport(url: URL, decision: DecisionType, at now: Date = Date()) -> Bool
  {
    let key = "\(decision)|\(Self.pageKey(url))"
    if let last, last.key == key, now.timeIntervalSince(last.at) < Self.window,
      now >= last.at
    {
      return false
    }
    last = (key, now)
    return true
  }

  /// The address as a person would recognise it: no scheme, no `www.`, no
  /// trailing slash.
  ///
  /// The scheme is dropped because an http→https upgrade is the same page, and
  /// the trailing slash because `example.com` and `example.com/` are too.
  ///
  /// `www.` goes for the same reason, and it was missing: typing a bare host
  /// and being redirected to the canonical one is one attempt, and it logged
  /// as two. Worse, the log shows the registrable domain, so both rows read
  /// identically — a parent saw their child trying a blocked site twice when
  /// they had tried it once. Only the leading label is dropped;
  /// `wwwexample.com` is a different site.
  static func pageKey(_ url: URL) -> String {
    var text = url.absoluteString
    for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
      text.removeFirst(scheme.count)
      break
    }
    if text.hasPrefix("www.") { text.removeFirst(4) }
    if text.hasSuffix("/") { text.removeLast() }
    return text.lowercased()
  }
}
