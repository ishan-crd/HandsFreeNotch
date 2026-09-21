//
//  LLMRouter.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation

/// Tier 1: a small model turns an unusual sentence into the same `Intent` the fast router
/// produces. No screenshot, no page text: just the words and the list of installed apps, so a
/// call is a few hundred tokens and a few hundred milliseconds.
public protocol LLMRouter {
    var label: String { get }
    func route(_ transcript: String, apps: AppIndex) async throws -> Routed?
}

public enum LLMRouterError: LocalizedError {
    case missingKey
    case http(Int, String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "No API key set. Open the notch and add one in Settings."
        case let .http(code, body): return "LLM request failed (\(code)): \(body.prefix(200))"
        case let .badResponse(why): return "LLM gave an unusable answer: \(why)"
        }
    }
}

/// The one JSON shape both providers fill in. Kept flat so a 1.5B local model can manage it.
struct RoutePayload: Decodable {
    var action: String
    var app: String?
    var url: String?
    var query: String?
    var engine: String?
    var text: String?
    var key: String?
    var modifiers: [String]?
    var amount: Int?
    var goal: String?

    static let actions = [
        "open_app", "open_url", "search", "type_text", "press_key", "shortcut", "quit_app", "hide_app",
        "scroll_down", "scroll_up", "volume_up", "volume_down", "volume_set", "mute", "unmute",
        "brightness_up", "brightness_down", "play_pause", "next_track", "previous_track",
        "lock_screen", "sleep", "screenshot", "show_desktop", "mission_control", "spotlight",
        "empty_trash", "agent", "cancel",
    ]

    static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["action"],
        "properties": [
            "action": ["type": "string", "enum": actions],
            "app": ["type": "string", "description": "Exact name from the installed apps list, for open_app/quit_app/hide_app"],
            "url": ["type": "string", "description": "Full https URL for open_url"],
            "query": ["type": "string", "description": "Search terms for search"],
            "engine": ["type": "string", "enum": SearchEngine.allCases.map(\.rawValue)],
            "text": ["type": "string", "description": "Text to type for type_text"],
            "key": ["type": "string", "description": "Key name for press_key: enter, escape, tab, space, delete, up, down, left, right, or a single letter/digit"],
            "modifiers": ["type": "array", "items": ["type": "string", "enum": ["command", "shift", "option", "control"]]],
            "amount": ["type": "integer", "description": "Percent for volume_set, lines for scroll, steps for volume up/down"],
            "goal": ["type": "string", "description": "For agent: the full goal in the user's words"],
        ],
    ]

    static func systemPrompt(apps: [String]) -> String {
        """
        You route one spoken command from a macOS user to one action. Reply only by calling the route tool.
        Rules:
        - Use open_app only with an exact name from INSTALLED APPS. If the user names an app that is not installed but is a website (netflix, gmail), use open_url.
        - Prefer the simplest action that satisfies the sentence. "play some jazz" is open_app Spotify only if nothing better exists; if the request needs clicking around inside an app or a website (find a product, book something, reply to a message, read something on screen), use agent with the full goal.
        - shortcut takes key+modifiers, e.g. new tab is key "t" with ["command"].
        - Unclear or not a command: cancel.
        INSTALLED APPS: \(apps.joined(separator: ", "))
        """
    }

    func intent(apps: AppIndex) throws -> Intent {
        func app() throws -> AppEntry {
            guard let name = self.app, let match = apps.match(name), match.1 >= 0.7 else {
                throw LLMRouterError.badResponse("unknown app \(self.app ?? "nil")")
            }
            return match.0
        }
        func chord() throws -> KeyChord {
            guard let key = self.key?.lowercased(), let k = FastRouter.keyNames[key] else {
                throw LLMRouterError.badResponse("unknown key \(self.key ?? "nil")")
            }
            let mods = Set(modifiers ?? [])
            return KeyChord(k, command: mods.contains("command"), shift: mods.contains("shift"), option: mods.contains("option"), control: mods.contains("control"))
        }
        switch action {
        case "open_app": return .openApp(try app())
        case "open_url":
            guard let s = url, let u = URL(string: s), u.scheme != nil else { throw LLMRouterError.badResponse("bad url") }
            return .openURL(u)
        case "search":
            guard let q = query, !q.isEmpty else { throw LLMRouterError.badResponse("empty query") }
            return .search(query: q, engine: SearchEngine(rawValue: engine ?? "google") ?? .google)
        case "type_text":
            guard let t = text, !t.isEmpty else { throw LLMRouterError.badResponse("empty text") }
            return .typeText(t)
        case "press_key", "shortcut": return .pressKey(try chord())
        case "quit_app": return .quitApp(try app())
        case "hide_app": return .hideApp(try app())
        case "scroll_down": return .scroll(.down(lines: amount ?? 10))
        case "scroll_up": return .scroll(.up(lines: amount ?? 10))
        case "volume_up": return .volume(.up(steps: amount ?? 3))
        case "volume_down": return .volume(.down(steps: amount ?? 3))
        case "volume_set": return .volume(.set(percent: max(0, min(100, amount ?? 50))))
        case "mute": return .volume(.mute)
        case "unmute": return .volume(.unmute)
        case "brightness_up": return .brightness(up: true)
        case "brightness_down": return .brightness(up: false)
        case "play_pause": return .media(.playPause)
        case "next_track": return .media(.next)
        case "previous_track": return .media(.previous)
        case "lock_screen": return .system(.lockScreen)
        case "sleep": return .system(.sleep)
        case "screenshot": return .system(.screenshot)
        case "show_desktop": return .system(.showDesktop)
        case "mission_control": return .system(.missionControl)
        case "spotlight": return .system(.spotlight)
        case "empty_trash": return .system(.emptyTrash)
        case "agent": return .agent(goal: goal ?? "")
        case "cancel": return .cancel
        default: throw LLMRouterError.badResponse("unknown action \(action)")
        }
    }
}

