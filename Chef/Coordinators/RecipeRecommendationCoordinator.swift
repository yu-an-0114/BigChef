//
//  RecipeRecommendationCoordinator.swift
//  ChefHelper
//
//  Created by Claude on 2025/9/22.
//

import UIKit
import SwiftUI

@MainActor
final class RecipeRecommendationCoordinator: Coordinator, ObservableObject {

    // MARK: - Protocol Requirements
    var childCoordinators: [Coordinator] = []
    var navigationController: UINavigationController
    weak var parentCoordinator: MainTabCoordinator?

    // MARK: - Dependencies
    private var viewModel: RecipeRecommendationViewModel?
    private var hostingController: UIHostingController<AnyView>?

    // MARK: - State Management
    private var currentRecipeResult: RecipeRecommendationResponse?  // 儲存當前食譜
    private var currentCookCoordinator: CookCoordinator?  // 儲存當前 AR Coordinator

    // MARK: - Init
    init(navigationController: UINavigationController, parentCoordinator: MainTabCoordinator? = nil) {
        self.navigationController = navigationController
        self.parentCoordinator = parentCoordinator
    }

    // MARK: - Lifecycle Methods
    func start() {
        print("🔄 RecipeRecommendationCoordinator: 啟動食譜推薦流程")

        // 創建 ViewModel 和 View
        let viewModel = RecipeRecommendationViewModel()
        self.viewModel = viewModel

        let view = RecipeRecommendationView(viewModel: viewModel, coordinator: self)

        let hostingController = UIHostingController(rootView: AnyView(view))
        self.hostingController = hostingController

        // 設置導航標題
        hostingController.title = "食譜推薦"
        hostingController.navigationItem.largeTitleDisplayMode = .automatic
        hostingController.hidesBottomBarWhenPushed = false

        navigationController.pushViewController(hostingController, animated: true)
    }

    /// 使用預填資料啟動（來自食物辨識）
    func startWithPrefillData(ingredients: [String], equipment: [String] = [], recognizedFoodName: String? = nil) {
        print("🔄 RecipeRecommendationCoordinator: 啟動食譜推薦流程（預填資料）")
        print("   辨識食物：\(recognizedFoodName ?? "基於食材推薦")")

        // 創建 ViewModel 和 View
        let viewModel = RecipeRecommendationViewModel()
        self.viewModel = viewModel

        // 預填資料，包含辨識食物名稱
        viewModel.prefillFromRecognition(
            ingredients: ingredients,
            equipment: equipment,
            recognizedFoodName: recognizedFoodName
        )

        let view = RecipeRecommendationView(viewModel: viewModel, coordinator: self)

        let hostingController = UIHostingController(rootView: AnyView(view))
        self.hostingController = hostingController

        // 根據是否有辨識食物調整標題
        let title = recognizedFoodName != nil ? "製作 \(recognizedFoodName!)" : "食譜推薦"
        hostingController.title = title
        hostingController.navigationItem.largeTitleDisplayMode = .automatic
        hostingController.hidesBottomBarWhenPushed = false

        navigationController.pushViewController(hostingController, animated: true)
    }

    func stop() {
        print("🛑 RecipeRecommendationCoordinator: 停止食譜推薦流程")

        // 清理資源
        viewModel = nil
        hostingController = nil

        // 清除所有子協調器
        childCoordinators.removeAll()
    }

    func restart() {
        print("🔄 RecipeRecommendationCoordinator: 重新啟動食譜推薦流程")
        stop()
        start()
    }

    // MARK: - Navigation Methods

    /// 顯示食譜詳細信息
    func showRecipeDetail(_ recipe: RecipeRecommendationResponse) {
        print("📄 RecipeRecommendationCoordinator: 顯示食譜詳細信息 - \(recipe.dishName)")

        // ⚠️ 檢查是否有舊的食譜，如果有則清除相關資源
        if let oldRecipe = currentRecipeResult {
            print("🗑️ RecipeRecommendationCoordinator: 偵測到舊食譜，準備覆蓋")
            print("   舊食譜：\(oldRecipe.dishName)")
            clearOldRecipeResources()
        }

        // 儲存新食譜
        currentRecipeResult = recipe
        print("✅ RecipeRecommendationCoordinator: 新食譜已儲存 - \(recipe.dishName)")

        let detailView = RecipeDetailView(
            recommendationResult: recipe,
            showNavigationBar: false,  // 使用系統導航欄，保持 tab bar 顯示
            onStartCooking: { [weak self] in
                self?.startARCooking(with: recipe.recipe, dishName: recipe.dishName)
            },
            onBack: { [weak self] in
                self?.goBack()
            },
            onFavorite: {
                // TODO: Implement favorite functionality
                print("❤️ 收藏食譜：\(recipe.dishName)")
            }
        )

        let hostingController = UIHostingController(rootView: detailView)
        hostingController.title = recipe.dishName
        hostingController.navigationItem.largeTitleDisplayMode = .never
        hostingController.hidesBottomBarWhenPushed = false

        navigationController.pushViewController(hostingController, animated: true)
    }

