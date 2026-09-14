// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@_exported import Strings

/// Copy for Settings → Protection and the site panel behind the URL bar.
///
/// In `BraveStrings` rather than beside the views: that module owns the
/// `BraveShared` table, and its `Resources/*.lproj` are where the app's
/// translations live. A string declared in the `Brave` target has no `.lproj`
/// to resolve against, so it would ship English to all forty locales.
extension Strings {
  public struct ScoutProtection {
    public static let title = NSLocalizedString(
      "scoutProtection.title",
      tableName: "BraveShared",
      bundle: .module,
      value: "Protection",
      comment: "Settings row and screen title for everything Scout does to keep sites out"
    )
    public static let statusHeadline = NSLocalizedString(
      "scoutProtection.statusHeadline",
      tableName: "BraveShared",
      bundle: .module,
      value: "Scout is checking every site",
      comment: "Headline of the status card at the top of the Protection screen"
    )
    public static let statusNotDefault = NSLocalizedString(
      "scoutProtection.statusNotDefault",
      tableName: "BraveShared",
      bundle: .module,
      value: "Scout only checks links opened in Scout",
      comment: "Headline of the status card when Scout is not the default browser"
    )
    public static let statusChecked = NSLocalizedString(
      "scoutProtection.statusChecked",
      tableName: "BraveShared",
      bundle: .module,
      value: "Sites checked",
      comment: "Label under the count of sites Scout has a verdict for"
    )
    public static let statusBlocked = NSLocalizedString(
      "scoutProtection.statusBlocked",
      tableName: "BraveShared",
      bundle: .module,
      value: "Blocked",
      comment: "Label under the count of sites Scout has blocked recently"
    )
    public static let statusAllowed = NSLocalizedString(
      "scoutProtection.statusAllowed",
      tableName: "BraveShared",
      bundle: .module,
      value: "You allowed",
      comment: "Label under the count of sites the user allowed by hand"
    )
    public static let whatScoutBlocks = NSLocalizedString(
      "scoutProtection.whatScoutBlocks",
      tableName: "BraveShared",
      bundle: .module,
      value: "What Scout blocks",
      comment: "Section header above the content and search filtering settings"
    )
    public static let beyondScout = NSLocalizedString(
      "scoutProtection.beyondScout",
      tableName: "BraveShared",
      bundle: .module,
      value: "Beyond this app",
      comment: "Section header above settings that reach outside the browser"
    )
    public static let yourDecisions = NSLocalizedString(
      "scoutProtection.yourDecisions",
      tableName: "BraveShared",
      bundle: .module,
      value: "Sites you decided about",
      comment: "Section header above the lists of sites the user allowed or blocked"
    )
    public static let safeSearchTitle = NSLocalizedString(
      "scoutProtection.safeSearchTitle",
      tableName: "BraveShared",
      bundle: .module,
      value: "Filter search results",
      comment: "Title of the setting that pins search engines to their filtered mode"
    )
    public static let safeSearchDetail = NSLocalizedString(
      "scoutProtection.safeSearchDetail",
      tableName: "BraveShared",
      bundle: .module,
      value: "Turns on the safe mode built into search engines and YouTube, so explicit results never reach the page.",
      comment: "Explanation of the search filtering setting"
    )
    public static let categoriesSummary = NSLocalizedString(
      "scoutProtection.categoriesSummary",
      tableName: "BraveShared",
      bundle: .module,
      value: "%d of %d on",
      comment: "Summary showing how many blockable content categories are switched on"
    )
    public static let allowedSites = NSLocalizedString(
      "scoutProtection.allowedSites",
      tableName: "BraveShared",
      bundle: .module,
      value: "Allowed sites",
      comment: "Row title for the list of sites the user always allows"
    )
    public static let blockedSites = NSLocalizedString(
      "scoutProtection.blockedSites",
      tableName: "BraveShared",
      bundle: .module,
      value: "Blocked sites",
      comment: "Row title for the list of sites the user always blocks"
    )
    public static let allowedSitesFooter = NSLocalizedString(
      "scoutProtection.allowedSitesFooter",
      tableName: "BraveShared",
      bundle: .module,
      value: "Scout opens these without checking them. Sites land here when you choose \"Always allow this site\" on a blocked page.",
      comment: "Footer under the list of always-allowed sites"
    )
    public static let blockedSitesFooter = NSLocalizedString(
      "scoutProtection.blockedSitesFooter",
      tableName: "BraveShared",
      bundle: .module,
      value: "Scout never opens these, whatever the check says.",
      comment: "Footer under the list of always-blocked sites"
    )
    public static let noAllowedSites = NSLocalizedString(
      "scoutProtection.noAllowedSites",
      tableName: "BraveShared",
      bundle: .module,
      value: "No sites allowed by hand",
      comment: "Empty state for the list of always-allowed sites"
    )
    public static let noBlockedSites = NSLocalizedString(
      "scoutProtection.noBlockedSites",
      tableName: "BraveShared",
      bundle: .module,
      value: "No sites blocked by hand",
      comment: "Empty state for the list of always-blocked sites"
    )
    public static let addSite = NSLocalizedString(
      "scoutProtection.addSite",
      tableName: "BraveShared",
      bundle: .module,
      value: "Add a site",
      comment: "Button that adds a site to the allowed or blocked list"
    )
    public static let sitePlaceholder = NSLocalizedString(
      "scoutProtection.sitePlaceholder",
      tableName: "BraveShared",
      bundle: .module,
      value: "example.com",
      comment: "Placeholder in the field where a site name is typed"
    )
    public static let recentlyBlocked = NSLocalizedString(
      "scoutProtection.recentlyBlocked",
      tableName: "BraveShared",
      bundle: .module,
      value: "Recently blocked",
      comment: "Section header and screen title for the list of blocked navigations"
    )
    public static let nothingBlocked = NSLocalizedString(
      "scoutProtection.nothingBlocked",
      tableName: "BraveShared",
      bundle: .module,
      value: "Nothing has been blocked yet",
      comment: "Empty state for the recently blocked list"
    )
    public static let recentlyBlockedFooter = NSLocalizedString(
      "scoutProtection.recentlyBlockedFooter",
      tableName: "BraveShared",
      bundle: .module,
      value: "This list stays on your phone. A record of what Scout checked is also kept in your account for 30 days.",
      comment: "Footer explaining where the recently blocked list lives"
    )
    public static let activityTitle = NSLocalizedString(
      "scoutProtection.activityTitle",
      tableName: "BraveShared",
      bundle: .module,
      value: "All Activity",
      comment: "Row and screen title for the full record of links Scout checked"
    )
    public static let activityFooter = NSLocalizedString(
      "scoutProtection.activityFooter",
      tableName: "BraveShared",
      bundle: .module,
      value: "Every link Scout was asked to open, kept for 30 days.",
      comment: "Footer under the full activity list"
    )
    public static let activityEmpty = NSLocalizedString(
      "scoutProtection.activityEmpty",
      tableName: "BraveShared",
      bundle: .module,
      value: "Nothing here yet",
      comment: "Empty state for the full activity list"
    )
    public static let activityFailed = NSLocalizedString(
      "scoutProtection.activityFailed",
      tableName: "BraveShared",
      bundle: .module,
      value: "Couldn't load the activity right now.",
      comment: "Shown when the activity list can't be fetched"
    )
    public static let activityRetry = NSLocalizedString(
      "scoutProtection.activityRetry",
      tableName: "BraveShared",
      bundle: .module,
      value: "Try again",
      comment: "Button that retries loading the activity list"
    )
    public static let activityFilterAll = NSLocalizedString(
      "scoutProtection.activityFilterAll",
      tableName: "BraveShared",
      bundle: .module,
      value: "Everything",
      comment: "Filter showing every link Scout checked"
    )
    public static let activityFilterBlocked = NSLocalizedString(
      "scoutProtection.activityFilterBlocked",
      tableName: "BraveShared",
      bundle: .module,
      value: "Blocked only",
      comment: "Filter showing only the links Scout refused"
    )
    public static let activityAllowed = NSLocalizedString(
      "scoutProtection.activityAllowed",
      tableName: "BraveShared",
      bundle: .module,
      value: "Opened",
      comment: "Label on a link Scout allowed"
    )
    public static let activityWarned = NSLocalizedString(
      "scoutProtection.activityWarned",
      tableName: "BraveShared",
      bundle: .module,
      value: "Warned",
      comment: "Label on a link Scout warned about"
    )
    public static let activityFromCache = NSLocalizedString(
      "scoutProtection.activityFromCache",
      tableName: "BraveShared",
      bundle: .module,
      value: "Already known",
      comment: "Note that the decision used a verdict Scout already had, with no new check"
    )
    public static let activityPrivate = NSLocalizedString(
      "scoutProtection.activityPrivate",
      tableName: "BraveShared",
      bundle: .module,
      value: "Private tab",
      comment: "Note that the link was opened in a private tab"
    )
    public static let seeAll = NSLocalizedString(
      "scoutProtection.seeAll",
      tableName: "BraveShared",
      bundle: .module,
      value: "See all",
      comment: "Button that opens the full list of blocked navigations"
    )
    public static let clearList = NSLocalizedString(
      "scoutProtection.clearList",
      tableName: "BraveShared",
      bundle: .module,
      value: "Clear list",
      comment: "Button that empties the recently blocked list"
    )
    public static let continuedAnyway = NSLocalizedString(
      "scoutProtection.continuedAnyway",
      tableName: "BraveShared",
      bundle: .module,
      value: "Opened anyway",
      comment: "Badge on a blocked site the user chose to continue to"
    )
    public static let blockedReasonUnsafe = NSLocalizedString(
      "scoutProtection.blockedReasonUnsafe",
      tableName: "BraveShared",
      bundle: .module,
      value: "Unsafe",
      comment: "Why a site was blocked: the safety check found it dangerous"
    )
    public static let blockedReasonYourList = NSLocalizedString(
      "scoutProtection.blockedReasonYourList",
      tableName: "BraveShared",
      bundle: .module,
      value: "On your blocked list",
      comment: "Why a site was blocked: the user blocked it by hand"
    )
    public static let blockedReasonUnchecked = NSLocalizedString(
      "scoutProtection.blockedReasonUnchecked",
      tableName: "BraveShared",
      bundle: .module,
      value: "Couldn't be checked",
      comment: "Why a site was blocked: the check could not be completed"
    )
    public static let blockedReasonLinkType = NSLocalizedString(
      "scoutProtection.blockedReasonLinkType",
      tableName: "BraveShared",
      bundle: .module,
      value: "Link type Scout doesn't open",
      comment: "Why a site was blocked: the URL scheme is not one Scout opens"
    )
  }

