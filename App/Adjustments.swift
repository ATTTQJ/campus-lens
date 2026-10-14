import Foundation
import CampusLensCore

enum AdjustmentAction: Equatable, Sendable {
    case faster, depth, compensation(Double), restore
    var title: String {
        switch self {
        case .faster: "人物模糊"
        case .depth: "景深不足"
        case .compensation: "调整曝光补偿"
        case .restore: "恢复初始参数"
        }
    }
}

extension CameraAdjustment {
    var isInitial: Bool { self == CameraAdjustment() }
    func applying(_ action: AdjustmentAction) throws -> Self {
        var next = self
        switch action {
        case .faster:
            guard fasterSteps < 6 else { throw SolverError.invalid("快门已调整六档，请先撤销或重新确认人物运动") }
            next.fasterSteps += 1
        case .depth:
            guard depthSteps < 6 else { throw SolverError.invalid("光圈已调整六档，请先撤销或检查人物距离") }
            next.depthSteps += 1
        case .compensation(let value):
            guard value.isFinite, abs(value) <= 5 else { throw SolverError.invalid("曝光补偿范围为 −5 到 +5 档") }
            next.compensation = value
        case .restore: next = Self()
        }
        return next
    }
}

/// A proposal belongs to one capture, scene, solver revision and camera snapshot.
/// It must never apply after a reshoot, condition edit or another adjustment.
struct AdjustmentPreview: Identifiable, Sendable {
    let id = UUID()
    let captureID: UUID
    let revision: UUID
    let intent: SceneIntent
    let camera: LensCamera
    let action: AdjustmentAction
    let previous: CameraAdjustment
    let next: CameraAdjustment
    let before: Recommendation
    let after: Recommendation
}

struct AdjustmentChange: Sendable {
    let title: String
    let before: Exposure?
    let after: Exposure?
}

struct AdjustmentSnapshot: Sendable {
    let adjustment: CameraAdjustment
    let count: Int
    let change: AdjustmentChange?
}
