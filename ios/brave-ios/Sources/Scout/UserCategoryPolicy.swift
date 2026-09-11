import Foundation

/// A policy whose blocked categories are the user's own choice, read live on
/// every decision; everything else (allow/block lists, scheme rules, fail
/// mode) comes from `base`.
///
/// The closure is the seam: the browser backs it with a persisted preference,
/// so a change made in onboarding or Settings applies to the very next
/// navigation without anyone having to push it into the policy.
public final class UserCategoryPolicy: PolicyProviding {
  private let base: PolicyProviding
  private let chosenCategories: () -> Set<ContentCategory>

  public init(base: PolicyProviding, blockedCategories: @escaping () -> Set<ContentCategory>) {
    self.base = base
    self.chosenCategories = blockedCategories
  }

  public var blockedCategories: Set<ContentCategory> { chosenCategories() }
  public var failMode: FailMode { base.failMode }
  public func decideHost(_ url: URL) -> LocalDecision { base.decideHost(url) }
  public func schemeDecision(_ url: URL) -> SchemeRule? { base.schemeDecision(url) }
}
