//
//  KeyStore.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation

/// API keys live in ~/.config/handsfreenotch/.env, readable only by the user. The keychain
/// would be the textbook place, but it puts up a permission dialog every time the app is
/// rebuilt with a different code hash, and that dialog blocks launch.
enum KeyStore {
    static let path = NSHomeDirectory() + "/.config/handsfreenotch/.env"

    static func read(_ name: String) -> String? {
        let value = load()[name] ?? ""
        return value.isEmpty ? nil : value
    }

    static func write(_ value: String, name: String) {
        var env = load()
        env[name] = value
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let text = env.keys.sorted().map { "\($0)=\(env[$0] ?? "")" }.joined(separator: "\n") + "\n"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// KEY=VALUE lines; comments and blank lines are dropped on the next write.
    static func load() -> [String: String] {
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
}
