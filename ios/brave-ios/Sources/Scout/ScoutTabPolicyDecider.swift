import Foundation

public enum ScoutTabPolicyDecision: Equatable { case allow, cancel }

public final class ScoutTabPolicyDecider {
  private let guard_: NavigationGuard
  private let onBlock: (String) -> Void

  public init(guard: NavigationGuard, onBlock: @escaping (String) -> Void) {
    self.guard_ = `guard`; self.onBlock = onBlock
  }

  // Unit-testable seam: run the guard and translate to allow/cancel, loading
  // the interstitial on a non-allow outcome.
  public func decision(for url: URL) async -> ScoutTabPolicyDecision {
    let decision = await guard_.decide(url)
    if decision.type == .allow { return .allow }
    onBlock(ScoutInterstitial.html(type: decision.type, verdict: decision.verdict, reason: decision.reason,
                                     matchedCategories: decision.matchedCategories))
    return .cancel
  }

  // Phase 1 (brave-ios): conform to TabPolicyDecider and map .allow/.cancel to WebPolicyDecision here.
}
