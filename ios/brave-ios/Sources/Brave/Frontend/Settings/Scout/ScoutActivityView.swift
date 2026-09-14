// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Onboarding
import Scout
import Shared
import Strings
import SwiftUI

/// Every link Scout was asked to open, and what it did.
///
/// The on-device list next to this one shows blocks, instantly and offline.
/// This shows everything — including the links that were allowed and the ones
/// decided from a verdict Scout already had — which is what a question like
/// "how did that page get through?" actually needs to answer.
struct ScoutActivityView: View {
  private enum Filter: Hashable { case all, blocked }
  private enum Load: Equatable { case loading, loaded, failed }

  @State private var records: [ScoutActivityReporter.ActivityRecord] = []
  @State private var state: Load = .loading
  @State private var filter: Filter = .all

  private var shown: [ScoutActivityReporter.ActivityRecord] {
    filter == .all ? records : records.filter { $0.decision == .block }
  }

  var body: some View {
    List {
      Section {
        Picker("", selection: $filter) {
          Text(Strings.ScoutProtection.activityFilterAll).tag(Filter.all)
          Text(Strings.ScoutProtection.activityFilterBlocked).tag(Filter.blocked)
        }
        .pickerStyle(.segmented)
        .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
      }

      Section {
        switch state {
        case .loading:
          HStack {
            ProgressView()
            Spacer()
          }
        case .failed:
          VStack(alignment: .leading, spacing: 10) {
            Text(Strings.ScoutProtection.activityFailed)
              .font(.subheadline)
              .foregroundStyle(Color(braveSystemName: .textSecondary))
            Button(Strings.ScoutProtection.activityRetry) {
              Task { await load() }
            }
            .foregroundStyle(scoutViolet)
          }
        case .loaded:
          if shown.isEmpty {
            Text(Strings.ScoutProtection.activityEmpty)
              .font(.subheadline)
              .foregroundStyle(Color(braveSystemName: .textSecondary))
          } else {
            ForEach(shown) { record in
              ActivityRow(record: record)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                  // Reading the log is where someone notices a site they want
                  // decided differently. Making them go and type it into a
                  // list somewhere else is how that intention gets lost.
                  ruleButton(for: record)
                }
            }
          }
        }
      } footer: {
        Text(Strings.ScoutProtection.activityFooter)
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(Strings.ScoutProtection.activityTitle)
    .navigationBarTitleDisplayMode(.inline)
    .refreshable { await load() }
    .task { await load() }
  }

  /// Sets a standing rule from the row, or clears it if this site already has
  /// the one the button would set.
  @ViewBuilder private func ruleButton(
    for record: ScoutActivityReporter.ActivityRecord
  ) -> some View {
    let site = record.site.isEmpty ? (URL(string: record.url)?.host ?? "") : record.site
    if !site.isEmpty {
      let existing = ScoutServices.shared.siteRules.rule(forSite: site)
      if record.decision == .block {
        Button(Strings.ScoutSitePanel.allow) {
          ScoutServices.shared.siteRules.set(existing == .allow ? nil : .allow, forSite: site)
        }
        .tint(scoutMint)
      } else {
        Button(Strings.ScoutSitePanel.block) {
          ScoutServices.shared.siteRules.set(existing == .block ? nil : .block, forSite: site)
        }
        .tint(scoutViolet)
      }
    }
  }

  private func load() async {
    if records.isEmpty { state = .loading }
    do {
      records = try await ScoutActivityReporter.shared.recentActivity()
      state = .loaded
    } catch {
      state = .failed
    }
  }
}

/// One decision, said plainly: what was asked for, what happened, and why.
private struct ActivityRow: View {
  let record: ScoutActivityReporter.ActivityRecord

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 15))
        .foregroundStyle(tint)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 3) {
        Text(record.site.isEmpty ? record.url : record.site)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(detail)
          .font(.footnote)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
          .fixedSize(horizontal: false, vertical: true)
        if !notes.isEmpty {
          Text(notes.joined(separator: " · "))
            .font(.caption2)
            .foregroundStyle(Color(braveSystemName: .textTertiary))
        }
      }
      Spacer(minLength: 8)
      Text(record.date, format: .relative(presentation: .numeric))
        .font(.caption2)
        .foregroundStyle(Color(braveSystemName: .textSecondary))
    }
    .accessibilityElement(children: .combine)
  }

  private var symbol: String {
    switch record.decision {
    case .allow: return record.continued ? "arrow.turn.down.right" : "checkmark.circle"
    case .warn: return "exclamationmark.circle"
    case .block: return "hand.raised.fill"
    }
  }

  private var tint: Color {
    switch record.decision {
    case .allow: return scoutMint
    case .warn: return scoutAmber
    case .block: return scoutViolet
    }
  }

  /// Why it went that way. A block reuses the same wording as the on-device
  /// list, so the two never disagree about the same event.
  private var detail: String {
    switch record.decision {
    case .allow:
      return record.continued
        ? Strings.ScoutProtection.continuedAnyway : Strings.ScoutProtection.activityAllowed
    case .warn:
      return Strings.ScoutProtection.activityWarned
    case .block:
      return BlockRecordRow.why(
        BlockRecord(
          site: record.site, reason: record.reason, categories: record.categories,
          date: record.date, continued: record.continued))
    }
  }

  /// The two facts that explain a surprising row: whether anything was
  /// actually checked for it, and whether it happened out of sight.
  private var notes: [String] {
    var notes: [String] = []
    if record.source == .cache { notes.append(Strings.ScoutProtection.activityFromCache) }
    if record.isPrivate { notes.append(Strings.ScoutProtection.activityPrivate) }
    return notes
  }
}
