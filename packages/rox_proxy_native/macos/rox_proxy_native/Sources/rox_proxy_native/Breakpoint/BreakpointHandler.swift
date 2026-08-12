import Foundation
import NIOCore

/// Suspends requests at breakpoints, waits for a user decision, enforces the
/// timeout (RF5) and releases every suspension on shutdown (RNF2).
///
/// Thread safety: the pending registry is guarded by a lock. Notifications are
/// dispatched to the UI boundary (`Notifier`); decisions arrive from any
/// thread (typically the main thread via MethodChannel) and are hopped back to
/// the suspension's own event loop. Each pending request resolves exactly once.
final class BreakpointHandler: @unchecked Sendable {

    /// UI availability + notification boundary.
    /// Implemented by `BreakpointStreamHandler` (Flutter EventChannel) in the
    /// plugin; stubbed in CoreTests.
    protocol Notifier: AnyObject {
        /// True when the UI is listening. When false the core must not
        /// suspend: traffic is forwarded immediately (RF3.3).
        var isAvailable: Bool { get }
        func requestSuspended(_ request: BreakpointRequest)
        func responseSuspended(_ response: ResponseBreakpoint)
    }

    /// Timeout before auto-proceed with the original request (RF5.1).
    static let defaultTimeout: TimeAmount = .seconds(30)

    let matcher: BreakpointMatcher

    private let lock = NSLock()
    private var notifier: Notifier?
    private var pending: [String: Pending] = [:]

    private struct Pending {
        let breakpointId: String
        let eventLoop: EventLoop
        let onDecision: (BreakpointResponse) -> Void
        let timeoutTask: Scheduled<Void>
    }

    init(matcher: BreakpointMatcher, notifier: Notifier? = nil) {
        self.matcher = matcher
        self.notifier = notifier
    }

    // MARK: - Wiring

    func setNotifier(_ notifier: Notifier?) {
        lock.lock()
        self.notifier = notifier
        lock.unlock()
    }

    /// True when a UI is available to receive notifications right now.
    var isNotifierAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return notifier?.isAvailable ?? false
    }

    // MARK: - Suspend

    /// Registers a suspended request and notifies the UI.
    ///
    /// Returns `false` when the UI cannot be reached (notifier missing or not
    /// listening): in that case nothing is registered and the caller must
    /// forward the request immediately (RF3.3 — never block without UI).
    func suspend(
        request: BreakpointRequest,
        eventLoop: EventLoop,
        onDecision: @escaping (BreakpointResponse) -> Void
    ) -> Bool {
        lock.lock()
        guard let notifier, notifier.isAvailable else {
            lock.unlock()
            ProxyLogger.breakpoint.default("Breakpoint: UI unavailable, forwarding request %{public}@", request.method)
            return false
        }
        notifier.requestSuspended(request)
        let breakpointId = request.id
        let timeoutTask = eventLoop.scheduleTask(in: Self.defaultTimeout) { [weak self] in
            ProxyLogger.breakpoint.info("Breakpoint %{public}@: timeout, auto-proceeding", breakpointId)
            self?.resolve(breakpointId: breakpointId, response: .autoProceed(breakpointId: breakpointId))
        }
        pending[breakpointId] = Pending(
            breakpointId: breakpointId,
            eventLoop: eventLoop,
            onDecision: onDecision,
            timeoutTask: timeoutTask
        )
        lock.unlock()
        return true
    }

    /// Registers a suspended response and notifies the UI. Same semantics as
    /// `suspend(request:...)`; returns false when the UI cannot be reached.
    func suspend(
        response: ResponseBreakpoint,
        eventLoop: EventLoop,
        onDecision: @escaping (BreakpointResponse) -> Void
    ) -> Bool {
        lock.lock()
        guard let notifier, notifier.isAvailable else {
            lock.unlock()
            ProxyLogger.breakpoint.default("Breakpoint: UI unavailable, forwarding response")
            return false
        }
        notifier.responseSuspended(response)
        let breakpointId = response.id
        let timeoutTask = eventLoop.scheduleTask(in: Self.defaultTimeout) { [weak self] in
            ProxyLogger.breakpoint.info("Breakpoint %{public}@: timeout, auto-proceeding", breakpointId)
            self?.resolve(breakpointId: breakpointId, response: .autoProceed(breakpointId: breakpointId))
        }
        pending[breakpointId] = Pending(
            breakpointId: breakpointId,
            eventLoop: eventLoop,
            onDecision: onDecision,
            timeoutTask: timeoutTask
        )
        lock.unlock()
        return true
    }

    // MARK: - Decision

    /// Resolves a suspended request with the user decision. Safe to call from
    /// any thread. Unknown or already-resolved ids are ignored (exactly-once).
    func resolve(breakpointId: String, response: BreakpointResponse) {
        lock.lock()
        guard let entry = pending.removeValue(forKey: breakpointId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        entry.timeoutTask.cancel()
        ProxyLogger.breakpoint.info("Breakpoint %{public}@: decision %{public}@", breakpointId, response.action.rawValue)
        entry.eventLoop.execute { entry.onDecision(response) }
    }

    // MARK: - Shutdown

    /// Releases every suspended request with an auto-proceed decision
    /// (RNF2 — shutdown pulito, no hang at `stopProxy`).
    func releaseAll() {
        lock.lock()
        let entries = Array(pending.values)
        pending.removeAll()
        lock.unlock()

        for entry in entries {
            entry.timeoutTask.cancel()
            ProxyLogger.breakpoint.info("Breakpoint %{public}@: released on shutdown", entry.breakpointId)
            entry.eventLoop.execute { entry.onDecision(.autoProceed(breakpointId: entry.breakpointId)) }
        }
    }

    // MARK: - Inspection

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }
}
