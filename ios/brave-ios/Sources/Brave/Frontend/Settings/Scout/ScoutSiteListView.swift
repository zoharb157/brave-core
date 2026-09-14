// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Scout
import Shared
import Strings
import SwiftUI

/// The sites the user always allows, or always blocks.
///
/// Reachable and editable, not just written to from a blocked page: a standing
/// decision the user can't find again is one they can't take back, and "always
/// allow" would then be a one-way door.
struct ScoutSiteListView: View {
  let rule: SiteRule

  @State private var sites: [String] = []
  @State private var typed = ""
  @FocusState private var fieldFocused: Bool

  var body: some View {
    List {
      Section {
        if sites.isEmpty {
          Text(
            rule == .allow
              ? Strings.ScoutProtection.noAllowedSites : Strings.ScoutProtection.noBlockedSites
          )
          .font(.subheadline)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
        } else {
          ForEach(sites, id: \.self) { site in
            HStack(spacing: 12) {
              Image(systemName: rule == .allow ? "checkmark.circle.fill" : "minus.circle.fill")
                .foregroundStyle(rule == .allow ? scoutMint : scoutRose)
              Text(site).lineLimit(1).truncationMode(.middle)
            }
          }
          .onDelete(perform: remove)
        }
      } footer: {
        Text(
          rule == .allow
            ? Strings.ScoutProtection.allowedSitesFooter
            : Strings.ScoutProtection.blockedSitesFooter
        )
      }

      Section {
        HStack(spacing: 10) {
          TextField(Strings.ScoutProtection.sitePlaceholder, text: $typed)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .submitLabel(.done)
            .focused($fieldFocused)
            .onSubmit(add)
          Button(Strings.ScoutProtection.addSite, action: add)
            .disabled(normalized(typed) == nil)
            .foregroundStyle(normalized(typed) == nil ? Color(braveSystemName: .textSecondary) : scoutViolet)
        }
      } footer: {
        // Only once there is something to be wrong about: an empty field is
        // not a mistake, it is the starting state.
        if hasUnusableInput {
          Text(Strings.ScoutProtection.siteInvalid)
            .foregroundStyle(scoutRose)
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(
      rule == .allow ? Strings.ScoutProtection.allowedSites : Strings.ScoutProtection.blockedSites
    )
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !sites.isEmpty {
        ToolbarItem(placement: .topBarTrailing) { EditButton() }
      }
    }
    .onAppear { sites = ScoutServices.shared.siteRules.sites(rule) }
  }

  /// Whether the user has typed something that isn't a site.
  ///
  /// Without this the Add button simply refuses to work and says nothing,
  /// which reads as a broken screen rather than a rejected entry.
  private var hasUnusableInput: Bool {
    !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalized(typed) == nil
  }

  /// What the user typed, as a site name — or nil if there isn't one in there.
  ///
  /// People paste whole addresses into a field like this, so a pasted
  /// `https://example.com/page?q=1` is accepted and reduced to the site it
  /// names rather than rejected for not looking like a hostname.
  private func normalized(_ text: String) -> String? {
    var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if candidate.isEmpty { return nil }
    if let url = URL(string: candidate), let host = url.host {
      candidate = host
    } else {
      candidate = candidate.components(separatedBy: "/").first ?? candidate
    }
    guard candidate.contains("."), !candidate.hasPrefix("."), !candidate.hasSuffix("."),
      !candidate.contains(" ")
    else { return nil }
    return candidate
  }

  private func add() {
    guard let site = normalized(typed) else { return }
    ScoutServices.shared.siteRules.set(rule, forSite: site)
    sites = ScoutServices.shared.siteRules.sites(rule)
    typed = ""
    fieldFocused = false
  }

  private func remove(at offsets: IndexSet) {
    let rules = ScoutServices.shared.siteRules
    for index in offsets {
      rules.set(nil, forSite: sites[index])
    }
    sites = rules.sites(rule)
  }
}
