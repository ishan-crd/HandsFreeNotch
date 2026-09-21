//
//  Settings.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation
import HandsFreeNotchCore
import Observation

enum LLMProvider: String, CaseIterable, Identifiable {
    case none, anthropic, openrouter, ollama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Off (fast tier only)"
        case .anthropic: return "Claude Haiku 4.5"
        case .openrouter: return "OpenRouter (free models)"
        case .ollama: return "Ollama (local)"
        }
    }
}

/// Everything the user can change, persisted in defaults except the key.
@Observable
final class Settings {
    static let shared = Settings()

    var hotkey: Hotkey { didSet { defaults.set(hotkey.rawValue, forKey: "hotkey") } }
    var provider: LLMProvider { didSet { defaults.set(provider.rawValue, forKey: "provider") } }
    var anthropicModel: String { didSet { defaults.set(anthropicModel, forKey: "anthropicModel") } }
    var ollamaModel: String { didSet { defaults.set(ollamaModel, forKey: "ollamaModel") } }
    var agentPath: String { didSet { defaults.set(agentPath, forKey: "agentPath") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var anthropicKey: String { didSet { Keychain.write(anthropicKey, account: "anthropic") } }
    var openrouterKey: String { didSet { Keychain.write(openrouterKey, account: "openrouter") } }
    var openrouterModel: String { didSet { defaults.set(openrouterModel, forKey: "openrouterModel") } }

    private let defaults = UserDefaults.standard

    /// Re-reads the provider and key after the command line changed them.
    func reload() {
        provider = LLMProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .anthropic
        let stored = Keychain.read("anthropic") ?? ""
        if !stored.isEmpty {
            if stored != anthropicKey { anthropicKey = stored; keySource = "keychain" }
        } else if keySource == "keychain" {
            anthropicKey = ""  // removed with `--set-key ""`
        }
        let openrouter = Keychain.read("openrouter") ?? ""
        if openrouter != openrouterKey { openrouterKey = openrouter }
        openrouterModel = defaults.string(forKey: "openrouterModel") ?? OpenRouterRouter.defaultModel
    }

    private init() {
        hotkey = Hotkey(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .rightOption
        provider = LLMProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .anthropic
        anthropicModel = defaults.string(forKey: "anthropicModel") ?? AnthropicRouter.defaultModel
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? OllamaRouter.defaultModel
        openrouterModel = defaults.string(forKey: "openrouterModel") ?? OpenRouterRouter.defaultModel
        openrouterKey = Keychain.read("openrouter") ?? ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? Settings.dotEnv()["OPENROUTER_API_KEY"] ?? ""
        agentPath = defaults.string(forKey: "agentPath") ?? Settings.guessAgentPath()
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        // First non-empty source wins: keychain, the environment, then the dotenv file.
        let sources: [(String, String?)] = [
            ("keychain", Keychain.read("anthropic")),
            ("environment", ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]),
            ("dotenv", Settings.dotEnv()["ANTHROPIC_API_KEY"]),
        ]
        let found = sources.first { !($0.1 ?? "").isEmpty }
        anthropicKey = found?.1 ?? ""
        keySource = found?.0 ?? "none"
    }

    /// Where the key came from, for the launch log.
    private(set) var keySource: String

    /// KEY=VALUE lines from ~/.config/handsfreenotch/.env, for people who would rather not use the keychain.
    private static func dotEnv() -> [String: String] {
        let path = NSHomeDirectory() + "/.config/handsfreenotch/.env"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            out[key] = value
        }
        return out
    }

    /// The router the pipeline should use right now.
    func makeLLM() -> LLMRouter? {
        switch provider {
        case .none: return nil
        case .anthropic: return anthropicKey.isEmpty ? nil : AnthropicRouter(apiKey: anthropicKey, model: anthropicModel)
        case .openrouter: return openrouterKey.isEmpty ? nil : OpenRouterRouter(apiKey: openrouterKey, model: openrouterModel)
        case .ollama: return OllamaRouter(model: ollamaModel)
        }
    }

    func makeAgent() -> AgentFallback? {
        agentPath.isEmpty ? nil : AgentFallback(projectPath: agentPath)
    }

    private static func guessAgentPath() -> String {
        let candidates = [
            NSHomeDirectory() + "/typesafe-computer-use",
            NSHomeDirectory() + "/superconductor/projects/typesafe-computer-use",
            NSHomeDirectory() + "/Projects/typesafe-computer-use",
            NSHomeDirectory() + "/code/typesafe-computer-use",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0 + "/pyproject.toml") } ?? ""
    }
}
