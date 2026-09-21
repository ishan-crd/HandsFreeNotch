//
//  CommandPipeline.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation

/// The whole trip from a held key to a finished action: listen, route through the tiers, act.
///
/// Tier 0 runs on every partial transcript, so a command like "open Spotify" fires the moment
/// the words stop changing, usually while the key is still held. Everything the fast tier
/// cannot place goes to the small model once the sentence is complete, and only a goal the
/// model marks as needing the screen goes to the agent.
@MainActor
public final class CommandPipeline {
    public enum State: Equatable {
        case idle
        case listening(transcript: String)
        case thinking(transcript: String)
        case done(title: String, tier: Routed.Tier, milliseconds: Int)
        case agent(goal: String, lines: [String])
        case failed(message: String)
        case help
    }

    public private(set) var state: State = .idle {
        didSet {
            onState?(state)
            onLog?("state: \(state)")
        }
    }
    public var onState: ((State) -> Void)?
    /// One line per state change, for the system log.
    public var onLog: ((String) -> Void)?
    public var onLevel: ((Float) -> Void)?
    /// Every command that ran, newest first, for the panel.
    public private(set) var history: [(transcript: String, title: String, tier: Routed.Tier, milliseconds: Int)] = []

    public let speech: SpeechListener
    public let apps: AppIndex
    public let fast: FastRouter
    public var llm: LLMRouter?
    public var agent: AgentFallback?
    /// How long a partial must stay unchanged before the fast tier acts on it.
    public var stableAfter: TimeInterval = 0.3
    /// How long to wait for the recognizer's final result after the key is released.
    public var finalGrace: TimeInterval = 0.6

    private var lastPartial = ""
    private var lastPartialAt: TimeInterval = 0
    private var firedPrefix: String?
    private var releasedAt: TimeInterval?
    private var stableCheck: DispatchWorkItem?
    private var graceCheck: DispatchWorkItem?
    private var idleReset: DispatchWorkItem?
    private var llmTask: Task<Void, Never>?

    public init(speech: SpeechListener, apps: AppIndex, llm: LLMRouter? = nil, agent: AgentFallback? = nil) {
        self.speech = speech
        self.apps = apps
        self.fast = FastRouter(apps: apps)
        self.llm = llm
        self.agent = agent
        speech.onTranscript = { [weak self] text, isFinal in self?.heard(text, isFinal: isFinal) }
        speech.onLevel = { [weak self] level in self?.onLevel?(level) }
        speech.onError = { [weak self] error in self?.fail(error.localizedDescription) }
    }

    /// Whether the microphone is open. The displayed state can briefly be `.done` while it is.
    public var isListening: Bool { speech.isListening }

    // MARK: - Key down / key up

    public func beginListening() {
        if case .agent = state, agent?.isRunning == true { return }
        idleReset?.cancel()
        llmTask?.cancel()
        lastPartial = ""
        firedPrefix = nil
        releasedAt = nil
        apps.refreshIfNeeded()
        do {
            try speech.start()
            state = .listening(transcript: "")
        } catch {
            fail(error.localizedDescription)
        }
    }

