import Foundation

/// 記錄從 API 取得的食譜資料，讓 QA 請求可以取回完整 context
final class CookRecipeContextRegistry {
    static let shared = CookRecipeContextRegistry()

    private let queue = DispatchQueue(label: "CookRecipeContextRegistry.queue")
    private var contexts: [String: CookQARecipeContext] = [:]

    private init() {}

    func register(_ context: CookQARecipeContext) {
        let signature = Self.signature(for: context.recipe)
        queue.async {
            self.contexts[signature] = context
        }
    }

    func context(matching steps: [RecipeStep]) -> CookQARecipeContext? {
        let signature = Self.signature(for: steps)
        return queue.sync {
            contexts[signature]
        }
    }

    private static func signature(for steps: [RecipeStep]) -> String {
        steps
            .sorted(by: { $0.step_number < $1.step_number })
            .map { "\($0.step_number)|\($0.title)|\($0.description)" }
            .joined(separator: "||")
    }
}

