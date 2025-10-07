//
//  CookViewController.swift
//  ChefHelper
//
//  Created by 陳泓齊 on 2025/5/7.
//


import UIKit
import SwiftUI
import AVFoundation
import Vision
import SceneKit
/// 「開始烹飪」AR 流程 —— 加入手勢辨識
final class CookViewController: UIViewController, ARGestureDelegate, UIGestureRecognizerDelegate {

    // MARK: - AR Session
    private let gestureSession = ARSessionAdapter()

    // MARK: - Data
    private let steps: [RecipeStep]
    private let stepViewModel = StepViewModel()
    private var currentIndex = 0 {
        didSet {
            print("🔄 [CookViewController] currentIndex changed: \(oldValue) -> \(currentIndex)")
            updateStepLabel()
            stepViewModel.currentDescription = steps[currentIndex].description

            // 🔄 更新 stepViewModel 的當前步驟，讓 SwiftUI 自動重新創建 CookingARView
            print("📝 [CookViewController] 更新 stepViewModel.currentStepModel to step \(steps[currentIndex].step_number)")
            stepViewModel.currentStepModel = steps[currentIndex]
        }
    }

    // MARK: - UI
    private let stepLabel = UILabel()
    private let prevBtn   = UIButton(type: .system)
    private let nextBtn   = UIButton(type: .system)
    private let completeBtn = UIButton(type: .system)
    private let qaModelView = SCNView()
    private var qaTapRecognizer: UITapGestureRecognizer?
    private var qaBubbleView: QASpeechBubbleView?
    private var qaInputBubbleView: QAInputBubbleView?
    private var qaBubbleDismissTap: UITapGestureRecognizer?
    private var pendingDraftQuestion: String = ""

    // 手勢狀態 UI
    private let gestureStatusLabel = UILabel()
    private let hoverProgressView  = UIProgressView()

    private var arContainer: UIHostingController<CookingARViewWrapper>!
    private var stepBinding: Binding<String>!
    private let qaService = CookQAService.shared
    private let qaRecipeContext: CookQARecipeContext?

    // 菜名（用於完成頁面）
    private var dishName: String = "料理"

    // 完成回調
    private var onComplete: (() -> Void)?

