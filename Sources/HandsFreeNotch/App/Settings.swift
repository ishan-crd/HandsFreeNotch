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
    var anthropicKey: String { didSet { KeyStore.write(anthropicKey, name: "ANTHROPIC_API_KEY") } }
    var openrouterKey: String { didSet { KeyStore.write(openrouterKey, name: "OPENROUTER_API_KEY") } }
    var openrouterModel: String { didSet { defaults.set(openrouterModel, forKey: "openrouterModel") } }

    private let defaults = UserDefaults.standard

    /// Re-reads the provider and key after the command line changed them.
    func reload() {
        provider = LLMProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .anthropic
        let anthropic = KeyStore.read("ANTHROPIC_API_KEY") ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        if anthropic != anthropicKey { anthropicKey = anthropic }
        let openrouter = KeyStore.read("OPENROUTER_API_KEY") ?? ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        if openrouter != openrouterKey { openrouterKey = openrouter }
        openrouterModel = defaults.string(forKey: "openrouterModel") ?? OpenRouterRouter.defaultModel
    }

    private init() {
        hotkey = Hotkey(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .rightOption
        provider = LLMProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .anthropic
        anthropicModel = defaults.string(forKey: "anthropicModel") ?? AnthropicRouter.defaultModel
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? OllamaRouter.defaultModel
        openrouterModel = defaults.string(forKey: "openrouterModel") ?? OpenRouterRouter.defaultModel
        openrouterKey = KeyStore.read("OPENROUTER_API_KEY") ?? ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        agentPath = defaults.string(forKey: "agentPath") ?? Settings.guessAgentPath()
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        anthropicKey = KeyStore.read("ANTHROPIC_API_KEY") ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
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
