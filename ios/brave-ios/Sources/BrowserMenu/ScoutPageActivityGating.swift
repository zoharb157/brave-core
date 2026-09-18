// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Which page activities belong to a feature Scout can switch off, and the one
/// rule for leaving them out of the menu.
///
/// The menu renders any registered page activity that nothing supplied as a
/// disabled row. That is right for an action this page cannot do — Print on a
/// blank tab, which becomes available once something loads — and wrong for a
/// feature the build does not have, which can never become available at all.
/// Two such rows shipped: "Report a Broken Site" and "Send To Your Devices".
///
/// Availability is passed in rather than read here. `BrowserMenu` has no
/// dependency on the module that declares Scout's feature flags, and giving it
/// one to answer a question the caller already knows the answer to would be the
/// wrong direction. The caller owns which features exist; this owns the rule.
extension Action.Identifier {

  /// Whether each switchable feature is on in this build.
  public struct PageActivityAvailability: Sendable {
    public var webcompatReporter: Bool
    public var sync: Bool
    public var braveNews: Bool

    public init(webcompatReporter: Bool, sync: Bool, braveNews: Bool) {
      self.webcompatReporter = webcompatReporter
      self.sync = sync
      self.braveNews = braveNews
    }
  }

  /// Every page activity that a feature owns, paired with the flag that owns it.
  ///
  /// Hand-written, and that is the point: adding an entry here is how someone
  /// adding a page activity for a switchable feature is made to say which
  /// feature it belongs to, rather than having it appear in the menu of a build
  /// that cannot perform it.
  public static let switchablePageActivities:
    [(id: Action.Identifier, isOn: @Sendable (PageActivityAvailability) -> Bool)] = [
      // Files the report with Brave's webcompat service.
      (.reportBrokenSite, { $0.webcompatReporter }),
      // Needs Brave Sync to have somewhere to send the tab.
      (.sendURL, { $0.sync }),
      // Adds the site as a Brave News source.
      (.addSourceNews, { $0.braveNews }),
    ]

  /// Page activities no feature owns: every build can do these, so a disabled
  /// row for one only ever means "not on this page yet".
  ///
  /// Listed rather than inferred, because the guard's whole job is to notice a
  /// registered activity that belongs to neither list. Inferring this one as
  /// "everything without an owner" would make that impossible to detect.
  public static let unconditionalPageActivities: Set<Action.Identifier> = [
    .copyCleanLink,
    .toggleReaderMode,
    .translate,
    .findInPage,
    .pageZoom,
    .addFavourites,
    .requestDesktopSite,
    .createPDF,
    .addSearchEngine,
    .displaySecurityCertificate,
  ]

  /// The activities to leave out of the menu entirely, given what this build has.
  public static func pageActivitiesNotOffered(
    _ availability: PageActivityAvailability
  ) -> Set<Action.Identifier> {
    Set(switchablePageActivities.compactMap { $0.isOn(availability) ? nil : $0.id })
  }
}