    // MARK: - Init
    init(
        steps: [RecipeStep],
        dishName: String = "料理",
        recipeContext: CookQARecipeContext? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.steps = steps
        self.dishName = dishName
        self.qaRecipeContext = recipeContext
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Cleanup
    private func cleanupARContainer() {
        print("🧹 [CookViewController.cleanupARContainer] 開始")
        guard arContainer != nil else {
            print("⚠️ [CookViewController.cleanupARContainer] arContainer 已經是 nil")
            return
        }

        // ✅ 先清空 stepViewModel 以中斷 SwiftUI 的引用鏈
        print("🧹 [CookViewController.cleanupARContainer] 清空 stepViewModel")
        stepViewModel.currentStepModel = nil
        stepViewModel.currentDescription = ""

        // 清空 stepBinding
        stepBinding = nil

        // 手動觸發 SwiftUI 的清理
        arContainer?.willMove(toParent: nil)
        arContainer?.view.removeFromSuperview()
        arContainer?.removeFromParent()
        arContainer = nil

        print("✅ [CookViewController.cleanupARContainer] 完成")
    }

    deinit {
        print("🧹 [CookViewController] deinit - 開始清理資源 (dishName: \(dishName))")

        // 確保 AR container 被清理
        cleanupARContainer()

        // 清理 gesture session
        gestureSession.removeGestureDelegate(self)
        gestureSession.setGestureEnabled(false)
        gestureSession.stop()

        print("🧹 [CookViewController] deinit - 完成")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        stepViewModel.currentDescription = steps[currentIndex].description
        stepViewModel.currentStepModel = steps[currentIndex]
        updateStepLabel()
        // ⚠️ 使用 [weak self] 避免循環引用
        stepBinding = Binding<String>(
            get: { [weak self] in
                self?.stepViewModel.currentDescription ?? ""
            },
            set: { [weak self] newValue in
                self?.stepViewModel.currentDescription = newValue
            }
        )

        // ✅ 使用 stepViewModel 來動態更新 CookingARView
        arContainer = UIHostingController(
            rootView: CookingARViewWrapper(
                stepViewModel: stepViewModel,
                sessionAdapter: gestureSession
            )
        )
        addChild(arContainer)
        arContainer.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(arContainer.view)



        NSLayoutConstraint.activate([
            arContainer.view.topAnchor.constraint(equalTo: view.topAnchor),
            arContainer.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            arContainer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arContainer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        arContainer.didMove(toParent: self)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            //print("📏 AR Container frame = \(self.arContainer.view.frame)")
        }
        // ▲ Step Label
        stepLabel.numberOfLines = 0
        stepLabel.textColor = .white
        stepLabel.font = .preferredFont(forTextStyle: .headline)
        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stepLabel)
        setupQAInteractionView()

        // ▼ Prev / Next / Complete Buttons
        let navigationStack = UIStackView(arrangedSubviews: [prevBtn, nextBtn])
        navigationStack.axis = .horizontal
        navigationStack.spacing = 40
        navigationStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationStack)

        prevBtn.setTitle("〈 上一步", for: .normal)
        nextBtn.setTitle("下一步 〉", for: .normal)
        prevBtn.addTarget(self, action: #selector(prevStep), for: .touchUpInside)
        nextBtn.addTarget(self, action: #selector(nextStep), for: .touchUpInside)

        // 完成按鈕設置
        completeBtn.setTitle("✓ 完成", for: .normal)
        completeBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        completeBtn.backgroundColor = UIColor(named: "BrandOrange") ?? .systemOrange
        completeBtn.setTitleColor(.white, for: .normal)
        completeBtn.layer.cornerRadius = 12
        completeBtn.translatesAutoresizingMaskIntoConstraints = false
        completeBtn.addTarget(self, action: #selector(completeRecipe), for: .touchUpInside)
        completeBtn.isHidden = true
        view.addSubview(completeBtn)

        // 設定手勢狀態 UI
        setupGestureStatusUI()

        NSLayoutConstraint.activate([
            stepLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stepLabel.trailingAnchor.constraint(equalTo: qaModelView.leadingAnchor, constant: -12),
            stepLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            qaModelView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            qaModelView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            qaModelView.widthAnchor.constraint(equalToConstant: 56),
            qaModelView.heightAnchor.constraint(equalToConstant: 56),

            gestureStatusLabel.topAnchor.constraint(equalTo: stepLabel.bottomAnchor, constant: 8),
            gestureStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            gestureStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            gestureStatusLabel.heightAnchor.constraint(equalToConstant: 30),

            hoverProgressView.topAnchor.constraint(equalTo: gestureStatusLabel.bottomAnchor, constant: 4),
            hoverProgressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hoverProgressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            hoverProgressView.heightAnchor.constraint(equalToConstant: 4),

            navigationStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            navigationStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),

            completeBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            completeBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            completeBtn.widthAnchor.constraint(equalToConstant: 200),
            completeBtn.heightAnchor.constraint(equalToConstant: 50)
        ])

        updateStepLabel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // ✅ 先註冊 delegate 和啟用，再啟動 session
        gestureSession.addGestureDelegate(self)
        gestureSession.setGestureEnabled(true)
        gestureSession.start()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("📸 View Did Appear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("👋 [CookViewController] viewWillDisappear - isBeingDismissed=\(isBeingDismissed), isMovingFromParent=\(isMovingFromParent)")
        print("👋 [CookViewController] viewWillDisappear - navigationController.viewControllers.count=\(navigationController?.viewControllers.count ?? -1)")
        print("👋 [CookViewController] viewWillDisappear - parent=\(parent != nil)")

        dismissQABubble(animated: false)

        // 移除 delegate 並停用手勢辨識
        gestureSession.removeGestureDelegate(self)
        gestureSession.setGestureEnabled(false)
        gestureSession.stop()

        // ✅ 如果正在被移除（pop），立即清理 arContainer
        if isMovingFromParent {
            print("🧹 [CookViewController] 即將被 pop，開始清理 arContainer")
            cleanupARContainer()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        print("💤 [CookViewController] viewDidDisappear - isBeingDismissed=\(isBeingDismissed), isMovingFromParent=\(isMovingFromParent)")
        print("💤 [CookViewController] viewDidDisappear - navigationController.viewControllers.count=\(navigationController?.viewControllers.count ?? -1)")
        print("💤 [CookViewController] viewDidDisappear - parent=\(parent != nil)")

        // 🔍 檢查是否有任何強引用仍在保持這個 VC
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self != nil {
                print("⚠️ [CookViewController] 2 秒後仍未被釋放！存在記憶體洩漏")
            } else {
                print("✅ [CookViewController] 已成功釋放")
            }
        }
    }

    // MARK: - Helpers

    private func updateStepLabel() {
        guard !steps.isEmpty else { stepLabel.text = "無步驟"; return }
        let step = steps[currentIndex]
        stepLabel.text = "步驟 \(step.step_number)：\(step.title)\n\(step.description)"
        prevBtn.isEnabled = currentIndex > 0
        nextBtn.isEnabled = currentIndex < steps.count - 1

        // 判斷是否為最後一步
        let isLastStep = currentIndex == steps.count - 1
        completeBtn.isHidden = !isLastStep
        nextBtn.isHidden = isLastStep
    }

    @objc private func prevStep() {
        guard currentIndex > 0 else { return }
        print("⬅️ [CookViewController] prevStep: \(currentIndex) -> \(currentIndex - 1)")
        currentIndex -= 1
    }

    @objc private func nextStep() {
        guard currentIndex < steps.count - 1 else { return }
        print("➡️ [CookViewController] nextStep: \(currentIndex) -> \(currentIndex + 1)")
        currentIndex += 1
    }

    @objc private func completeRecipe() {
        // 顯示完成頁面
        let completionView = RecipeCompletionView(
            dishName: dishName,
            totalSteps: steps.count
        ) { [weak self] in
            guard let self = self else { return }

            // 先關閉 modal 完成頁面
            self.dismiss(animated: true) { [weak self] in
                guard let self = self else { return }

                // 呼叫完成回調，通知 coordinator 處理返回首頁邏輯
                self.onComplete?()
            }
        }

        let hostingController = UIHostingController(rootView: completionView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }

    private func setupQAInteractionView() {
        qaModelView.translatesAutoresizingMaskIntoConstraints = false
        qaModelView.backgroundColor = .clear
        qaModelView.scene = SCNScene()
        qaModelView.autoenablesDefaultLighting = true
        qaModelView.allowsCameraControl = false
        qaModelView.isUserInteractionEnabled = true
        qaModelView.accessibilityLabel = "烹飪求助"

        let tap = UITapGestureRecognizer(target: self, action: #selector(askCookQuestionTapped))
        qaModelView.addGestureRecognizer(tap)
        qaTapRecognizer = tap

        view.addSubview(qaModelView)
        loadQAInteractionModel()
        setQAInteractionEnabled(true)
    }

    private func loadQAInteractionModel() {
        guard let url = Bundle.main.url(forResource: "ingredient", withExtension: "usdz") else {
            return
        }

        do {
            let scene = try SCNScene(url: url, options: nil)
            qaModelView.scene = scene
            qaModelView.scene?.background.contents = UIColor.clear
            qaModelView.pointOfView = makeQAInteractionCameraIfNeeded(for: scene)
        } catch {
            print("⚠️ [CookViewController] 無法載入 ingredient.usdz: \(error)")
        }
    }

    private func makeQAInteractionCameraIfNeeded(for scene: SCNScene) -> SCNNode? {
        if let cameraNode = scene.rootNode.childNodes.first(where: { $0.camera != nil }) {
            return cameraNode
        }

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 2.5)
        scene.rootNode.addChildNode(cameraNode)
        return cameraNode
    }

    private func setQAInteractionEnabled(_ enabled: Bool) {
        qaModelView.isUserInteractionEnabled = enabled
        qaModelView.alpha = enabled ? 1.0 : 0.5
    }

    private func dismissQABubble(animated: Bool = true, persistDraft: Bool = true) {
        let answerBubble = qaBubbleView
        let inputBubble = qaInputBubbleView
        guard answerBubble != nil || inputBubble != nil else { return }

        qaBubbleView = nil
        qaInputBubbleView = nil

        let viewsToDismiss = [answerBubble, inputBubble].compactMap { $0 }

        let animations = {
            viewsToDismiss.forEach { view in
                view.alpha = 0
                view.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            }
        }

        let completion: (Bool) -> Void = { [weak self] _ in
            if let input = inputBubble {
                input.resignFocus()
                if persistDraft {
                    self?.pendingDraftQuestion = input.currentDraftText()
                }
            }
            viewsToDismiss.forEach { $0.removeFromSuperview() }
            self?.removeBubbleDismissGesture()
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
        if !persistDraft {
            pendingDraftQuestion = ""
        }
    }

    private func installBubbleDismissGestureIfNeeded() {
        guard qaBubbleDismissTap == nil else { return }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTapped))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
        qaBubbleDismissTap = recognizer
    }

    private func removeBubbleDismissGesture() {
        guard let recognizer = qaBubbleDismissTap else { return }
        view.removeGestureRecognizer(recognizer)
        qaBubbleDismissTap = nil
    }

    @objc private func askCookQuestionTapped() {
        guard !steps.isEmpty else { return }
        showQAInputBubble()
    }

    private func submitCookQuestion(_ question: String) {
        let description = steps[currentIndex].description

        guard let screenshot = captureARScreenshot() else {
            presentQAError(message: "目前無法擷取相機畫面，請稍後再試。")
            return
        }

        dismissQABubble(persistDraft: false)

        guard let base64Image = ImageCompressor.compressToBase64(image: screenshot) else {
            presentQAError(message: "圖片處理失敗，請稍後再試。")
            return
        }

        setQAInteractionEnabled(false)

        let registryContext = CookRecipeContextRegistry.shared.context(matching: steps)
        let effectiveRecipeContext: CookQARecipeContext = qaRecipeContext
            ?? registryContext
            ?? CookQARecipeContext.fallback(
                dishName: dishName,
                steps: steps
            )

        print("📨 [CookQA] 發送問題")
        print("    • Question: \(question)")
        print("    • Step description: \(description)")
        print("    • Has recipe context: \(qaRecipeContext != nil)")
        print("    • Registry context matched: \(registryContext != nil)")
        print("    • Recipe prompt: \(effectiveRecipeContext.sanitizedPromptSnippet())")

        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await qaService.askCookAssistant(
                    question: question,
                    stepDescription: description,
                    base64Image: base64Image,
                    recipeContext: effectiveRecipeContext
                )

                await MainActor.run { [weak self] in
                    self?.setQAInteractionEnabled(true)
                    self?.presentQAAnswer(response.answer)
                }
                print("✅ [CookQA] 成功取得回覆")
            } catch {
                let message: String
                if let error = error as? CookQAServiceError {
                    message = error.errorDescription ?? "發生未知錯誤"
                } else {
                    message = error.localizedDescription
                }

                print("❌ [CookQA] 發送失敗 - \(message)")

                await MainActor.run { [weak self] in
                    self?.setQAInteractionEnabled(true)
                    self?.presentQAError(message: message)
                }
            }
        }
    }

    private func captureARScreenshot() -> UIImage? {
        guard let containerView = arContainer?.view else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: containerView.bounds)
        return renderer.image { _ in
            containerView.drawHierarchy(in: containerView.bounds, afterScreenUpdates: true)
        }
    }

