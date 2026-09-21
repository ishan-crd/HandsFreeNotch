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
    case none, anthropic, ollama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Off (fast tier only)"
        case .anthropic: return "Claude Haiku 4.5"
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

    private let defaults = UserDefaults.standard

    private init() {
        hotkey = Hotkey(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .rightOption
        provider = LLMProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .anthropic
        anthropicModel = defaults.string(forKey: "anthropicModel") ?? AnthropicRouter.defaultModel
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? OllamaRouter.defaultModel
        agentPath = defaults.string(forKey: "agentPath") ?? Settings.guessAgentPath()
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        anthropicKey = Keychain.read("anthropic")
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? Settings.dotEnv()["ANTHROPIC_API_KEY"]
            ?? ""
    }

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