  /// Copy for the Scout panel behind the URL bar.
  public struct ScoutSitePanel {
    public static let checkedSafe = NSLocalizedString(
      "scoutSitePanel.checkedSafe",
      tableName: "BraveShared",
      bundle: .module,
      value: "Checked — nothing unsafe found",
      comment: "Status shown for a site Scout checked and found no problem with"
    )
    public static let checkedUnsafe = NSLocalizedString(
      "scoutSitePanel.checkedUnsafe",
      tableName: "BraveShared",
      bundle: .module,
      value: "Scout found this site unsafe",
      comment: "Status shown for a site the safety check found dangerous"
    )
    public static let checkedSuspicious = NSLocalizedString(
      "scoutSitePanel.checkedSuspicious",
      tableName: "BraveShared",
      bundle: .module,
      value: "Something about this site looks off",
      comment: "Status shown for a site the safety check was unsure about"
    )
    public static let checkedBlockedCategory = NSLocalizedString(
      "scoutSitePanel.checkedBlockedCategory",
      tableName: "BraveShared",
      bundle: .module,
      value: "Matched what you block: %@",
      comment: "Status naming the content categories a site matched. %@ is a list of category names"
    )
    public static let notChecked = NSLocalizedString(
      "scoutSitePanel.notChecked",
      tableName: "BraveShared",
      bundle: .module,
      value: "Not checked yet",
      comment: "Status shown for a page Scout has no verdict for"
    )
    public static let alwaysAllowed = NSLocalizedString(
      "scoutSitePanel.alwaysAllowed",
      tableName: "BraveShared",
      bundle: .module,
      value: "You always allow this site",
      comment: "Status shown for a site the user allowed by hand"
    )
    public static let alwaysBlocked = NSLocalizedString(
      "scoutSitePanel.alwaysBlocked",
      tableName: "BraveShared",
      bundle: .module,
      value: "You always block this site",
      comment: "Status shown for a site the user blocked by hand"
    )
    public static let checkedAt = NSLocalizedString(
      "scoutSitePanel.checkedAt",
      tableName: "BraveShared",
      bundle: .module,
      value: "Checked %@",
      comment: "How long ago the site was checked. %@ is a relative time like \"2 hours ago\""
    )
    public static let allow = NSLocalizedString(
      "scoutSitePanel.allow",
      tableName: "BraveShared",
      bundle: .module,
      value: "Always allow",
      comment: "Button that allows this site from now on"
    )
    public static let block = NSLocalizedString(
      "scoutSitePanel.block",
      tableName: "BraveShared",
      bundle: .module,
      value: "Always block",
      comment: "Button that blocks this site from now on"
    )
    public static let undo = NSLocalizedString(
      "scoutSitePanel.undo",
      tableName: "BraveShared",
      bundle: .module,
      value: "Undo",
      comment: "Button that removes the standing decision the user made about this site"
    )
    public static let recheck = NSLocalizedString(
      "scoutSitePanel.recheck",
      tableName: "BraveShared",
      bundle: .module,
      value: "Check again",
      comment: "Button that discards the stored verdict and checks the site again"
    )
    public static let checking = NSLocalizedString(
      "scoutSitePanel.checking",
      tableName: "BraveShared",
      bundle: .module,
      value: "Checking\u{2026}",
      comment: "Shown on the check-again button while the check runs"
    )
  }
}
