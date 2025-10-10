import Foundation
import simd
import RealityKit
import ARKit

/// 撒調味料動畫
class SprinkleAnimation: Animation {
    override var requiresContainerDetection: Bool { true }
    override var containerType: Container? { container }

    private let container: Container
    private let ingredient: String?
    private let model: Entity
    private weak var arViewRef: ARView?

    init(container: Container,
         ingredient: String? = nil,
         scale: Float = 1.0,
         isRepeat: Bool = false) {
        self.container = container
        self.ingredient = ingredient
        if let url = Bundle.main.url(forResource: "sprinkle", withExtension: "usdz"),
           let template = try? AnimationModelCache.entity(for: url) {
            self.model = template
        } else {
            self.model = ModelEntity()
        }
        super.init(type: .sprinkle, scale: scale, isRepeat: isRepeat)
    }

    /// 加入 Anchor 並播放動畫
    override func applyAnimation(to anchor: AnchorEntity, on arView: ARView) {
        self.arViewRef = arView
        let entity = model.clone(recursive: true)
        entity.scale = SIMD3<Float>(repeating: scale)
        if let name = ingredient, !name.isEmpty {
            _ = ARText.addLabel(text: name, to: entity)
        }
        anchor.addChild(entity)
        if let animation = entity.availableAnimations.first {
            let resource = isRepeat
                ? animation.repeat(duration: .infinity)
                : animation
            _ = entity.playAnimation(resource)
        } else {
            print("⚠️ USDZ 無可用動畫：sprinkle")
        }
    }

    /// 更新位置：在容器框上方均勻撒落
    override func updateBoundingBox(rect: CGRect) {
        guard let anchor = anchorEntity else { return }
        var newPos = anchor.transform.translation
        newPos.x += 0.2  // 往右方偏移 0.2 米
        newPos.y += Float(rect.height) * scale * 0.5 + 0.05
        anchor.transform.translation = newPos
    }
}
