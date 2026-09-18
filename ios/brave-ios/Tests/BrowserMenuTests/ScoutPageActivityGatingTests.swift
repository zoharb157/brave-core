// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest

@testable import BrowserMenu

/// Two menu rows shipped for features this build does not have: "Report a
/// Broken Site" and "Send To Your Devices". Both sat greyed out on every page,
/// looking like something that would work somewhere else.
///
/// The gates themselves were sound — no report was ever filed with Brave — so
/// what this guards is narrower than "the feature is unreachable", which is not
/// something a unit test can prove about a Chromium fork. It guards the one
/// place that shipped the bug: the registry the menu builds disabled rows from.
final class ScoutPageActivityGatingTests: XCTestCase {

  private typealias Availability = Action.Identifier.PageActivityAvailability

  private static let allOff = Availability(
    webcompatReporter: false, sync: false, braveNews: false)
  private static let allOn = Availability(
    webcompatReporter: true, sync: true, braveNews: true)

  /// The assertion that actually catches the shipped bug.
  ///
  /// An earlier version of this test only iterated the mapping, so deleting an
  /// entry from it made the loops shorter and everything still passed — a guard
  /// checking the entries that exist, against a failure mode of an entry not
  /// existing. This walks the registry instead: every activity the menu can
  /// build a row for must be claimed by something.
  func testEveryRegisteredActivityIsEitherUnconditionalOrOwnedByAFeature() {
    let owned = Set(Action.Identifier.switchablePageActivities.map(\.id))
    let unconditional = Action.Identifier.unconditionalPageActivities

    for id in Action.Identifier.allPageActivites {
      XCTAssertTrue(
        owned.contains(id) || unconditional.contains(id),
        "\(id.id) is a registered page activity that no feature owns and that is "
          + "not declared unconditional. If a feature owns it, add it to "
          + "switchablePageActivities so it is left out of builds without that "
          + "feature; if every build can do it, add it to "
          + "unconditionalPageActivities.")
    }
  }

  /// Nothing may be in both lists, which would make the classification a lie.
  func testNoActivityIsBothOwnedAndUnconditional() {
    let owned = Set(Action.Identifier.switchablePageActivities.map(\.id))
    let both = owned.intersection(Action.Identifier.unconditionalPageActivities)
    XCTAssertTrue(both.isEmpty, "claimed by a feature and declared unconditional: \(both.map(\.id))")
  }

  /// A mapping entry naming an activity the menu never registers would be dead
  /// weight that still reads as protection.
  func testEverySwitchableActivityIsOneTheMenuActuallyRegisters() {
    for entry in Action.Identifier.switchablePageActivities {
      XCTAssertTrue(
        Action.Identifier.allPageActivites.contains(entry.id),
        "\(entry.id.id) is mapped to a feature but is not a registered page activity")
    }
  }

  /// Scout's own configuration: all three off, so none may be registered.
  func testNothingSwitchedOffIsLeftInTheMenu() {
    let excluded = Action.Identifier.pageActivitiesNotOffered(Self.allOff)
    for entry in Action.Identifier.switchablePageActivities {
      XCTAssertTrue(
        excluded.contains(entry.id),
        "\(entry.id.id) belongs to a feature that is off and would render as a "
          + "permanently disabled row")
    }
  }

  /// The other direction, so the exclusion list cannot rot into hiding things
  /// the build can actually do.
  func testNothingSwitchedOnIsExcluded() {
    XCTAssertTrue(Action.Identifier.pageActivitiesNotOffered(Self.allOn).isEmpty)
  }

  /// The specific regression: turning webcompat back on must put the row back,
  /// and must not take the others with it.
  func testTurningOneFeatureOnAffectsOnlyItsOwnActivity() {
    let onlyWebcompat = Availability(webcompatReporter: true, sync: false, braveNews: false)
    let excluded = Action.Identifier.pageActivitiesNotOffered(onlyWebcompat)

    XCTAssertFalse(excluded.contains(.reportBrokenSite))
    XCTAssertTrue(excluded.contains(.sendURL))
    XCTAssertTrue(excluded.contains(.addSourceNews))
  }
}
