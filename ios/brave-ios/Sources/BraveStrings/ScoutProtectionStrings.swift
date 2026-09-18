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
    public static let safeSearchUnfilteredDetail = NSLocalizedString(
      "scoutProtection.safeSearchUnfilteredDetail",
      tableName: "BraveShared",
      bundle: .module,
      value:
        "Your search engine, %@, has no safe mode Scout can turn on, so explicit results can still reach the page.",
      comment:
        "Replaces the search filtering explanation when the user's default search engine offers no filter Scout can switch on. %@ is the engine's name, such as Startpage."
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
      value: "You haven't allowed any sites yet",
      comment: "Empty state for the list of always-allowed sites"
    )
    public static let noBlockedSites = NSLocalizedString(
      "scoutProtection.noBlockedSites",
      tableName: "BraveShared",
      bundle: .module,
      value: "You haven't blocked any sites yet",
      comment: "Empty state for the list of always-blocked sites"
    )
    public static let addSite = NSLocalizedString(
      "scoutProtection.addSite",
      tableName: "BraveShared",
      bundle: .module,
      value: "Add a site",
      comment: "Button that adds a site to the allowed or blocked list"
    )
    /// Shown under the field when what was typed isn't a site.
    ///
    /// The Add button disables itself on invalid input, which is correct and
    /// completely silent: someone types, taps, nothing happens, and there is
    /// no way to tell a rejected entry from a broken screen.
    public static let siteInvalid = NSLocalizedString(
      "scoutProtection.siteInvalid",
      tableName: "BraveShared",
      bundle: .module,
      value: "Enter a site name, like example.com",
      comment: "Hint shown when the text typed into the add-a-site field is not a site name"
    )

    /// An allow that happened because nothing could be checked.
    ///
    /// Scout opens the page when a check cannot be completed, which is the
    /// right call on a flaky network but is not the same event as a page that
    /// was checked and found safe. The log said "Opened" for both, which is
    /// exactly the row someone is looking for when asking how a page got
    /// through.
    public static let activityUnchecked = NSLocalizedString(
      "scoutProtection.activityUnchecked",
      tableName: "BraveShared",
      bundle: .module,
      value: "Opened without checking",
      comment: "Shown in the activity log when a page opened because its safety check could not be completed"
    )

    /// The one-line summary under Protection in Settings, where it now sits
    /// on its own rather than among the features.
    public static let settingsSubtitle = NSLocalizedString(
      "scoutProtection.settingsSubtitle",
      tableName: "BraveShared",
      bundle: .module,
      value: "What Scout checks and blocks, and everywhere it has been",
      comment: "Subtitle for the Protection row in Settings"
    )

    public static let askWhenCheckFails = NSLocalizedString(
      "scoutProtection.askWhenCheckFails",
      tableName: "BraveShared",
      bundle: .module,
      value: "Ask if a check can't finish",
      comment: "Title of the setting deciding what happens when a safety check cannot complete"
    )
    public static let askWhenCheckFailsDetail = NSLocalizedString(
      "scoutProtection.askWhenCheckFailsDetail",
      tableName: "BraveShared",
      bundle: .module,
      value:
        "A check can fail because the phone lost signal, not because the site is bad. Off, those pages open and are marked in your activity. On, Scout stops and asks.",
      comment: "Explanation of the setting deciding what happens when a safety check cannot complete"
    )

    /// Shown in place of the explanation while the phone is supervised, when
    /// the setting is forced on and the toggle cannot be moved. Without it the
    /// row says pages open, which is the opposite of what happens.
    public static let askWhenCheckFailsSupervised = NSLocalizedString(
      "scoutProtection.askWhenCheckFailsSupervised",
      tableName: "BraveShared",
      bundle: .module,
      value:
        "While this phone is supervised, Scout always asks. A check that couldn't finish isn't a verdict, so the page isn't opened.",
      comment:
        "Explanation shown when supervision forces the ask-on-failed-check setting on"
    )

    /// Shown instead of "that PIN is wrong" while a wait is running. Saying
    /// the PIN was wrong would be untrue — it was not read — and would leave
    /// someone tapping a button that cannot succeed yet.
    public static let supervisionPINWait = NSLocalizedString(
      "scoutProtection.supervisionPINWait",
      tableName: "BraveShared",
      bundle: .module,
      value: "Too many wrong tries. Try again in %@.",
      comment: "Shown when PIN entry is temporarily locked; %@ is a duration like '5 minutes'"
    )

    // MARK: - Supervision

    public static let supervisionTitle = NSLocalizedString(
      "scoutProtection.supervisionTitle",
      tableName: "BraveShared",
      bundle: .module,
      value: "Let a parent watch this phone",
      comment: "Title of the screen that turns supervision on"
    )
    public static let supervisionDetail = NSLocalizedString(
      "scoutProtection.supervisionDetail",
      tableName: "BraveShared",
      bundle: .module,
      value:
        "A parent can see what Scout checked and blocked here, from their own phone. They can't change anything from there, and private tabs are turned off while this is on.",
      comment: "Explanation of what supervision does"
    )
    public static let supervisionTurnOn = NSLocalizedString(
      "scoutProtection.supervisionTurnOn",
      tableName: "BraveShared",
      bundle: .module,
      value: "Turn on",
      comment: "Button that starts supervision"
    )
    public static let supervisionSetPIN = NSLocalizedString(
      "scoutProtection.supervisionSetPIN",
      tableName: "BraveShared",
      bundle: .module,
      value: "Choose a 4-digit PIN",
      comment: "Prompt to set the supervision PIN"
    )
    /// The key changed under this sentence. Continuing past a block used to
    /// never need the PIN; it now does when the page was found to be an
    /// attack, so the old wording — "Continuing past one block does not need
    /// it" — promised something no longer true on the one screen whose job is
    /// to say what the PIN protects.
    ///
    /// New key, not an edited value: the old one is translated into forty
    /// languages and every one of those translations is now wrong. A fresh key
    /// falls back to this English until they are redone, which is better than
    /// confidently saying the wrong thing in thirty-nine languages.
    public static let supervisionPINDetail = NSLocalizedString(
      "scoutProtection.supervisionPINDetailV2",
      tableName: "BraveShared",
      bundle: .module,
      value:
        "Needed to allow a blocked site, turn a category off, turn this back off, or open a page that was found to be an attack. Continuing past an ordinary block does not need it.",
      comment: "Explanation of what the PIN is for"
    )
    public static let supervisionConfirmPIN = NSLocalizedString(
      "scoutProtection.supervisionConfirmPIN",
      tableName: "BraveShared",
      bundle: .module,
      value: "Enter it again",
      comment: "Prompt to confirm the PIN"
    )
    public static let supervisionPINMismatch = NSLocalizedString(
      "scoutProtection.supervisionPINMismatch",
      tableName: "BraveShared",
      bundle: .module,
      value: "Those don't match",
      comment: "Shown when the two PIN entries differ"
    )
    public static let supervisionWrongPIN = NSLocalizedString(
      "scoutProtection.supervisionWrongPIN",
      tableName: "BraveShared",
      bundle: .module,
      value: "That PIN doesn't match",
      comment: "Shown when the PIN entered is wrong"
    )
    public static let supervisionEnterPIN = NSLocalizedString(
      "scoutProtection.supervisionEnterPIN",
      tableName: "BraveShared",
      bundle: .module,
      value: "Enter the PIN",
      comment: "Title of the sheet asking for the PIN"
    )
    public static let supervisionCodeTitle = NSLocalizedString(
      "scoutProtection.supervisionCodeTitle",
      tableName: "BraveShared",
      bundle: .module,
      value: "Give this code to the parent",
      comment: "Title above the pairing code"
    )
    public static let supervisionCodeDetail = NSLocalizedString(
      "scoutProtection.supervisionCodeDetail",
      tableName: "BraveShared",
      bundle: .module,
      value: "They enter it at %@ within ten minutes. It works once.",
      comment: "Where and how long the pairing code can be used; %@ is a web address"
    )
    public static let supervisionNewCode = NSLocalizedString(
      "scoutProtection.supervisionNewCode",
      tableName: "BraveShared",
      bundle: .module,
      value: "New code",
      comment: "Button that issues a fresh pairing code"
    )
    public static let supervisionCodeFailed = NSLocalizedString(
      "scoutProtection.supervisionCodeFailed",
      tableName: "BraveShared",
      bundle: .module,
      value: "Scout couldn't reach the internet to make a code. Try again.",
      comment: "Shown when a pairing code could not be issued"
    )
    public static let supervisionStopSharing = NSLocalizedString(
      "scoutProtection.supervisionStopSharing",
      tableName: "BraveShared",
      bundle: .module,
      value: "Stop sharing",
      comment: "Button that revokes every parent link"
    )
    public static let supervisionStopSharingDetail = NSLocalizedString(
      "scoutProtection.supervisionStopSharingDetail",
      tableName: "BraveShared",
      bundle: .module,
      value: "Any link a parent saved stops working straight away.",
      comment: "What Stop sharing does"
    )
    public static let supervisionTurnOff = NSLocalizedString(
      "scoutProtection.supervisionTurnOff",
      tableName: "BraveShared",
      bundle: .module,
      value: "Turn off supervision",
      comment: "Button that ends supervision"
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
    public static let blockedReasonKnownThreat = NSLocalizedString(
      "scoutProtection.blockedReasonKnownThreat",
      tableName: "BraveShared",
      bundle: .module,
      value: "Known phishing or malware",
      comment:
        "Why a site was blocked: its address is on a public list of sites caught phishing or spreading malware"
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