// MARK: - Anthropic

/// Claude Haiku 4.5 through the Messages API with one strict tool, so the answer is always the
/// shape above. About $0.0003 a command.
public struct AnthropicRouter: LLMRouter {
    public static let defaultModel = "claude-haiku-4-5"
    public var apiKey: String
    public var model: String
    public var timeout: TimeInterval = 8

    public init(apiKey: String, model: String = AnthropicRouter.defaultModel) {
        self.apiKey = apiKey
        self.model = model
    }

    public var label: String { model }

    public func route(_ transcript: String, apps: AppIndex) async throws -> Routed? {
        guard !apiKey.isEmpty else { throw LLMRouterError.missingKey }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "system": RoutePayload.systemPrompt(apps: apps.names),
            "tools": [[
                "name": "route",
                "description": "The single action to take for the spoken command.",
                "strict": true,
                "input_schema": RoutePayload.schema,
            ]],
            "tool_choice": ["type": "tool", "name": "route"],
            "messages": [["role": "user", "content": transcript]],
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LLMRouterError.http(status, String(data: data, encoding: .utf8) ?? "") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let tool = content.first(where: { $0["type"] as? String == "tool_use" }),
              let input = tool["input"] else {
            throw LLMRouterError.badResponse("no tool_use block")
        }
        let payload = try JSONDecoder().decode(RoutePayload.self, from: JSONSerialization.data(withJSONObject: input))
        return Routed(try payload.intent(apps: apps), confidence: 0.8, tier: .llm)
    }
}

// MARK: - Ollama

/// A local model through Ollama's chat endpoint with a JSON schema response. Free, offline, and
/// good enough for this flat schema with a 1-3B model.
public struct OllamaRouter: LLMRouter {
    public static let defaultModel = "qwen2.5:1.5b"
    public var model: String
    public var endpoint: URL
    public var timeout: TimeInterval = 10

    public init(model: String = OllamaRouter.defaultModel, endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!) {
        self.model = model
        self.endpoint = endpoint
    }

    public var label: String { "ollama/\(model)" }

