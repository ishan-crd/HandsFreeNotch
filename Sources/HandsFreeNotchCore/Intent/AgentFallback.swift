//
//  AgentFallback.swift
//  HandsFreeNotch
//
//  Copyright © 2026 Ishan Gupta. MIT License.
//

import Foundation

/// Tier 2: hand an open-ended goal to typesafe-computer-use (`clicker`), which reads the screen
/// and clicks through it. Slow and optional; only the LLM tier ever sends work here.
public final class AgentFallback {
    /// The checkout of https://github.com/awlevin/typesafe-computer-use with `uv sync` done.
    public var projectPath: String
    public var maxSteps = 30
    private var process: Process?

    public init(projectPath: String) {
        self.projectPath = projectPath
    }

    public var isAvailable: Bool {
        !projectPath.isEmpty && FileManager.default.fileExists(atPath: projectPath + "/pyproject.toml") && Self.uvPath != nil
    }

    public var isRunning: Bool { process?.isRunning ?? false }

    static var uvPath: String? {
        for p in ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", NSHomeDirectory() + "/.local/bin/uv", NSHomeDirectory() + "/.cargo/bin/uv"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    /// Runs the goal and streams each stdout line to `onLine`; `completion` gets the exit code.
    public func run(goal: String, onLine: @escaping (String) -> Void, completion: @escaping (Int32) -> Void) {
        guard let uv = Self.uvPath else { completion(127); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: uv)
        process.arguments = ["run", "--project", projectPath, "clicker", goal, "--act", "--steps", String(maxSteps)]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        env["PYTHONUNBUFFERED"] = "1"  // otherwise every step's output arrives only at exit
        // The project's .env is the source of truth. clicker only fills variables that are unset,
        // and a login session often carries empty or unrelated ANTHROPIC_* values that would
        // otherwise win, so they are cleared first and the file's values put in their place.
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "TYPESAFE_API_KEY"] { env.removeValue(forKey: key) }
        for (key, value) in Self.dotEnv(at: projectPath + "/.env") where !value.isEmpty { env[key] = value }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { onLine(line) }
            }
        }
        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            completion(p.terminationStatus)
        }
        self.process = process
        do {
            try process.run()
        } catch {
            onLine("could not start clicker: \(error.localizedDescription)")
            completion(126)
        }
    }

    public func stop() {
        process?.terminate()
    }

    /// Whether the project has a key the loop can run on.
    public var hasKey: Bool {
        let env = Self.dotEnv(at: projectPath + "/.env")
        return !(env["ANTHROPIC_API_KEY"] ?? "").isEmpty || !(env["TYPESAFE_API_KEY"] ?? "").isEmpty
    }

    static func dotEnv(at path: String) -> [String: String] {
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
