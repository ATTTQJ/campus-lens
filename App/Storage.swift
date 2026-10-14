import Foundation
import SwiftData
import Security
import CampusLensCore

@Model
final class HistoryRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    @Attribute(.externalStorage) var thumbnail: Data
    var payload: Data
    init(result: SavedResult) throws {
        id = result.sample.id; timestamp = result.sample.timestamp
        thumbnail = result.sample.previewJPEG
        var compact = result; compact.sample.previewJPEG = Data()
        payload = try JSONEncoder().encode(compact)
    }
    func decoded() throws -> SavedResult {
        var result = try JSONDecoder().decode(SavedResult.self,from:payload)
        result.sample.previewJPEG = thumbnail
        return result
    }
    func update(result: SavedResult) throws {
        guard result.sample.id == id else { throw SolverError.invalid("历史记录 ID 不匹配") }
        var compact = result; compact.sample.previewJPEG = Data()
        let encoded = try JSONEncoder().encode(compact)
        timestamp = result.sample.timestamp; thumbnail = result.sample.previewJPEG; payload = encoded
    }
}
struct CameraAdjustment: Codable, Sendable, Equatable {
    var compensation: Double = 0
    var fasterSteps = 0
    var depthSteps = 0
}
struct SavedResult: Codable, Sendable {
    var sample: CaptureSample
    var intent: SceneIntent
    var recommendations: [Recommendation]
    var adjustments: [String:CameraAdjustment]
    var calibrations: [CalibrationProfile]
    var aiExplanation: String?
}
enum CalibrationStore {
    static var url: URL {
        URL.applicationSupportDirectory.appendingPathComponent("calibrations.json")
    }
    static func load() throws -> [CalibrationProfile] {
        guard FileManager.default.fileExists(atPath:url.path) else { return [] }
        return try JSONDecoder().decode([CalibrationProfile].self,from:Data(contentsOf:url))
    }
    static func save(_ profiles: [CalibrationProfile]) throws {
        try FileManager.default.createDirectory(at:URL.applicationSupportDirectory,withIntermediateDirectories:true)
        try JSONEncoder().encode(profiles).write(to:url,options:[.atomic,.completeFileProtection])
    }
}
enum KeychainStore {
    static let service = "org.campuslens.vision"
    static func read() throws -> String {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
                                 kSecAttrAccount as String:"api-key",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var output: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary,&output)
        if code == errSecItemNotFound { return "" }
        guard code == errSecSuccess, let data = output as? Data, let value = String(data:data,encoding:.utf8) else {
            throw SolverError.invalid("无法读取 Keychain（\(code)）")
        }
        return value
    }
    static func write(_ value: String) throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"api-key"]
        if value.isEmpty {
            let code = SecItemDelete(query as CFDictionary)
            guard code == errSecSuccess || code == errSecItemNotFound else { throw SolverError.invalid("无法删除 Keychain 密钥") }
            return
        }
        let attributes: [String:Any] = [kSecValueData as String:Data(value.utf8),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let code = SecItemUpdate(query as CFDictionary,attributes as CFDictionary)
        if code == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes,uniquingKeysWith: { _,new in new }) as CFDictionary,nil)
            guard added == errSecSuccess else { throw SolverError.invalid("无法保存 Keychain 密钥（\(added)）") }
        } else if code != errSecSuccess { throw SolverError.invalid("无法更新 Keychain 密钥（\(code)）") }
    }
}