    /// 顯示食譜推薦結果的詳細頁面
    func showRecommendationDetail(_ result: RecipeRecommendationResponse) {
        print("📋 RecipeRecommendationCoordinator: 顯示推薦結果詳細頁面")
        showRecipeDetail(result)
    }

    /// 啟動 AR 烹飪模式
    func startARCooking(with steps: [RecipeStep], dishName: String = "料理") {
        print("🥽 RecipeRecommendationCoordinator: 啟動 AR 烹飪模式 - \(dishName)")

        // 生成推薦 tab 的食譜 ID
        let recipeID = "recommendation_\(dishName)"
        print("📌 RecipeRecommendationCoordinator: 推薦食譜 ID - \(recipeID)")

        let recipeContext = CookQARecipeContext(recommendation: currentRecipeResult)

        let cookCoordinator = CookCoordinator(
            navigationController: navigationController,
            parentCoordinator: self
        )
        cookCoordinator.onComplete = { [weak self] in
            // 烹飪完成後，返回到首頁（tab bar 的根頁面）
            self?.navigationController.popToRootViewController(animated: true)

            // 清除 AR Coordinator 引用
            self?.currentCookCoordinator = nil
        }

        // 儲存當前 CookCoordinator
        currentCookCoordinator = cookCoordinator

        childCoordinators.append(cookCoordinator)
        cookCoordinator.start(
            with: steps,
            dishName: dishName,
            recipeContext: recipeContext
        )

        print("⚠️ AR 動畫註冊將在首次載入時自動完成（食譜ID: \(recipeID)）")
    }

    /// 清除舊食譜的 AR 快取資源（選擇性清除，不影響辨識 tab）
    private func clearOldRecipeResources() {
        guard let oldRecipe = currentRecipeResult else {
            print("ℹ️ RecipeRecommendationCoordinator: 沒有舊食譜需要清除")
            return
        }

        print("🧹 RecipeRecommendationCoordinator: 開始清除舊食譜資源")
        print("   舊食譜 ID: \(oldRecipe.dishName)")

        // 1. 清除舊的 CookCoordinator（如果還在運行）
        if let oldCookCoordinator = currentCookCoordinator {
            print("   - 移除舊的 CookCoordinator")
            removeChildCoordinator(oldCookCoordinator)
            currentCookCoordinator = nil
        }

        // 2. ✅ 只清除此食譜的 AR 動畫快取（不影響辨識 tab）
        print("   - 清除推薦 tab 食譜的 AR 動畫快取")
        let recipeID = "recommendation_\(oldRecipe.dishName)"  // 推薦 tab 前綴
        AnimationModelCache.clearAnimations(forRecipe: recipeID)

        // 3. 清除舊食譜引用
        currentRecipeResult = nil

        print("✅ RecipeRecommendationCoordinator: 舊食譜資源清除完成（辨識 tab 快取保留）")
    }

    /// 顯示錯誤提示
    func showError(_ error: Error) {
        print("❌ RecipeRecommendationCoordinator: 顯示錯誤提示：\(error)")

        let alert = UIAlertController(
            title: "錯誤",
            message: error.localizedDescription,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "確定", style: .default))

        DispatchQueue.main.async { [weak self] in
            self?.navigationController.present(alert, animated: true)
        }
    }

    /// 顯示成功提示
    func showSuccess(message: String) {
        print("✅ RecipeRecommendationCoordinator: 顯示成功提示：\(message)")

        let alert = UIAlertController(
            title: "成功",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "確定", style: .default))

        DispatchQueue.main.async { [weak self] in
            self?.navigationController.present(alert, animated: true)
        }
    }

    /// 導航到首頁
    func navigateToHome() {
        print("🏠 RecipeRecommendationCoordinator: 導航到首頁")
        navigationController.popToRootViewController(animated: true)
    }

    /// 導航回上一個頁面
    func goBack() {
        print("⬅️ RecipeRecommendationCoordinator: 導航回上一個頁面")
        navigationController.popViewController(animated: true)
    }

    func handleLogout() {
        print("RecipeRecommendationCoordinator: 開始處理登出")

        // 清除所有子協調器
        print("RecipeRecommendationCoordinator: 清除子協調器")
        childCoordinators.removeAll()

        // 通知父協調器處理登出
        if let parentCoordinator = parentCoordinator {
            print("RecipeRecommendationCoordinator: 找到父協調器，通知處理登出")
            parentCoordinator.handleLogout()
        } else {
            print("RecipeRecommendationCoordinator: 錯誤 - 父協調器為空")
        }
    }
}
