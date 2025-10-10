import Foundation

struct CookQARequest: Codable {
    let question: String
    let current_step_description: String
    let image: String
    let recipe: CookQARecipeContext?
}

struct CookQAResponse: Codable {
    let answer: String
}

private struct CookQAErrorResponse: Codable {
    let message: String?
}

enum CookQAServiceError: LocalizedError {
    case invalidURL
    case encodingFailed
    case invalidResponse
    case server(message: String)
    case decodingFailed
    case network(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "請確認伺服器設定，無法建立請求。"
        case .encodingFailed:
            return "無法建立請求內容，請稍後重試。"
        case .invalidResponse:
            return "伺服器回應異常。"
        case .server(let message):
            return message.isEmpty ? "伺服器發生錯誤。" : message
        case .decodingFailed:
            return "無法解析伺服器回應。"
        case .network(let message):
            return message
        }
    }
}

final class CookQAService {
    static let shared = CookQAService()

    private init() {}

    private static var baseURL: String {
        guard var raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String else {
            return ""
        }
        while raw.hasSuffix("/") && !raw.hasSuffix("://") {
            raw.removeLast()
        }
        return raw
    }

    func askCookAssistant(
        question: String,
        stepDescription: String,
        base64Image: String,
        recipeContext: CookQARecipeContext?
    ) async throws -> CookQAResponse {
        guard let url = URL(string: "\(Self.baseURL)/api/v1/cook/qa") else {
            throw CookQAServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CookQARequest(
            question: question,
            current_step_description: stepDescription,
            image: base64Image,
            recipe: recipeContext
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let bodyData = try encoder.encode(payload)
            request.httpBody = bodyData

            if let jsonObject = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                var sanitized = jsonObject
                if sanitized["image"] != nil {
                    sanitized["image"] = "<omitted>"
                }
                let dataWithoutImage = try JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .withoutEscapingSlashes])
                if let jsonString = String(data: dataWithoutImage, encoding: .utf8) {
                    print("🧾 [CookQAService] Request payload:\n\(jsonString)")
                }
            }
        } catch {
            throw CookQAServiceError.encodingFailed
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CookQAServiceError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let decoder = JSONDecoder()
                let message = (try? decoder.decode(CookQAErrorResponse.self, from: data).message)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !message.isEmpty {
                    print("❌ [CookQAService] Server error message: \(message)")
                }
                throw CookQAServiceError.server(message: message)
            }

            do {
                let decoder = JSONDecoder()
                return try decoder.decode(CookQAResponse.self, from: data)
            } catch {
                throw CookQAServiceError.decodingFailed
            }

        } catch let error as CookQAServiceError {
            throw error
        } catch let urlError as URLError {
            throw CookQAServiceError.network(message: urlError.localizedDescription)
        } catch {
            throw CookQAServiceError.network(message: error.localizedDescription)
        }
    }
}