    public func route(_ transcript: String, apps: AppIndex) async throws -> Routed? {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "format": RoutePayload.schema,
            "options": ["temperature": 0, "num_predict": 200],
            "messages": [
                ["role": "system", "content": RoutePayload.systemPrompt(apps: apps.names) + "\nAnswer with one JSON object only."],
                ["role": "user", "content": transcript],
            ],
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMRouterError.badResponse("Ollama is not running · brew install ollama && ollama pull \(model)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw LLMRouterError.badResponse("model \(model) is not pulled · ollama pull \(model)") }
        guard status == 200 else { throw LLMRouterError.http(status, String(data: data, encoding: .utf8) ?? "") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String,
              let payloadData = content.data(using: .utf8) else {
            throw LLMRouterError.badResponse("no message content")
        }
        let payload = try JSONDecoder().decode(RoutePayload.self, from: payloadData)
        return Routed(try payload.intent(apps: apps), confidence: 0.7, tier: .llm)
    }
}

// MARK: - OpenRouter (OpenAI-compatible)

/// Any OpenAI-compatible chat endpoint; OpenRouter's free models by default. The route is asked
/// for as a forced tool call; models that answer in plain JSON instead are parsed leniently.
public struct OpenRouterRouter: LLMRouter {
    public static let defaultModel = "nex-agi/nex-n2.5-mini:free"
    /// Free models that answered this exact tool call correctly when tested, fastest first. The
    /// request names all of them so OpenRouter moves on when one is rate-limited upstream.
    public static let fallbacks = [
        "cohere/north-mini-code:free",
        "inclusionai/ling-3.0-flash-sante:free",
        "nvidia/nemotron-3-super-120b-a12b:free",
        "liquid/lfm-2.5-2.6b:free",
        "google/gemma-4-26b-a4b-it:free",
        "qwen/qwen3.8-27b:free",
    ]
    public var apiKey: String
    public var model: String
    public var endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    public var timeout: TimeInterval = 12

    public init(apiKey: String, model: String = OpenRouterRouter.defaultModel) {
        self.apiKey = apiKey
        self.model = model
    }

    public var label: String { "openrouter/\(model)" }

    public func route(_ transcript: String, apps: AppIndex) async throws -> Routed? {
        guard !apiKey.isEmpty else { throw LLMRouterError.missingKey }
        let tool: [String: Any] = [
            "type": "function",
            "function": [
                "name": "route",
                "description": "The single action to take for the spoken command.",
                "parameters": RoutePayload.schema,
            ],
        ]
        let models = [model] + Self.fallbacks.filter { $0 != model }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 300,
            "temperature": 0,
            "tools": [tool],
            "tool_choice": ["type": "function", "function": ["name": "route"]],
            "messages": [
                ["role": "system", "content": RoutePayload.systemPrompt(apps: apps.names) + "\nCall the route tool exactly once. If you cannot call tools, reply with the JSON object only."],
                ["role": "user", "content": transcript],
            ],
        ]
        // Free models are rate-limited upstream. OpenRouter takes at most three models per request
        // and moves down that list itself; a second request covers the rest of ours.
        var data = Data()
        var status = 0
        for attempt in 0..<3 {
            let order = Array(models.dropFirst(attempt * 3).prefix(3))
            guard !order.isEmpty else { break }
            body["model"] = order[0]
            body["models"] = order
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("https://github.com/ishan-crd/HandsFreeNotch", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("HandsFreeNotch", forHTTPHeaderField: "X-Title")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (d, response) = try await URLSession.shared.data(for: request)
            data = d
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status != 429 { break }
        }
        if status == 429 { throw LLMRouterError.badResponse("every free model is busy right now; try again in a moment") }
        guard status == 200 else { throw LLMRouterError.http(status, String(data: data, encoding: .utf8) ?? "") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw LLMRouterError.badResponse("no choices")
        }
        let payloadData: Data
        if let calls = message["tool_calls"] as? [[String: Any]],
           let function = calls.first?["function"] as? [String: Any],
           let arguments = function["arguments"] as? String, let d = arguments.data(using: .utf8) {
            payloadData = d
        } else if let content = message["content"] as? String, let d = Self.extractJSON(content) {
            payloadData = d
        } else {
            throw LLMRouterError.badResponse("no tool call or JSON in the reply")
        }
        let payload = try JSONDecoder().decode(RoutePayload.self, from: payloadData)
        return Routed(try payload.intent(apps: apps), confidence: 0.75, tier: .llm)
    }

    /// The first {...} in a reply, with any ```json fences stripped.
    static func extractJSON(_ text: String) -> Data? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return nil }
        return String(text[open...close]).data(using: .utf8)
    }
}
