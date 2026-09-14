import Foundation

/// A policy whose blocked categories — and, when the browser supplies one,
/// what happens to a check that cannot be completed — are the user's own
/// choice, read live on every decision; everything else (allow/block lists,
/// scheme rules) comes from `base`.
///
/// The closure is the seam: the browser backs it with a persisted preference,
/// so a change made in onboarding or Settings applies to the very next
/// navigation without anyone having to push it into the policy.
public final class UserCategoryPolicy: PolicyProviding {
  private let base: PolicyProviding
  private let chosenCategories: () -> Set<ContentCategory>
  private let chosenFailMode: (() -> FailMode)?

  /// - Parameter failMode: what to do when a check cannot be completed, read
  ///   live like the categories. Omit it and `base` decides, which is what a
  ///   caller with no setting behind it wants.
  public init(
    base: PolicyProviding,
    blockedCategories: @escaping () -> Set<ContentCategory>,
    failMode: (() -> FailMode)? = nil
  ) {
    self.base = base
    self.chosenCategories = blockedCategories
    self.chosenFailMode = failMode
  }

  public var blockedCategories: Set<ContentCategory> { chosenCategories() }
  public var failMode: FailMode { chosenFailMode?() ?? base.failMode }
  public func decideHost(_ url: URL) -> LocalDecision { base.decideHost(url) }
  public func schemeDecision(_ url: URL) -> SchemeRule? { base.schemeDecision(url) }
}