    private func showQAInputBubble() {
        dismissQABubble(animated: false)

        let bubble = QAInputBubbleView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.alpha = 0
        bubble.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)

        bubble.onSubmit = { [weak self, weak bubble] text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                bubble?.showValidationError("請輸入想詢問的問題內容。")
                return
            }
            self?.submitCookQuestion(trimmed)
        }

        view.addSubview(bubble)
        qaInputBubbleView = bubble
        installBubbleDismissGestureIfNeeded()

        let constraints = [
            bubble.trailingAnchor.constraint(equalTo: qaModelView.leadingAnchor, constant: -12),
            bubble.centerYAnchor.constraint(equalTo: qaModelView.centerYAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16)
        ]
        constraints.last?.priority = .defaultHigh
        NSLayoutConstraint.activate(constraints)

        view.layoutIfNeeded()

        bubble.setDraftText(pendingDraftQuestion)

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.75,
            initialSpringVelocity: 0.6,
            options: [.curveEaseOut]
        ) {
            bubble.alpha = 1
            bubble.transform = .identity
        } completion: { [weak bubble] _ in
            bubble?.focus()
        }
    }

    private func presentQAAnswer(_ answer: String) {
        dismissQABubble(animated: false, persistDraft: false)

        let bubble = QASpeechBubbleView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.configure(text: answer)
        bubble.alpha = 0
        bubble.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)

        let tapToDismiss = UITapGestureRecognizer(target: self, action: #selector(handleBubbleTapped))
        bubble.addGestureRecognizer(tapToDismiss)

        view.addSubview(bubble)
        qaBubbleView = bubble
        installBubbleDismissGestureIfNeeded()

        let constraints = [
            bubble.trailingAnchor.constraint(equalTo: qaModelView.leadingAnchor, constant: -12),
            bubble.centerYAnchor.constraint(equalTo: qaModelView.centerYAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16)
        ]
        constraints.last?.priority = .defaultHigh
        NSLayoutConstraint.activate(constraints)

        view.layoutIfNeeded()

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.75,
            initialSpringVelocity: 0.6,
            options: [.curveEaseOut]
        ) {
            bubble.alpha = 1
            bubble.transform = .identity
        }
    }

    @objc private func handleBubbleTapped() {
        dismissQABubble()
    }

    @objc private func handleBackgroundTapped() {
        dismissQABubble()
    }

    private func presentQAError(message: String) {
        let alert = UIAlertController(title: "送出失敗", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    // MARK: - 手勢狀態 UI
    private func setupGestureStatusUI() {
        gestureStatusLabel.text = "手勢辨識：準備中"
        gestureStatusLabel.textColor = .white
        gestureStatusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        gestureStatusLabel.textAlignment = .center
        gestureStatusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        gestureStatusLabel.layer.cornerRadius = 8
        gestureStatusLabel.clipsToBounds = true
        gestureStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gestureStatusLabel)

        hoverProgressView.progressTintColor = .systemBlue
        hoverProgressView.trackTintColor = UIColor.white.withAlphaComponent(0.25)
        hoverProgressView.progress = 0.0
        hoverProgressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hoverProgressView)
    }

    private func updateGestureStatusUI(_ state: GestureState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let (text, color): (String, UIColor) = {
                switch state {
                case .idle:       return ("手勢辨識：等待手部", .systemGray)
                case .detecting:  return ("手勢辨識：偵測中", .systemYellow)
                case .hovering:   return ("手勢辨識：懸停中…", .systemOrange)
                case .ready:      return ("手勢辨識：準備完成", .systemGreen)
                case .processing: return ("手勢辨識：處理中", .systemBlue)
                case .completed:  return ("手勢辨識：完成", .systemGreen)
                }
            }()
            self.gestureStatusLabel.text = text
            self.gestureStatusLabel.backgroundColor = color.withAlphaComponent(0.6)
        }
    }

    private func updateHoverProgressUI(_ progress: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.hoverProgressView.progress = max(0, min(progress, 1))
        }
    }
}

