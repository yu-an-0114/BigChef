//
//  IngredientConfirmationView.swift
//  ChefHelper
//
//  Created by Claude on 2025/9/27.
//

import SwiftUI

struct IngredientConfirmationView: View {
    @EnvironmentObject private var viewModel: IngredientConfirmationViewModel
    @EnvironmentObject private var coordinator: FoodRecognitionCoordinator

    let recognitionResult: FoodRecognitionResponse
    let onConfirm: ([String], [String]) -> Void
    let onCancel: () -> Void

    @State private var showingAddIngredientOptions = false
    @State private var showingAddEquipmentOptions = false
    @State private var showingIngredientScan = false
    @State private var showingEquipmentScan = false

    var body: some View {
        Group {
            switch viewModel.generationState {
            case .configuring:
                configurationView
            case .loading:
                loadingView
            case .success(let result):
                successView(result)
            case .error(let error):
                errorView(error)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if case .configuring = viewModel.generationState {
                    Button("取消") {
                        onCancel()
                    }
                }
            }
        }
        .sheet(isPresented: $showingIngredientScan) {
            IngredientScanView(scanMode: .ingredientOnly) { ingredients, equipment in
                // 只加入食材
                for ingredient in ingredients {
                    viewModel.addScannedIngredient(ingredient.name)
                }
            }
        }
        .sheet(isPresented: $showingEquipmentScan) {
            IngredientScanView(scanMode: .equipmentOnly) { ingredients, equipment in
                // 只加入器具
                for equip in equipment {
                    viewModel.addScannedEquipment(equip.name)
                }
            }
        }
    }

    private var navigationTitle: String {
        switch viewModel.generationState {
        case .configuring:
            return "確認食材器具"
        case .loading:
            return "生成食譜中"
        case .success:
            return "食譜生成完成"
        case .error:
            return "生成失敗"
        }
    }

