import Foundation
import simd
import RealityKit
import ARKit

/// 定義容器類型
enum Container: String, CaseIterable, Codable {
    case airFryer, bowl, microWaveOven, oven, pan, plate, riceCooker, soupPot
}

/// 食材掉入容器動畫
class PutIntoContainerAnimation: Animation {
    override var requiresContainerDetection: Bool { true }
    override var containerType: Container? { container }

    private let container: Container
    private let ingredientNames: [String]
    private var currentIngredientIndex: Int = 0
    private var activeEntity: Entity?
    private weak var arViewRef: ARView?
    private var containerCenter: SIMD3<Float>?
    private var cycleTimer: DispatchSourceTimer?

    /// 最後一次更新的容器底部位置
    private var _containerPosition: SIMD3<Float>?
    var containerPosition: SIMD3<Float>? { _containerPosition }

    private let containerScalePadding: Float = 0.85
    private let verticalLift: Float = 0.05

    private static var fallbackTextCache: [String: Entity] = [:]
    private static let fallbackTextLock = NSLock()
    private var containerRect: CGRect?

    init(ingredientNames: [String],
         container: Container,
         scale: Float = 1.0,
         isRepeat: Bool = false) {
        self.container = container
        let sanitized = ingredientNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sanitized.isEmpty {
            self.ingredientNames = [""]
        } else {
            self.ingredientNames = sanitized
        }
        super.init(type: .putIntoContainer, scale: scale, isRepeat: isRepeat)
    }

    private func makeEntity(for ingredientName: String) -> Entity {
        let base = PutIntoContainerAnimation.resolveModel(
            ingredientName: ingredientName,
            scale: scale
        )
        let content = base.clone(recursive: true)
        sanitizeEntityHierarchy(content)

        let wrapper = Entity()
        wrapper.name = "PutIntoContainerWrapper_\(ingredientName)"
        wrapper.addChild(content)
        wrapper.components.set(BillboardComponent())
        applyBillboard(to: content)
        content.position = .zero
        wrapper.position = .zero
        return wrapper
    }

    private func replaceActiveEntity(with entity: Entity, on anchor: AnchorEntity) {
        activeEntity?.removeFromParent()
        anchor.addChild(entity)
        activeEntity = entity
    }

    private func fitEntityToContainer(_ entity: Entity, anchor: AnchorEntity) {
        guard let rect = containerRect else { return }
        let bounds = entity.visualBounds(recursive: true, relativeTo: anchor).extents
        let epsilon: Float = 1e-5
        let sizeX = max(bounds.x, epsilon)
        let sizeY = max(bounds.y, epsilon)
        let sizeZ = max(bounds.z, epsilon)

        let allowedWidth = max(Float(rect.width) * scale * containerScalePadding, 0.05)
        let allowedHeight = max(Float(rect.height) * scale * containerScalePadding, 0.05)

        let factorCandidates: [Float] = [
            allowedWidth / sizeX,
            allowedHeight / sizeY,
            allowedWidth / sizeZ
        ]
        let factor = min(factorCandidates.min() ?? 1.0, 1.0)
        guard factor < 1.0 else { return }

        entity.scale = entity.scale * factor
    }

    private func resolveEntitySizeAndPlacement(_ entity: Entity, anchor: AnchorEntity) {
        guard containerRect != nil else { return }
        fitEntityToContainer(entity, anchor: anchor)
        positionEntityAtBottom(entity, anchor: anchor)
    }

    private func positionEntityAtBottom(_ entity: Entity, anchor: AnchorEntity) {
        guard let rect = containerRect else { return }
        entity.transform.translation = .zero
        let bounds = entity.visualBounds(recursive: true, relativeTo: anchor)
        let halfHeight = Float(rect.height) * scale * 0.5
        let minY = bounds.center.y - bounds.extents.y * 0.5
        let offsetY = (-halfHeight) - minY + verticalLift
        var translation = entity.transform.translation
        translation.y += offsetY
        entity.transform.translation = translation
    }

    private func updateActiveEntityPlacement() {
        guard let anchor = anchorEntity, let entity = activeEntity else { return }
        if let center = containerCenter {
            anchor.transform.translation = center
        }
        resolveEntitySizeAndPlacement(entity, anchor: anchor)
    }

