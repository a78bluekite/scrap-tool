import Foundation

enum ClaudeError: Error, LocalizedError {
    case missingKey
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "API 키가 설정되지 않았습니다."
        case .badResponse(let msg): return msg
        }
    }
}

enum ClaudeClient {
    static let model = "claude-opus-4-8"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static func send(prompt: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.badResponse("응답을 받지 못했습니다.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ClaudeError.badResponse(msg)
        }

        struct ContentBlock: Decodable { let type: String; let text: String? }
        struct Response: Decodable { let content: [ContentBlock] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.content.compactMap { $0.text }.joined()
    }
}
