import Foundation

enum SessionActivity: String, Sendable {
    case initializing = "Preparing"
    case starting = "Starting"
    case stopping = "Stopping"
    case changingMode = "Changing Mode"
    case validating = "Checking"
    case quitting = "Quitting"
}

struct SessionSnapshot: Sendable {
    let state: SessionState
    let mode: KeepAwakeMode
    let hasResources: Bool
    let errorMessages: [String]
    let virtualDisplayUnavailableReason: String?
    let activity: SessionActivity?
    let requestedOn: Bool

    var isBusy: Bool { activity != nil }

    fileprivate func presenting(_ activity: SessionActivity?, requestedOn: Bool, clearErrors: Bool = false) -> Self {
        Self(state: state, mode: mode, hasResources: hasResources,
             errorMessages: clearErrors ? [] : errorMessages,
             virtualDisplayUnavailableReason: virtualDisplayUnavailableReason,
             activity: activity, requestedOn: requestedOn)
    }

    fileprivate init(session: KeepAwakeSession) {
        state = session.state
        mode = session.mode
        hasResources = session.hasResources
        errorMessages = session.errorMessages
        virtualDisplayUnavailableReason = session.virtualDisplayUnavailableReason
        activity = nil
        requestedOn = session.hasResources
    }

    private init(state: SessionState, mode: KeepAwakeMode, hasResources: Bool,
                 errorMessages: [String], virtualDisplayUnavailableReason: String?,
                 activity: SessionActivity?, requestedOn: Bool) {
        self.state = state
        self.mode = mode
        self.hasResources = hasResources
        self.errorMessages = errorMessages
        self.virtualDisplayUnavailableReason = virtualDisplayUnavailableReason
        self.activity = activity
        self.requestedOn = requestedOn
    }

    static let initial = Self(state: .off, mode: .screen, hasResources: false,
                              errorMessages: [], virtualDisplayUnavailableReason: nil,
                              activity: .initializing, requestedOn: false)
}

enum SessionTerminationResult: Sendable {
    case completed(SessionSnapshot)
    case timedOut
}

private enum SessionRequest: Sendable {
    case initialize, start, stop, selectMode(KeepAwakeMode), validate(retryUntil: DispatchTime), quit

    var activity: SessionActivity {
        switch self {
        case .initialize: .initializing
        case .start: .starting
        case .stop: .stopping
        case .selectMode: .changingMode
        case .validate: .validating
        case .quit: .quitting
        }
    }
}

private final class SessionExecutor: Sendable {
    // Only queue closures access this storage. Its session and all native handles
    // are created, used, and destroyed on that one executor, never on AppKit's actor.
    private final class Storage: @unchecked Sendable {
        var session: KeepAwakeSession?
    }

    private let queue = DispatchQueue(label: "io.github.underconnor.insomac.session", qos: .userInitiated)
    private let storage = Storage()
    private let makeSession: @Sendable () -> KeepAwakeSession

    init(makeSession: @escaping @Sendable () -> KeepAwakeSession) {
        self.makeSession = makeSession
    }

    func perform(_ request: SessionRequest, completion: @escaping @Sendable (SessionSnapshot, Bool) -> Void) {
        queue.async { [storage, makeSession] in
            if storage.session == nil { storage.session = makeSession() }
            guard let session = storage.session else { return }
            var retryValidation = false
            switch request {
            case .initialize: break
            case .start: session.start()
            case .stop: session.stop()
            case .selectMode(let mode): session.selectMode(mode)
            case .validate(let deadline): retryValidation = session.validateResources(retryUntil: deadline)
            case .quit: session.stop()
            }
            let snapshot = SessionSnapshot(session: session)
            if case .quit = request { storage.session = nil }
            completion(snapshot, retryValidation)
        }
    }

    deinit {
        queue.async { [storage] in storage.session = nil }
    }
}

@MainActor
final class SessionCoordinator {
    private let executor: SessionExecutor
    private let terminationTimeout: TimeInterval
    private let validationGracePeriod: TimeInterval
    private var requests: [SessionRequest] = [.initialize]
    private var inFlight: SessionRequest?
    private var validationPending = false
    private var validationDeadline: DispatchTime?
    private var validationRetry: Task<Void, Never>?
    private var requestedOn = false
    private var quitCompletion: (@MainActor (SessionTerminationResult) -> Void)?
    private var quitReplyDelivered = false

    private(set) var snapshot: SessionSnapshot = .initial
    private(set) var isQuitting = false
    var onChange: (@MainActor (SessionSnapshot) -> Void)?

