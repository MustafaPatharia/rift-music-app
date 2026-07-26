// SPDX-License-Identifier: GPL-3.0-only
//
// OllamaClient — talks to a locally running Ollama server (default port
// 11434). Used when the user picks Ollama as the AI provider in Settings:
// list installed models, download ("pull") a model with progress, and chat.
// Ollama itself is installed by the user from ollama.com — we never bundle it.

import Foundation

struct OllamaClient {
    private static let base = URL(string: "http://127.0.0.1:11434")!

    static func running() async -> Bool {
        var req = URLRequest(url: base)
        req.timeoutInterval = 2
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// Names of locally installed models (GET /api/tags).
    static func models() async throws -> [String] {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("api/tags"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = (json?["models"] as? [[String: Any]]) ?? []
        return models.compactMap { $0["name"] as? String }
    }

    /// Download a model (POST /api/pull, streaming NDJSON progress lines).
    static func pull(_ model: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        var req = URLRequest(url: base.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 3600
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": model])
        let (bytes, _) = try await URLSession.shared.bytes(for: req)
        for try await line in bytes.lines {
            guard let d = line.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            if let err = j["error"] as? String {
                throw NSError(domain: "Ollama", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
            }
            if let total = j["total"] as? Double, total > 0,
               let done = j["completed"] as? Double {
                progress(done / total)
            }
        }
    }

    /// One-shot chat completion (POST /api/chat, stream:false).
    static func chat(system: String, user: String, model: String) async throws -> String {
        guard !model.isEmpty else {
            throw NSError(domain: "Ollama", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "No Ollama model selected."])
        }
        var req = URLRequest(url: base.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = j["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            let err = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "Ollama", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: err ?? "malformed Ollama response"])
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