    public func endListening() {
        guard isListening else { return }
        releasedAt = now()
        speech.stop()
        stableCheck?.cancel()
        // The recognizer usually finalises within a couple hundred milliseconds. If it does not,
        // the last partial is what we have.
        let grace = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.speech.forceFinal(self.lastPartial)
        }
        graceCheck = grace
        DispatchQueue.main.asyncAfter(deadline: .now() + finalGrace, execute: grace)
    }

    public func cancel() {
        stableCheck?.cancel()
        graceCheck?.cancel()
        llmTask?.cancel()
        speech.cancel()
        agent?.stop()
        state = .idle
    }

    /// Route text as if it had been spoken, e.g. from the panel's text field or a test.
    public func handle(_ text: String) {
        releasedAt = now()
        Task { await route(text) }
    }

    // MARK: - Transcripts

    private func heard(_ text: String, isFinal: Bool) {
        if isFinal {
            graceCheck?.cancel()
            stableCheck?.cancel()
            Task { await finish(text) }
            return
        }
        guard speech.isListening else { return }
        if case .listening = state { state = .listening(transcript: text) }
        let normalized = Normalizer.normalize(text)
        guard normalized != lastPartial else { return }
        lastPartial = normalized
        lastPartialAt = now()
        stableCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in self?.tryEarlyFire() }
        stableCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + stableAfter, execute: check)
    }

    /// The fast tier acts on a transcript that has stopped changing, without waiting for release.
    private func tryEarlyFire() {
        guard speech.isListening, firedPrefix == nil, !lastPartial.isEmpty else { return }
        // Only a near-certain match fires before release: a prefix of a longer name never does.
        guard let routed = fast.route(lastPartial), routed.intent.firesEarly, routed.confidence >= 0.95 else { return }
        firedPrefix = lastPartial
        let started = lastPartialAt
        perform(routed, transcript: lastPartial, since: started, keepListening: true)
    }

    private func finish(_ text: String) async {
        let normalized = Normalizer.normalize(text)
        if let firedPrefix {
            // Whatever came after the part that already ran is its own command.
            var rest = normalized
            if rest.hasPrefix(firedPrefix) { rest = String(rest.dropFirst(firedPrefix.count)).trimmingCharacters(in: .whitespaces) }
            else if Fuzzy.score(rest, firedPrefix) > 0.8 { rest = "" }
            for joiner in ["and then ", "then ", "and "] where rest.hasPrefix(joiner) { rest = String(rest.dropFirst(joiner.count)) }
            self.firedPrefix = nil
            if rest.isEmpty { scheduleIdle(); return }
            await route(rest)
            return
        }
        guard !normalized.isEmpty else { state = .idle; return }
        await route(normalized)
    }

    // MARK: - Routing

    private func route(_ text: String) async {
        let started = releasedAt ?? now()
        let parts = Normalizer.splitSequence(text)
        // A sequence runs only when every step is a fast-tier command; otherwise the model sees the whole sentence.
        if parts.count > 1 {
            let routedParts = parts.compactMap { fast.route($0) }
            if routedParts.count == parts.count {
                for r in routedParts {
                    perform(r, transcript: text, since: started, keepListening: false)
                    try? await Task.sleep(nanoseconds: 350_000_000)
                }
                return
            }
        }
        if let routed = fast.route(text) {
            perform(routed, transcript: text, since: started, keepListening: false)
            return
        }
        guard let llm else {
            fail("Didn't catch a command in “\(text)”. Add an API key in Settings to handle free-form requests.")
            return
        }
        state = .thinking(transcript: text)
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                guard let routed = try await llm.route(text, apps: self.apps) else {
                    self.fail("Didn't understand “\(text)”")
                    return
                }
                guard !Task.isCancelled else { return }
                if case let .agent(goal) = routed.intent {
                    self.runAgent(goal: goal.isEmpty ? text : goal)
                } else {
                    self.perform(routed, transcript: text, since: started, keepListening: false)
                }
            } catch is CancellationError {
            } catch {
                self.fail(error.localizedDescription)
            }
        }
        llmTask = task
        await task.value
    }

    private func perform(_ routed: Routed, transcript: String, since started: TimeInterval, keepListening: Bool) {
        if case .help = routed.intent { state = .help; scheduleIdle(after: 8); return }
        if case .cancel = routed.intent { state = .idle; return }
        do {
            try ActionRunner.run(routed.intent)
            let ms = Int((now() - started) * 1000)
            history.insert((transcript, routed.intent.title, routed.tier, ms), at: 0)
            if history.count > 20 { history.removeLast() }
            state = .done(title: routed.intent.title, tier: routed.tier, milliseconds: ms)
            if keepListening {
                // Show the result but keep the microphone open for the rest of the sentence.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                    guard let self, self.speech.isListening, case .done = self.state else { return }
                    self.state = .listening(transcript: "")
                }
            } else {
                scheduleIdle()
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func runAgent(goal: String) {
        guard let agent, agent.isAvailable else {
            fail("“\(goal)” needs the screen agent. Set the typesafe-computer-use path in Settings.")
            return
        }
        var lines: [String] = []
        state = .agent(goal: goal, lines: lines)
        let started = now()
        agent.run(goal: goal, onLine: { [weak self] line in
            DispatchQueue.main.async {
                guard let self else { return }
                lines.append(line)
                if lines.count > 6 { lines.removeFirst() }
                self.state = .agent(goal: goal, lines: lines)
            }
        }, completion: { [weak self] code in
            DispatchQueue.main.async {
                guard let self else { return }
                let ms = Int((self.now() - started) * 1000)
                if code == 0 {
                    self.history.insert((goal, "Agent: \(goal)", .agent, ms), at: 0)
                    self.state = .done(title: lines.last ?? "Agent finished", tier: .agent, milliseconds: ms)
                    self.scheduleIdle(after: 6)
                } else {
                    self.fail(lines.last ?? "Agent stopped (exit \(code))")
                }
            }
        })
    }

    private func fail(_ message: String) {
        state = .failed(message: message)
        scheduleIdle(after: 4)
    }

    private func scheduleIdle(after seconds: TimeInterval = 1.4) {
        idleReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            guard let self, !self.speech.isListening else { return }
            self.state = .idle
        }
        idleReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: reset)
    }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