    private var configurationView: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                ingredientsSection
                equipmentSection
                actionButtons
            }
            .padding()
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("辨識完成")
                .font(.title2)
                .fontWeight(.bold)

            // 顯示辨識出的食物名稱
            if let primaryFood = recognitionResult.recognizedFoods.first {
                RecognizedFoodNameSection(
                    foodName: primaryFood.name,
                    description: primaryFood.description
                )
            }

            Text("請確認下方的食材和器具，您可以調整選擇或新增項目")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Ingredients Section
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("食材")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Menu {
                    Button("全選") {
                        viewModel.selectAllIngredients()
                    }
                    Button("全不選") {
                        viewModel.deselectAllIngredients()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.blue)
                }
            }

            if !viewModel.recognizedIngredients.isEmpty {
                Text("辨識到的食材")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(viewModel.recognizedIngredients, id: \.id) { ingredient in
                    EditableIngredientRow(
                        name: ingredient.name,
                        type: ingredient.type,
                        isSelected: viewModel.selectedIngredients.contains(ingredient.name),
                        onToggle: {
                            viewModel.toggleIngredientSelection(ingredient.name)
                        },
                        onEdit: { newName in
                            viewModel.updateIngredientName(oldName: ingredient.name, newName: newName)
                        },
                        onDelete: {
                            viewModel.removeRecognizedIngredient(ingredient.name)
                        }
                    )
                }
            }

            if !viewModel.customIngredients.isEmpty {
                Text("自訂食材")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(Array(viewModel.customIngredients.enumerated()), id: \.offset) { index, ingredient in
                    EditableCustomItemRow(
                        name: ingredient,
                        onEdit: { newName in
                            viewModel.updateIngredientName(oldName: ingredient, newName: newName)
                        },
                        onDelete: {
                            viewModel.removeCustomIngredient(at: index)
                        }
                    )
                }
            }

            addIngredientField
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    private var addIngredientField: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("手動輸入食材", text: $viewModel.newIngredientName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        viewModel.addCustomIngredient()
                    }

                Button(action: {
                    viewModel.addCustomIngredient()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(viewModel.newIngredientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button(action: {
                showingIngredientScan = true
            }) {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("掃描新增食材")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.brandOrange.opacity(0.1))
                .foregroundColor(.brandOrange)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Equipment Section
    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("器具")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Menu {
                    Button("全選") {
                        viewModel.selectAllEquipment()
                    }
                    Button("全不選") {
                        viewModel.deselectAllEquipment()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.blue)
                }
            }

            if !viewModel.recognizedEquipment.isEmpty {
                Text("辨識到的器具")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(viewModel.recognizedEquipment, id: \.id) { equipment in
                    EditableEquipmentRow(
                        name: equipment.name,
                        type: equipment.type,
                        isSelected: viewModel.selectedEquipment.contains(equipment.name),
                        onToggle: {
                            viewModel.toggleEquipmentSelection(equipment.name)
                        },
                        onEdit: { newName in
                            viewModel.updateEquipmentName(oldName: equipment.name, newName: newName)
                        },
                        onDelete: {
                            viewModel.removeRecognizedEquipment(equipment.name)
                        }
                    )
                }
            }

            if !viewModel.customEquipment.isEmpty {
                Text("自訂器具")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(Array(viewModel.customEquipment.enumerated()), id: \.offset) { index, equipment in
                    EditableCustomItemRow(
                        name: equipment,
                        onEdit: { newName in
                            viewModel.updateEquipmentName(oldName: equipment, newName: newName)
                        },
                        onDelete: {
                            viewModel.removeCustomEquipment(at: index)
                        }
                    )
                }
            }

            addEquipmentField
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    private var addEquipmentField: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("手動輸入器具", text: $viewModel.newEquipmentName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        viewModel.addCustomEquipment()
                    }

                Button(action: {
                    viewModel.addCustomEquipment()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(viewModel.newEquipmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button(action: {
                showingEquipmentScan = true
            }) {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("掃描新增器具")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.brandOrange.opacity(0.1))
                .foregroundColor(.brandOrange)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                Task {
                    await viewModel.generateRecipe()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("確認並生成食譜")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(viewModel.canProceed ? Color.blue : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!viewModel.canProceed)

            Text("已選擇 \(viewModel.totalSelectedIngredients.count) 項食材，\(viewModel.totalSelectedEquipment.count) 項器具")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        RecommendationLoadingView(onCancel: {
            viewModel.cancelGeneration()
        })
    }

    // MARK: - Success View
    private func successView(_ result: RecipeRecommendationResponse) -> some View {
        RecipeDetailView(
            recommendationResult: result,
            showNavigationBar: false,
            onStartCooking: {
                coordinator.startARCooking(with: result.recipe, dishName: result.dishName)
            },
            onBack: {
                viewModel.backToConfiguration()
            },
            onFavorite: {
                print("❤️ 收藏食譜：\(result.dishName)")
            }
        )
    }

    // MARK: - Error View
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("食譜生成失敗")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await viewModel.retryGeneration()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("重試")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }

                Button(action: {
                    viewModel.backToConfiguration()
                }) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("返回修改")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Supporting Views

struct IngredientCard: View {
    let name: String
    let type: String
    let confidence: Double
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                }

                Text(type)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("信心度")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(confidence * 100))%")
                        .font(.caption2)
                        .foregroundColor(confidence > 0.8 ? .green : confidence > 0.6 ? .orange : .red)
                }
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EquipmentCard: View {
    let name: String
    let type: String
    let confidence: Double
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                }

                Text(type)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("信心度")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(confidence * 100))%")
                        .font(.caption2)
                        .foregroundColor(confidence > 0.8 ? .green : confidence > 0.6 ? .orange : .red)
                }
            }
            .padding(12)
            .background(isSelected ? Color.orange.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Editable Item Components

struct EditableIngredientRow: View {
    let name: String
    let type: String
    let isSelected: Bool
    let onToggle: () -> Void
    let onEdit: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editedName: String = ""

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title3)
            }

            // Content
            if isEditing {
                TextField("食材名稱", text: $editedName, onCommit: {
                    if !editedName.isEmpty {
                        onEdit(editedName)
                    }
                    isEditing = false
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(type)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action buttons
            if !isEditing {
                Button(action: {
                    editedName = name
                    isEditing = true
                }) {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.blue)
                        .font(.title3)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct EditableEquipmentRow: View {
    let name: String
    let type: String
    let isSelected: Bool
    let onToggle: () -> Void
    let onEdit: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editedName: String = ""

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .orange : .gray)
                    .font(.title3)
            }

            // Content
            if isEditing {
                TextField("器具名稱", text: $editedName, onCommit: {
                    if !editedName.isEmpty {
                        onEdit(editedName)
                    }
                    isEditing = false
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(type)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action buttons
            if !isEditing {
                Button(action: {
                    editedName = name
                    isEditing = true
                }) {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.blue)
                        .font(.title3)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct EditableCustomItemRow: View {
    let name: String
    let onEdit: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editedName: String = ""

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("名稱", text: $editedName, onCommit: {
                    if !editedName.isEmpty {
                        onEdit(editedName)
                    }
                    isEditing = false
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                Text(name)
                    .font(.body)
                    .foregroundColor(.primary)
            }

            Spacer()

            if !isEditing {
                Button(action: {
                    editedName = name
                    isEditing = true
                }) {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.blue)
                        .font(.title3)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Supporting Views

struct RecognizedFoodNameSection: View {
    let foodName: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "camera.viewfinder")
                    .foregroundColor(.blue)
                Text("辨識結果")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            VStack(spacing: 4) {
                HStack {
                    Text("我們辨識出這是：")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Text(foodName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                if !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("我們將為您生成 \(foodName) 的製作食譜")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    IngredientConfirmationView(
        recognitionResult: FoodRecognitionResponse(
            recognizedFoods: [
                RecognizedFood(
                    name: "番茄炒蛋",
                    description: "一道經典的家常菜",
                    possibleIngredients: [
                        PossibleIngredient(name: "番茄", type: "蔬菜"),
                        PossibleIngredient(name: "雞蛋", type: "蛋類")
                    ],
                    possibleEquipment: [
                        PossibleEquipment(name: "平底鍋", type: "鍋具")
                    ]
                )
            ]
        ),
        onConfirm: { _, _ in },
        onCancel: { }
    )
    .environmentObject(FoodRecognitionCoordinator(navigationController: UINavigationController()))
}