// MARK: - CookingARViewWrapper
/// SwiftUI Wrapper，讓 CookingARView 根據 stepViewModel 自動更新
private struct CookingARViewWrapper: View {
    @ObservedObject var stepViewModel: StepViewModel
    let sessionAdapter: ARSessionAdapter

    var body: some View {
        Group {
            if let stepModel = stepViewModel.currentStepModel {
                CookingARView(
                    stepModel: stepModel,
                    sessionAdapter: sessionAdapter
                )
                // ✅ 移除 .id() - 讓 SwiftUI 重用同一個 UIView，只透過 updateUIView 更新
                // 這樣可以避免每次切換步驟都重新創建 ARView，減少記憶體消耗
            }
        }
    }
}

// MARK: - ARGestureDelegate
extension CookViewController {
    func didRecognizeGesture(_ gestureType: GestureType) {
        print("🎯 [CookViewController] 接收到手勢: \(gestureType.description)")
        DispatchQueue.main.async { [weak self] in
            switch gestureType {
            case .previousStep: self?.prevStep()
            case .nextStep:     self?.nextStep()
            }
        }
    }

    func gestureStateDidChange(_ state: GestureState) {
        print("🎯 [CookViewController] 手勢狀態變更: \(state.description)")
        updateGestureStatusUI(state)
    }

