//
//  PurchaseResultReporter.swift
//  CmdReopen
//
//  Sends one `purchase result` for every purchase or restore attempt,
//  wherever it started. The access manager publishes no feedback for a
//  cancellation, so the end of an attempt is read from its progress flags.
//

#if APPSTORE
import Combine
import Foundation
import KikiAnalytics
import KikiCommerceCore

@MainActor
final class PurchaseResultReporter {
    /// The paywall sheet currently on screen; attempts started outside one
    /// (the win-back card) carry no session.
    static var activePaywallSession: KikiAnalyticsSessionID?

    private struct Attempt {
        let operation: CommandReopenEvent.PurchaseOperation
        let plan: CommandReopenEvent.PlanKind?
        let session: KikiAnalyticsSessionID?
    }

    private let manager: KikiAccessManager
    private let send: (CommandReopenEvent) -> Void
    private var attempt: Attempt?
    private var cancellables: Set<AnyCancellable> = []

    init(manager: KikiAccessManager, send: @escaping (CommandReopenEvent) -> Void) {
        self.manager = manager
        self.send = send
        // `@Published` emits before the property changes; by the time the
        // flag clears, the manager has already written feedback and error.
        manager.$purchaseInProgressPlanID
            .removeDuplicates()
            .sink { [weak self] planID in
                guard let self else { return }
                if let planID {
                    begin(.purchase, plan: Self.planKind(planID))
                } else {
                    finish(.purchase)
                }
            }
            .store(in: &cancellables)
        manager.$isRestoringPurchases
            .removeDuplicates()
            .sink { [weak self] isRestoring in
                guard let self else { return }
                if isRestoring {
                    begin(.restore, plan: nil)
                } else {
                    finish(.restore)
                }
            }
            .store(in: &cancellables)
    }

    private func begin(_ operation: CommandReopenEvent.PurchaseOperation, plan: CommandReopenEvent.PlanKind?) {
        attempt = Attempt(operation: operation, plan: plan, session: Self.activePaywallSession)
    }

    private func finish(_ operation: CommandReopenEvent.PurchaseOperation) {
        guard let attempt, attempt.operation == operation else { return }
        self.attempt = nil
        let (result, error) = Self.outcome(feedback: manager.commerceFeedback, lastError: manager.lastError)
        send(.purchaseResult(
            session: attempt.session, operation: operation, result: result, plan: attempt.plan, error: error
        ))
    }

    static func planKind(_ planID: String) -> CommandReopenEvent.PlanKind? {
        switch CommercePlan(planID) {
        case .lifetime: .lifetime
        case .winbackLifetime: .winbackLifetime
        default: nil
        }
    }

    static func outcome(
        feedback: KikiCommerceFeedback?,
        lastError: CommercePurchaseError?
    ) -> (CommandReopenEvent.PurchaseOutcome, CommandReopenEvent.ErrorCategory?) {
        if let feedback { return outcome(of: feedback) }
        // Only a cancellation leaves no feedback behind.
        if let lastError { return outcome(of: .error(lastError)) }
        return (.failed, .other)
    }

    static func outcome(
        of feedback: KikiCommerceFeedback
    ) -> (CommandReopenEvent.PurchaseOutcome, CommandReopenEvent.ErrorCategory?) {
        switch feedback {
        case .purchaseSucceeded, .restoreSucceeded: (.success, nil)
        case .noActivePurchase: (.failed, .noActivePurchase)
        case .error(let error):
            switch error {
            case .purchaseCancelled: (.cancelled, nil)
            case .activationPending: (.pending, nil)
            case .network: (.failed, .network)
            case .offeringUnavailable, .productUnavailable, .packageNotFound, .productIdentifierMissing:
                (.failed, .unavailable)
            case .purchaseNotAllowed: (.failed, .notAllowed)
            default: (.failed, .other)
            }
        }
    }
}

#endif
