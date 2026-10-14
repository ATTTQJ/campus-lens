import Foundation
import CoreFoundation

public struct AISuggestion: Codable, Sendable, Equatable {
    public var scene: NewsScene
    public var subjectID: Int
    public var explanation: String
    public static func validated(json: Data, subjects: [SubjectCandidate]) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: json) as? [String:Any],
              Set(object.keys) == Set(["scene","subjectID","explanation"]),
              let sceneString = object["scene"] as? String, let scene = NewsScene(rawValue: sceneString),
              let number = object["subjectID"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == Double(number.intValue),
              subjects.contains(where: { $0.id == number.intValue }),
              let text = object["explanation"] as? String, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              text.count <= 1200 else { throw SolverError.invalid("AI 返回格式不合法，仅接受场景、主体 ID 和说明") }
        return Self(scene: scene, subjectID: number.intValue, explanation: text)
    }
}