    init(terminationTimeout: TimeInterval = 15, validationGracePeriod: TimeInterval = 2,
         makeSession: @escaping @Sendable () -> KeepAwakeSession) {
        self.terminationTimeout = terminationTimeout
        self.validationGracePeriod = validationGracePeriod
        executor = SessionExecutor(makeSession: makeSession)
        startNextRequest()
    }

    @discardableResult
    func toggle() -> Bool {
        guard !isQuitting else { return false }
        requestedOn.toggle()
        enqueue(requestedOn ? .start : .stop)
        return true
    }

    @discardableResult
    func stop() -> Bool {
        guard !isQuitting else { return false }
        requestedOn = false
        enqueue(.stop)
        return true
    }

    @discardableResult
    func selectMode(_ mode: KeepAwakeMode) -> Bool {
        guard !isQuitting else { return false }
        requestedOn = false
        enqueue(.selectMode(mode))
        return true
    }

    func validateResources() {
        // A scheduled retry already covers changes that arrive before it starts.
        guard !isQuitting, validationRetry == nil else { return }
        guard inFlight != nil || (snapshot.state == .on && snapshot.mode == .virtualDisplay) else { return }
        validationPending = true
        startNextRequest()
    }

    func prepareToQuit(completion: @escaping @MainActor (SessionTerminationResult) -> Void) {
        guard !isQuitting else { return }
        isQuitting = true
        requestedOn = false
        cancelValidation()
        // Quit supersedes work that has not started, but follows any active
        // operation so its cleanup cannot race a display that is still starting.
        requests = [.quit]
        quitCompletion = completion
        publish(snapshot.presenting(.quitting, requestedOn: false))
        startNextRequest()
        DispatchQueue.main.asyncAfter(deadline: .now() + terminationTimeout) { [weak self] in
            self?.replyToQuit(.timedOut)
        }
    }

    private func enqueue(_ request: SessionRequest) {
        cancelValidation()
        requests.append(request)
        publish(snapshot.presenting(inFlight?.activity ?? request.activity,
                                    requestedOn: requestedOn, clearErrors: true))
        startNextRequest()
    }

    private func startNextRequest() {
        guard inFlight == nil, validationRetry == nil else { return }
        let request: SessionRequest
        if !requests.isEmpty {
            request = requests.removeFirst()
        } else if validationPending && snapshot.state == .on && snapshot.mode == .virtualDisplay {
            validationPending = false
            let deadline = validationDeadline ?? (.now() + validationGracePeriod)
            validationDeadline = deadline
            request = .validate(retryUntil: deadline)
        } else {
            validationPending = false
            requestedOn = snapshot.hasResources
            publish(snapshot.presenting(nil, requestedOn: requestedOn))
            return
        }
        inFlight = request
        publish(snapshot.presenting(isQuitting ? .quitting : request.activity, requestedOn: requestedOn))
        executor.perform(request) { [weak self] result, retryValidation in
            DispatchQueue.main.async {
                self?.completed(request, snapshot: result, retryValidation: retryValidation)
            }
        }
    }

    private func completed(_ request: SessionRequest, snapshot result: SessionSnapshot, retryValidation: Bool) {
        snapshot = result
        inFlight = nil
        if case .validate = request {
            if retryValidation, let deadline = validationDeadline {
                scheduleValidationRetry(until: deadline)
                return
            }
            validationDeadline = nil
        }
        if case .quit = request {
            publish(result)
            replyToQuit(.completed(result))
        } else {
            startNextRequest()
        }
    }

    private func scheduleValidationRetry(until deadline: DispatchTime) {
        validationPending = false
        let now = DispatchTime.now().uptimeNanoseconds
        let remaining = deadline.uptimeNanoseconds - min(now, deadline.uptimeNanoseconds)
        let delay = min(100_000_000, remaining)
        // Keep the busy state visible during the delay and leave the executor free
        // for cleanup if the user requests Off, a mode change, or Quit.
        validationRetry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            self.validationRetry = nil
            self.validationPending = true
            self.startNextRequest()
        }
        publish(snapshot.presenting(.validating, requestedOn: requestedOn))
    }

    private func cancelValidation() {
        validationRetry?.cancel()
        validationRetry = nil
        validationDeadline = nil
        validationPending = false
    }

    private func replyToQuit(_ result: SessionTerminationResult) {
        guard isQuitting, !quitReplyDelivered else { return }
        quitReplyDelivered = true
        let completion = quitCompletion
        quitCompletion = nil
        completion?(result)
    }

    private func publish(_ snapshot: SessionSnapshot) {
        self.snapshot = snapshot
        onChange?(snapshot)
    }
}