    func hoverProgressDidUpdate(_ progress: Float) {
        updateHoverProgressUI(progress)
    }

    func palmStateDidChange(_ palmState: PalmState) {
        // 目前僅示意；若需要可在這裡更新額外 UI 或紀錄
        // print("✋ palm state: \(palmState)")
    }

    func gestureRecognitionDidFail(with error: GestureRecognitionError) {
        print("❌ [CookViewController] 手勢辨識錯誤: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.gestureStatusLabel.text = "手勢辨識錯誤：\(error.localizedDescription)"
            self?.gestureStatusLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.6)
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension CookViewController {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let bubble = qaBubbleView, let touchedView = touch.view, touchedView.isDescendant(of: bubble) {
            return false
        }
        if let inputBubble = qaInputBubbleView, let touchedView = touch.view, touchedView.isDescendant(of: inputBubble) {
            return false
        }
        return true
    }
}

// MARK: - QA Bubbles
private final class QAInputBubbleView: UIView, UITextViewDelegate {
    var onSubmit: ((String) -> Void)?

    private let containerView = UIView()
    private let tailView = SpeechBubbleTailView()
    private let titleLabel = UILabel()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let errorLabel = UILabel()

    private let contentInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 18
        containerView.layer.borderColor = UIColor.black.cgColor
        containerView.layer.borderWidth = 2
        containerView.layer.shadowColor = UIColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 0.6).cgColor
        containerView.layer.shadowOpacity = 0.6
        containerView.layer.shadowRadius = 6
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        containerView.layer.masksToBounds = false
        addSubview(containerView)

