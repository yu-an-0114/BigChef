import Foundation

/// 為 Cook QA API 打包完整食譜資訊
struct CookQARecipeContext: Codable {
    let dishName: String
    let dishDescription: String
    let ingredients: [Ingredient]
    let equipment: [Equipment]
    let recipe: [RecipeStep]

    enum CodingKeys: String, CodingKey {
        case dishName = "dish_name"
        case dishDescription = "dish_description"
        case ingredients
        case equipment
        case recipe
    }

    init(
        dishName: String,
        dishDescription: String,
        ingredients: [Ingredient],
        equipment: [Equipment],
        recipe: [RecipeStep]
    ) {
        self.dishName = dishName
        self.dishDescription = dishDescription
        self.ingredients = ingredients
        self.equipment = equipment
        self.recipe = recipe
    }

    static func fallback(dishName: String, steps: [RecipeStep]) -> CookQARecipeContext {
        let rawIngredientNames = steps
            .flatMap { $0.actions }
            .flatMap { $0.material_required }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let toolNames = steps
            .flatMap { $0.actions }
            .map { $0.tool_required }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "無" }

        let uniqueToolNames = Array(Set(toolNames))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let equipment = uniqueToolNames.map {
            Equipment(
                name: $0,
                type: "",
                size: "",
                material: "",
                power_source: ""
            )
        }

        let toolSet = Set(uniqueToolNames)
        let filteredIngredientNames = rawIngredientNames
            .filter { !toolSet.contains($0) }

        let uniqueIngredientNames = Array(Set(filteredIngredientNames))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let ingredients = uniqueIngredientNames.map {
            Ingredient(
                name: $0,
                type: "",
                amount: "",
                unit: "",
                preparation: ""
            )
        }

        let dishDescription = steps.first?.description ?? ""

        return CookQARecipeContext(
            dishName: dishName.isEmpty ? "料理" : dishName,
            dishDescription: dishDescription,
            ingredients: ingredients,
            equipment: equipment,
            recipe: steps
        )
    }
}

extension CookQARecipeContext {
    func sanitizedPromptSnippet() -> String {
        let recipeSummary = recipe.prefix(3).map { step in
            "#\(step.step_number) \(step.title): \(step.description)"
        }.joined(separator: " | ")

        let ingredientSummary = ingredients.map { $0.name }.joined(separator: ", ")
        let equipmentSummary = equipment.map { $0.name }.joined(separator: ", ")

        return "dish=\(dishName), ingredients=[\(ingredientSummary)], equipment=[\(equipmentSummary)], steps=[\(recipeSummary)]"
    }

    init?(recommendation: RecipeRecommendationResponse?) {
        guard let recommendation else { return nil }
        self.init(
            dishName: recommendation.dishName,
            dishDescription: recommendation.dishDescription,
            ingredients: recommendation.ingredients,
            equipment: recommendation.equipment,
            recipe: recommendation.recipe
        )
        CookRecipeContextRegistry.shared.register(self)
    }

    init(suggested recipe: SuggestRecipeResponse) {
        self.init(
            dishName: recipe.dish_name,
            dishDescription: recipe.dish_description,
            ingredients: recipe.ingredients,
            equipment: recipe.equipment,
            recipe: recipe.recipe
        )
        CookRecipeContextRegistry.shared.register(self)
    }
}
