////
////  RecipeCoordinator.swift
////  ChefHelper
////
////  Created by 陳泓齊 on 2025/5/4.
////
//
//import SwiftUI
//
//final class RecipeCoordinator: Coordinator {
//    var childCoordinators: [Coordinator] = []
//    private unowned let nav: UINavigationController
//    func start() {fatalError("Use start(with:) instead.") }
//    //MARK: - Init
//    init(nav: UINavigationController) {
//        self.nav = nav
//    }
//    //MARK: - Start
//    func start(with response: SuggestRecipeResponse) {
//        print("📦 RecipeCoordinator - start \(response.dish_name)")
//        let vm = RecipeViewModel(response: response)
//        print("📦 RecipeCoordinator - pushing RecipeView1")
//        // ① 設定 callback
//        vm.onCookRequested = { [weak self] in
//            guard let self else { return }
//            let camera = CameraCoordinator(nav: self.nav)
//            self.childCoordinators.append(camera)
//            camera.onFinish = { [weak self, weak camera] in
//                guard let self, let camera else { return }
//                self.childCoordinators.removeAll { $0 === camera }
//            }
//            camera.start(with: response.recipe) // push camera with all steps
//        }
//        print("📦 RecipeCoordinator - pushing RecipeView")
//        let page = UIHostingController(rootView: RecipeView(viewModel: vm))
//        nav.pushViewController(page, animated: true)
//    }
//
//}

import SwiftUI

@MainActor
final class RecipeCoordinator: Coordinator, ObservableObject {
    var childCoordinators: [Coordinator] = []
    var navigationController: UINavigationController
    
    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }
    
    func start() {
        // 創建一個空的食譜列表視圖
        let viewModel = RecipeViewModel(response: SuggestRecipeResponse(
            dish_name: "",
            dish_description: "",
            ingredients: [],
            equipment: [],
            recipe: []
        ))
        pushRecipeView(with: viewModel)
    }
    
    func showRecipeDetail(_ recipe: SuggestRecipeResponse) {
        let viewModel = RecipeViewModel(response: recipe)
        viewModel.onCookRequested = { [weak self] in
            self?.startCooking(
                with: recipe.recipe,
                dishName: recipe.dish_name,
                recipeContext: CookQARecipeContext(suggested: recipe)
            )
        }
        viewModel.onBackRequested = { [weak self] in
            self?.navigationController.popViewController(animated: true)
        }
        pushRecipeView(with: viewModel)
    }

    func showRecipeDetail(_ recipe: Recipe) {
        // 使用新的RecipeDetailView，通過食物名稱來獲取詳細資料
        let detailView = RecipeDetailViewNew(recipeName: recipe.displayName)
        let hostingController = UIHostingController(rootView: detailView)
        hostingController.hidesBottomBarWhenPushed = false
        navigationController.pushViewController(hostingController, animated: true)
        print("顯示食譜詳情: \(recipe.displayName)")
    }
    
    func showRecipeEdit(_ recipe: SuggestRecipeResponse) {
        let viewModel = RecipeViewModel(response: recipe)
        viewModel.onBackRequested = { [weak self] in
            self?.navigationController.popViewController(animated: true)
        }
        pushRecipeView(with: viewModel)
    }

    func showCamera() {
        let coordinator = CameraCoordinator(navigationController: navigationController)
        addChildCoordinator(coordinator)
        coordinator.start()
    }
    
    // MARK: - Private Helpers
    
    private func pushRecipeView(with viewModel: RecipeViewModel) {
        let view = RecipeView(viewModel: viewModel)
            .environmentObject(self)
        let hostingController = UIHostingController(rootView: view)
        hostingController.hidesBottomBarWhenPushed = false
        navigationController.pushViewController(hostingController, animated: true)
    }
    
    private func startCooking(
        with steps: [RecipeStep],
        dishName: String = "料理",
        recipeContext: CookQARecipeContext? = nil
    ) {
        let coordinator = CookCoordinator(
            navigationController: navigationController,
            parentCoordinator: self
        )
        coordinator.onComplete = { [weak self] in
            // 烹飪完成後，返回到首頁（tab bar 的根頁面）
            self?.navigationController.popToRootViewController(animated: true)
        }
        addChildCoordinator(coordinator)
        coordinator.start(
            with: steps,
            dishName: dishName,
            recipeContext: recipeContext
        )
    }
}
