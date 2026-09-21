//
//  CommandPipeline.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation

/// The whole trip from a held key to finished actions: listen, route through the tiers, act.
///
/// The transcript is consumed as it streams in. "open safari and search youtube and on youtube
/// search faze rug" runs as three commands, each the moment its words are settled, while the
/// user is still talking. What the fast tier cannot place goes to the small model once the
/// sentence is complete, and only a goal the model marks as needing the screen goes to the agent.
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
    /// Listening stays on after the key is released, until a tap, "stop", or a long silence.
    public private(set) var continuous = false

    public let speech: SpeechListener
    public let apps: AppIndex
    public let fast: FastRouter
    public var llm: LLMRouter?
    public var agent: AgentFallback?
    /// What carries out an intent; tests swap in a recorder.
    public var runner: (Intent) throws -> Void = ActionRunner.run
    /// How long a partial must stay unchanged before its settled segments run.
    public var stableAfter: TimeInterval = 0.3
    /// How long to wait for the recognizer's final result after the key is released.
    public var finalGrace: TimeInterval = 0.6
    /// Continuous mode switches itself off after this much silence.
    public var continuousTimeout: TimeInterval = 30

    /// Words that end one command and start the next.
    private static let separators: [[String]] = [["and", "then"], ["after", "that"], ["and", "also"], ["then"], ["also"], ["and"]]
    /// These split even before a search or dictation; a bare "and" needs a command after it.
    private static let strongSeparators: Set<String> = ["and then", "after that", "then"]

    private var sessionWords: [String] = []   // the current recognizer session's transcript, normalized
    private var consumedWords = 0             // how many of those already ran
    private var lastPartialAt: TimeInterval = 0
    private var startedAt: TimeInterval = 0
    private var releasedAt: TimeInterval?
    private var stableCheck: DispatchWorkItem?
    private var graceCheck: DispatchWorkItem?
    private var idleReset: DispatchWorkItem?
    private var silenceCheck: DispatchWorkItem?
    private var llmTask: Task<Void, Never>?

    public init(speech: SpeechListener, apps: AppIndex, llm: LLMRouter? = nil, agent: AgentFallback? = nil) {
        self.speech = speech
        self.apps = apps
        self.fast = FastRouter(apps: apps)
        self.llm = llm
        self.agent = agent
        speech.onTranscript = { [weak self] text, isFinal in self?.heard(text, isFinal: isFinal) }
        speech.onLevel = { [weak self] level in self?.onLevel?(level) }
        speech.onError = { [weak self] error in
            self?.onLog?("speech error: \(error)")
            self?.fail(error.localizedDescription)
        }
    }

    /// Whether the microphone is open. The displayed state can briefly be `.done` while it is.
    public var isListening: Bool { speech.isListening }

    // MARK: - Key down / key up

    public func beginListening() {
        if case .agent = state, agent?.isRunning == true { return }
        // A listen that never closed out (recognizer hung) must not block the next one.
        if speech.isListening { speech.cancel() }
        graceCheck?.cancel()
        stableCheck?.cancel()
        idleReset?.cancel()
        llmTask?.cancel()
        sessionWords = []
        consumedWords = 0
        releasedAt = nil
        startedAt = now()
        apps.refreshIfNeeded()
        do {
            try speech.start()
            state = .listening(transcript: "")
            if continuous { armSilenceTimeout() }
        } catch {
            onLog?("speech start failed: \(error)")
            fail(error.localizedDescription)
        }
    }

    public func endListening() {
        guard speech.isListening else { return }
        continuous = false
        silenceCheck?.cancel()
        releasedAt = now()
        speech.stop()
        stableCheck?.cancel()
        // The recognizer usually finalises within a couple hundred milliseconds. If it does not,
        // the last partial is what we have.
        let grace = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.speech.forceFinal(self.sessionWords.joined(separator: " "))
        }
        graceCheck = grace
        DispatchQueue.main.asyncAfter(deadline: .now() + finalGrace, execute: grace)
    }

    /// Keep the microphone open after the key is released, until `stopContinuous`.
    public func startContinuous() {
        continuous = true
        if !speech.isListening { beginListening() } else { armSilenceTimeout() }
        state = .listening(transcript: "")
    }

    public func stopContinuous() {
        continuous = false
        silenceCheck?.cancel()
        if speech.isListening { endListening() } else { state = .idle }
    }

    public func cancel() {
        continuous = false
        stableCheck?.cancel()
        graceCheck?.cancel()
        silenceCheck?.cancel()
        llmTask?.cancel()
        speech.cancel()
        agent?.stop()
        state = .idle
    }

    /// Route text as if it had been spoken, e.g. from the panel's text field or a test.
    public func handle(_ text: String) {
        releasedAt = now()
        sessionWords = words(of: text)
        consumedWords = 0
        Task { await consume(final: true) }
    }

    // MARK: - Transcripts

    private func words(of text: String) -> [String] {
        Normalizer.normalize(text).split(separator: " ").map(String.init)
    }

    private func heard(_ text: String, isFinal: Bool) {
        ingest(text, isFinal: isFinal, listening: speech.isListening)
    }

    /// One transcript update from the recognizer (or a test standing in for it).
    func ingest(_ text: String, isFinal: Bool, listening: Bool) {
        onLog?("heard\(isFinal ? " (final)" : ""): \(text)")
        let incoming = words(of: text)
        // The recognizer may rewrite earlier words; never let that un-consume what already ran.
        if incoming.count >= consumedWords || isFinal { sessionWords = incoming }
        if isFinal {
            graceCheck?.cancel()
            stableCheck?.cancel()
            Task { await consume(final: true) }
            return
        }
        guard listening else { return }
        lastPartialAt = now()
        if case .listening = state { state = .listening(transcript: pendingText) }
        if continuous { armSilenceTimeout() }
        stableCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { await self.consume(final: false) }
        }
        stableCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + stableAfter, execute: check)
    }

    /// The words heard so far that have not run yet.
    private var pendingText: String {
        sessionWords.dropFirst(min(consumedWords, sessionWords.count)).joined(separator: " ")
    }

    // MARK: - Streaming segmentation

    /// Runs every settled command in the pending words, in order. With `final`, whatever is left
    /// runs too, through the model when the fast tier cannot place it.
    private func consume(final: Bool) async {
        while true {
            // A separator left over from the previous cut ("… and") is not part of the next command.
            while let sep = Self.separators.first(where: { Array(sessionWords.dropFirst(consumedWords).prefix($0.count)) == $0 }) {
                consumedWords += sep.count
            }
            let rest = Array(sessionWords.dropFirst(min(consumedWords, sessionWords.count)))
            guard !rest.isEmpty else { break }
            let started = final ? (releasedAt ?? lastPartialAt) : lastPartialAt

            guard let cut = nextSegment(in: rest, final: final) else {
                // Nothing settled yet. With a final transcript, the remainder is one command.
                if final { await route(rest.joined(separator: " "), since: started) ; consumedWords = sessionWords.count }
                break
            }
            let text = rest[0..<cut.length].joined(separator: " ")
            consumedWords += cut.length + cut.separator
            if let routed = fast.route(text) {
                perform(routed, transcript: text, since: started, keepListening: speech.isListening)
                // Give the app a beat to come forward before the next keystroke lands in it.
                if cut.separator > 0 || final { try? await Task.sleep(nanoseconds: 250_000_000) }
            } else {
                await route(text, since: started)
            }
        }
        if final, !speech.isListening, !continuous {
            if case .listening = state { state = .idle } else if case .done = state { scheduleIdle() }
        }
        if final, continuous {
            // The sentence is over; start a fresh session so the transcript stays short.
            sessionWords = []
            consumedWords = 0
            if !speech.isListening { beginListening() }
        }
    }

    private struct Cut { let length: Int; let separator: Int }

    /// The first command in `rest` that can run now: its word count, and the separator after it.
    private func nextSegment(in rest: [String], final: Bool) -> Cut? {
        // Candidate cut points: each separator, then the end of the words.
        var candidates: [(length: Int, separator: Int, strong: Bool)] = []
        var i = 0
        while i < rest.count {
            for sep in Self.separators where i + sep.count <= rest.count && Array(rest[i..<i + sep.count]) == sep {
                if i > 0 { candidates.append((i, sep.count, Self.strongSeparators.contains(sep.joined(separator: " ")))) }
                i += sep.count - 1
                break
            }
            i += 1
        }
        for candidate in candidates {
            let text = rest[0..<candidate.length].joined(separator: " ")
            guard let routed = fast.route(text) else { continue }
            // "open safari and …": the app command is complete on its own.
            if routed.intent.firesEarly, routed.confidence >= 0.9 { return Cut(length: candidate.length, separator: candidate.separator) }
            // "search youtube and on youtube search …": a search ends when a command follows it.
            if candidate.strong { return Cut(length: candidate.length, separator: candidate.separator) }
            let after = Array(rest[(candidate.length + candidate.separator)...])
            if let nextCut = firstSeparator(in: after), fast.route(after[0..<nextCut].joined(separator: " ")) != nil {
                return Cut(length: candidate.length, separator: candidate.separator)
            }
            if fast.route(after.joined(separator: " ")) != nil, after.count >= 2 || final {
                return Cut(length: candidate.length, separator: candidate.separator)
            }
        }
        // "open safari search youtube": two commands with nothing between them. Cut where a certain
        // app/site/key command ends and another command begins.
        let limit = firstSeparator(in: rest) ?? rest.count
        if limit > 1 {
            for i in 1..<limit {
                let head = rest[0..<i].joined(separator: " ")
                guard let routed = fast.route(head), routed.intent.firesEarly, routed.confidence >= 0.9 else { continue }
                if fast.route(rest[i..<limit].joined(separator: " ")) != nil { return Cut(length: i, separator: 0) }
            }
        }
        // No separator settled it. The whole remainder runs when it is a complete, certain command.
        let whole = rest.joined(separator: " ")
        if let routed = fast.route(whole) {
            if final { return Cut(length: rest.count, separator: 0) }
            if routed.intent.firesEarly, routed.confidence >= 0.95 { return Cut(length: rest.count, separator: 0) }
        }
        return nil
    }

    private func firstSeparator(in words: [String]) -> Int? {
        var i = 0
        while i < words.count {
            for sep in Self.separators where i + sep.count <= words.count && Array(words[i..<i + sep.count]) == sep {
                return i > 0 ? i : nil
            }
            i += 1
        }
        return nil
    }

    // MARK: - Routing

    private func route(_ text: String, since started: TimeInterval) async {
        if let routed = fast.route(text) {
            perform(routed, transcript: text, since: started, keepListening: speech.isListening)
            return
        }
        guard let llm else {
            fail("Not a command: “\(text)” · add an API key in Settings for free-form requests")
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
                    self.perform(routed, transcript: text, since: started, keepListening: self.speech.isListening)
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
        if case .cancel = routed.intent {
            if continuous { stopContinuous() } else { state = .idle }
            return
        }
        do {
            try runner(routed.intent)
            let ms = Int((now() - started) * 1000)
            history.insert((transcript, routed.intent.title, routed.tier, ms), at: 0)
            if history.count > 20 { history.removeLast() }
            state = .done(title: routed.intent.title, tier: routed.tier, milliseconds: ms)
            if keepListening {
                // Show the result but keep the microphone open for the rest of the sentence.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self, self.speech.isListening, case .done = self.state else { return }
                    self.state = .listening(transcript: self.pendingText)
                }
            }
            // Once the microphone closes, the result lingers under a second and fades.
            scheduleIdle()
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

    private func scheduleIdle(after seconds: TimeInterval = 0.8) {
        idleReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            guard let self, !self.speech.isListening else { return }
            self.state = .idle
        }
        idleReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: reset)
    }

    private func armSilenceTimeout() {
        silenceCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self, self.continuous else { return }
            self.onLog?("continuous: silence timeout")
            self.stopContinuous()
        }
        silenceCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + continuousTimeout, execute: check)
    }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
