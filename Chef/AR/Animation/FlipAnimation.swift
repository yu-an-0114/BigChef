import RealityKit
import UIKit
import ARKit

/// 翻面（Flip）動畫：當偵測到指定容器後，執行翻面動畫
class FlipAnimation: Animation {
    /// 以 Entity 描述，可容納帶骨骼或普通模型
    private let model: Entity
    /// 指定要偵測的容器
    private let container: Container
    private let ingredient: String?
    private var boundingBoxRect: CGRect?

    override var requiresContainerDetection: Bool { true }
    override var containerType: Container? { container }

    /// 現在把 container 拿進來，初始化時設定
    init(container: Container,
         ingredient: String? = nil,
         scale: Float = 1,
         isRepeat: Bool = false) {
        self.container = container
        self.ingredient = ingredient

        // 載入 flip.usdz
        guard let url = Bundle.main.url(forResource: "flip", withExtension: "usdz") else {
            fatalError("❌ 找不到 flip.usdz")
        }
        do {
            model = try AnimationModelCache.entity(for: url)
        } catch {
            fatalError("❌ 無法載入 flip.usdz：\(error)")
        }
        super.init(type: .flip, scale: scale, isRepeat: isRepeat)
    }

    /// 將模型加入 Anchor 並播放內建動畫
    override func applyAnimation(to anchor: AnchorEntity, on arView: ARView) {
        let entity = model.clone(recursive: true)
        entity.scale = SIMD3<Float>(repeating: scale)
        if let name = ingredient, !name.isEmpty {
            _ = ARText.addLabel(text: name, to: entity)
        }
        anchor.addChild(entity)

        // 將 anchor 移動到相機前方 0.3 米處
        anchor.setPosition(SIMD3<Float>(0, 0, -5), relativeTo: nil)

        if let anim = entity.availableAnimations.first {
            // 根據 isRepeat 決定是否無限重播
            let resource = isRepeat ? anim.repeat(duration: .infinity) : anim
            entity.playAnimation(resource, transitionDuration: 0.0, startsPaused: false)
        }
    }

    /// 每次 2D 偵測框更新時，儲存以做對齊
    override func updateBoundingBox(rect: CGRect) {
        boundingBoxRect = rect
    }
}