    private static func resolveModel(ingredientName: String, scale: Float) -> Entity {
        if let url = Bundle.main.url(forResource: ingredientName, withExtension: "usdz") {
            do {
                return try AnimationModelCache.entity(for: url)
            } catch {
                print("⚠️ 載入 \(ingredientName).usdz 失敗：\(error)，改用預設")
            }
        }
        return makeFallbackModel(ingredientName: ingredientName, scale: scale)
    }

    private static func makeFallbackModel(ingredientName: String, scale: Float) -> Entity {
        fallbackTextLock.lock()
        defer { fallbackTextLock.unlock() }

        if let cached = fallbackTextCache[ingredientName] {
            return cached.clone(recursive: true)
        }

        let template: Entity
        if let fallbackURL = Bundle.main.url(forResource: "ingredient", withExtension: "usdz"),
           let baseTemplate = try? AnimationModelCache.entity(for: fallbackURL) {
            let base = baseTemplate.clone(recursive: true)
            _ = ARText.addLabel(text: ingredientName, to: base, padding: 0.03, maxWidthRatio: 0.85)
            sanitizeEntityHierarchy(base)
            template = base
        } else {
            let holder = Entity()
            let halfExtents = SIMD3<Float>(0.15, 0.05, 0.05)
            let bounds = BoundingBox(min: -halfExtents, max: halfExtents)
            _ = ARText.addLabel(text: ingredientName, to: holder, padding: 0.02, maxWidthRatio: 1.0, boundingOverride: bounds)
            sanitizeEntityHierarchy(holder)
            template = holder
        }

        fallbackTextCache[ingredientName] = template
        let instance = template.clone(recursive: true)
        instance.scale = SIMD3<Float>(repeating: scale)
        return instance
    }

    /// 把模型加到 Anchor 並放置於容器底部
    override func applyAnimation(to anchor: AnchorEntity, on arView: ARView) {
        arViewRef = arView
        activeEntity = nil
        cycleTimer?.cancel()
        cycleTimer = nil
        currentIngredientIndex = 0
        containerRect = nil
        containerCenter = nil

        currentIngredientIndex = 0
        let initialName = ingredientNames.first ?? ""
        let entity = makeEntity(for: initialName)
        replaceActiveEntity(with: entity, on: anchor)

        updateActiveEntityPlacement()
        startIngredientCycle()
    }

    override func updatePosition(_ position: SIMD3<Float>) {
        containerCenter = position
        super.updatePosition(position)
        updateActiveEntityPlacement()
    }

    /// 更新 bounding box 時，同步計算框底世界座標
    override func updateBoundingBox(rect: CGRect) {
        guard let anchor = anchorEntity else { return }
        containerRect = rect
        let center = containerCenter ?? anchor.transform.translation
        anchor.transform.translation = center
        let halfHeight = Float(rect.height) * scale * 0.5
        var bottom = center
        bottom.y -= halfHeight
        _containerPosition = bottom
        updateActiveEntityPlacement()
    }

    override func stop() {
        super.stop()
        containerRect = nil
        _containerPosition = nil
        containerCenter = nil
        activeEntity = nil
        cycleTimer?.cancel()
        cycleTimer = nil
    }

    deinit {
        activeEntity = nil
        cycleTimer?.cancel()
        cycleTimer = nil
    }

    private func sanitizeEntityHierarchy(_ entity: Entity) {
        entity.components.remove(AnchoringComponent.self)
        entity.components.remove(SynchronizationComponent.self)
        entity.components.remove(PhysicsBodyComponent.self)
        entity.components.remove(PhysicsMotionComponent.self)
        entity.components.remove(CollisionComponent.self)
        for child in entity.children {
            sanitizeEntityHierarchy(child)
        }
    }

    private func applyBillboard(to entity: Entity) {
        entity.components.set(BillboardComponent())
        for child in entity.children {
            applyBillboard(to: child)
        }
    }

    private func startIngredientCycle() {
        guard ingredientNames.count > 1 else { return }

        cycleTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.cycleToNextIngredient()
        }
        cycleTimer = timer
        timer.resume()
    }

    private func cycleToNextIngredient() {
        guard !ingredientNames.isEmpty,
              let anchor = anchorEntity else { return }

        currentIngredientIndex = (currentIngredientIndex + 1) % ingredientNames.count
        let name = ingredientNames[currentIngredientIndex]
        let entity = makeEntity(for: name)
        replaceActiveEntity(with: entity, on: anchor)
        updateActiveEntityPlacement()
    }
}
