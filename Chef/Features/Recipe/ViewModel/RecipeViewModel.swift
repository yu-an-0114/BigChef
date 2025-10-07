
//
//  RecipeViewModel.swift
//  ChefHelper
//
//  Created by 陳泓齊 on 2025/5/4.
//

import Foundation

// RecipeViewModel.swift
final class RecipeViewModel: ObservableObject {
    let dishName: String
    let dishDescription: String
    let ingredients: [Ingredient]
    let equipment: [Equipment]
    let steps: [RecipeStep]
    var onCookRequested: (() -> Void)?
    var onBackRequested: (() -> Void)?

    init(response: SuggestRecipeResponse) {

        print("🧩 進入 RecipeViewModel init，開始解構 response")

        let context = CookQARecipeContext(suggested: response)

        self.dishName = context.dishName
        print("✅ dishName 設定完成：\(dishName)")

        self.dishDescription = context.dishDescription
        self.ingredients = context.ingredients
        self.equipment = context.equipment
        self.steps = context.recipe
    }
    func cookButtonTapped() {
        print("🍳 cookButtonTapped 被觸發")
        onCookRequested?()
    }

    func backButtonTapped() {
        print("⬅️ backButtonTapped 被觸發")
        onBackRequested?()
    }
}