        tailView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tailView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Question❓"
        titleLabel.textColor = .black
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = UIColor(white: 0.97, alpha: 1)
        textView.layer.cornerRadius = 12
        textView.layer.borderColor = UIColor.black.withAlphaComponent(0.15).cgColor
        textView.layer.borderWidth = 1
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .black
        textView.tintColor = .systemBlue
        textView.keyboardAppearance = .light
        textView.returnKeyType = .send
        textView.isScrollEnabled = false
        textView.delegate = self

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = ""
        placeholderLabel.textColor = UIColor.black.withAlphaComponent(0.3)
        placeholderLabel.font = .systemFont(ofSize: 15)
        textView.addSubview(placeholderLabel)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setTitle("送出", for: .normal)
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        sendButton.backgroundColor = UIColor.systemBlue
        sendButton.layer.cornerRadius = 12
        sendButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 22, bottom: 10, right: 22)
        sendButton.addTarget(self, action: #selector(handleSendTapped), for: .touchUpInside)
        sendButton.isEnabled = false
        sendButton.alpha = 0.5

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textColor = UIColor.systemRed
        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        containerView.addSubview(titleLabel)
        containerView.addSubview(textView)
        containerView.addSubview(errorLabel)
        containerView.addSubview(sendButton)

        let minimumWidth = max(168, sendButton.intrinsicContentSize.width + contentInsets.left + contentInsets.right)
        let widthConstraint = containerView.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth)
        widthConstraint.priority = .required

        let errorBottom = errorLabel.bottomAnchor.constraint(equalTo: sendButton.topAnchor, constant: -12)
        errorBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            widthConstraint,

            tailView.leadingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -6),
            tailView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            tailView.widthAnchor.constraint(equalToConstant: 26),
            tailView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: contentInsets.left),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -contentInsets.right),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: contentInsets.top),

            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: contentInsets.left),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -contentInsets.right),
            textView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            textView.heightAnchor.constraint(equalToConstant: 44),

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),

            errorLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor),
            errorLabel.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 6),
            errorBottom,

            sendButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12),
            sendButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -contentInsets.right),
            sendButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -contentInsets.bottom),
            sendButton.leadingAnchor.constraint(greaterThanOrEqualTo: textView.leadingAnchor, constant: 0)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        updateSendButtonState()
    }

    func focus() {
        textView.becomeFirstResponder()
    }

    func resignFocus() {
        textView.resignFirstResponder()
    }

    func setDraftText(_ text: String) {
        textView.text = text
        placeholderLabel.isHidden = !text.isEmpty
        clearValidationError()
        updateSendButtonState()
    }

    func currentDraftText() -> String {
        textView.text ?? ""
    }

    func showValidationError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        sendButton.shake()
    }

    func clearValidationError() {
        errorLabel.isHidden = true
    }

    @objc private func handleSendTapped() {
        clearValidationError()
        onSubmit?(textView.text)
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateSendButtonState()
        if sendButton.isEnabled {
            clearValidationError()
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            handleSendTapped()
            return false
        }
        return true
    }

    private func updateSendButtonState() {
        let hasText = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText
        sendButton.alpha = hasText ? 1.0 : 0.5
    }

    private final class SpeechBubbleTailView: UIView {
        private let shapeLayer = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupLayer()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupLayer() {
            backgroundColor = .clear
            shapeLayer.fillColor = UIColor.white.cgColor
            shapeLayer.strokeColor = UIColor.black.cgColor
            shapeLayer.lineWidth = 2
            shapeLayer.lineJoin = .round
            layer.addSublayer(shapeLayer)

            layer.shadowColor = UIColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 0.6).cgColor
            layer.shadowOpacity = 0.6
            layer.shadowRadius = 6
            layer.shadowOffset = CGSize(width: 0, height: 4)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let path = UIBezierPath()
            let width = bounds.width
            let height = bounds.height

            path.move(to: CGPoint(x: 0, y: height * 0.15))
            path.addQuadCurve(to: CGPoint(x: width, y: height / 2), controlPoint: CGPoint(x: width * 0.35, y: height * 0.1))
            path.addQuadCurve(to: CGPoint(x: 0, y: height * 0.85), controlPoint: CGPoint(x: width * 0.35, y: height * 0.9))
            path.close()

            shapeLayer.path = path.cgPath
            layer.shadowPath = path.cgPath
        }
    }
}

private final class QASpeechBubbleView: UIView {
    private let containerView = UIView()
    private let textLabel = UILabel()
    private let tailView = SpeechBubbleTailView()

    private let contentInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 18
        containerView.layer.borderColor = UIColor.black.cgColor
        containerView.layer.borderWidth = 2
        containerView.layer.masksToBounds = false
        containerView.layer.shadowColor = UIColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 0.6).cgColor
        containerView.layer.shadowOpacity = 0.6
        containerView.layer.shadowRadius = 6
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)

        addSubview(containerView)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        textLabel.textColor = .black
        textLabel.font = .systemFont(ofSize: 15, weight: .medium)
        containerView.addSubview(textLabel)

        tailView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tailView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            textLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: contentInsets.left),
            textLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -contentInsets.right),
            textLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: contentInsets.top),
            textLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -contentInsets.bottom),

            tailView.leadingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -4),
            tailView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            tailView.widthAnchor.constraint(equalToConstant: 24),
            tailView.heightAnchor.constraint(equalToConstant: 18)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func configure(text: String) {
        textLabel.text = text
        layoutIfNeeded()
    }

    private final class SpeechBubbleTailView: UIView {
        private let shapeLayer = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupLayer()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupLayer() {
            backgroundColor = .clear
            shapeLayer.fillColor = UIColor.white.cgColor
            shapeLayer.strokeColor = UIColor.black.cgColor
            shapeLayer.lineWidth = 2
            shapeLayer.lineJoin = .round
            layer.addSublayer(shapeLayer)

            layer.shadowColor = UIColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 0.6).cgColor
            layer.shadowOpacity = 0.6
            layer.shadowRadius = 6
            layer.shadowOffset = CGSize(width: 0, height: 4)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let path = UIBezierPath()
            let width = bounds.width
            let height = bounds.height

            path.move(to: CGPoint(x: 0, y: height * 0.15))
            path.addQuadCurve(to: CGPoint(x: width, y: height / 2), controlPoint: CGPoint(x: width * 0.35, y: height * 0.1))
            path.addQuadCurve(to: CGPoint(x: 0, y: height * 0.85), controlPoint: CGPoint(x: width * 0.35, y: height * 0.9))
            path.close()

            shapeLayer.path = path.cgPath
            layer.shadowPath = path.cgPath
        }
    }
}

// MARK: - UIView Convenience
private extension UIView {
    func shake() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.3
        animation.values = [-6, 6, -4, 4, -2, 2, 0]
        layer.add(animation, forKey: "shake")
    }
}
