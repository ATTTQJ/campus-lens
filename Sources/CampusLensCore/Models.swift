import Foundation

public enum LensCamera: String, Codable, CaseIterable, Sendable, Identifiable {
    case nikon, canon
    public var id: String { rawValue }
    public var title: String { self == .nikon ? "尼康 D850" : "佳能 200D" }
    public var lens: String { self == .nikon ? "24–70mm f/2.8G" : "EF-S 18–55mm f/4–5.6 IS STM" }
}
public enum NewsScene: String, Codable, CaseIterable, Sendable, Identifiable {
    case classroom, award, group
    public var id: String { rawValue }
    public var title: String {
        switch self { case .classroom: "会议课堂"; case .award: "颁奖抓拍"; case .group: "多排合影" }
    }
    public var defaultMotion: Motion {
        switch self { case .classroom: .speaking; case .award: .walking; case .group: .still }
    }
}
public enum Motion: String, Codable, CaseIterable, Sendable, Identifiable {
    case still, speaking, walking
    public var id: String { rawValue }
    public var title: String {
        switch self { case .still: "相对静止"; case .speaking: "讲话／手势"; case .walking: "走动／交接" }
    }
    public var shutterLimit: Double {
        switch self { case .still: 1.0/125; case .speaking: 1.0/250; case .walking: 1.0/500 }
    }
}
/// Normalized upright-image coordinates, origin at top left.
public struct UnitRect: Codable, Sendable, Equatable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var isValid: Bool {
        [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x+width <= 1.000001 && y+height <= 1.000001
    }
    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= x+width && py >= y && py <= y+height
    }
    public static let center = UnitRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
}
public struct SubjectCandidate: Codable, Sendable, Identifiable, Equatable {
    public var id: Int
    public var label: String
    public var rect: UnitRect
    public var highlights: RawStatistics?
    public init(id: Int, label: String, rect: UnitRect, highlights: RawStatistics? = nil) {
        self.id = id; self.label = label; self.rect = rect; self.highlights = highlights
    }
}
public struct Exposure: Codable, Sendable, Equatable {
    public var aperture: Double; public var seconds: Double; public var iso: Double
    public init(aperture: Double, seconds: Double, iso: Double) {
        self.aperture = aperture; self.seconds = seconds; self.iso = iso
    }
    public var isValid: Bool {
        [aperture, seconds, iso].allSatisfy { $0.isFinite && $0 > 0 } && aperture <= 128 && seconds <= 600 && iso <= 1_000_000
    }
    public func referenceEV() throws -> Double {
        guard isValid else { throw SolverError.invalid("曝光参数必须为有限正数") }
        return log2(aperture*aperture/seconds) - log2(iso/100)
    }
    public var shutterLabel: String {
        seconds < 1 ? "1/\(Int((1/seconds).rounded()))" : String(format: "%.1f s", seconds)
    }
}
public struct CaptureSample: Codable, Sendable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var exposure: Exposure
    public var previewJPEG: Data
    public var subjects: [SubjectCandidate]
    public var orientation: Int
    public var rawFormat: UInt32
    public var isTestData: Bool
    public var diagnostics: [String]
    public init(id: UUID, timestamp: Date = Date(), exposure: Exposure, previewJPEG: Data,
                subjects: [SubjectCandidate], orientation: Int = 1, rawFormat: UInt32 = 0,
                isTestData: Bool = false, diagnostics: [String] = []) {
        self.id = id; self.timestamp = timestamp; self.exposure = exposure; self.previewJPEG = previewJPEG
        self.subjects = subjects; self.orientation = orientation; self.rawFormat = rawFormat
        self.isTestData = isTestData; self.diagnostics = diagnostics
    }
}
public struct SceneIntent: Codable, Sendable, Equatable {
    public var scene: NewsScene = .classroom
    public var motion: Motion = .speaking
    public var handheld = true
    public var nikonFocal: Double = 35
    public var canonFocal: Double = 24
    public var canonOpenAperture: Double? = nil
    public var rows = 3
    public var nearestMeters: Double? = nil
    public var farthestMeters: Double? = nil
    public var flash = false
    public var subjectID = 0
    public init() {}
    public func focal(for camera: LensCamera) -> Double { camera == .nikon ? nikonFocal : canonFocal }
}
public struct CameraProfile: Codable, Sendable {
    public var camera: LensCamera
    public var cropFactor: Double
    public var circleOfConfusionMM: Double
    public var focalRange: ClosedRange<Double>
    public var apertures: [Double]
    public var shutters: [Double]
    public var isos: [Double]
    public static func standard(_ camera: LensCamera) -> Self {
        let denominators: [Double] = [8000,6400,5000,4000,3200,2500,2000,1600,1250,1000,800,640,500,400,320,250,200,160,125,100,80,60,50,40,30,25,20,15,13,10,8,6,5,4,3,2.5,2,1.6,1.3,1]
        let fast = denominators.filter { camera == .nikon || $0 <= 4000 }.map { 1/$0 }
        return Self(camera: camera, cropFactor: camera == .nikon ? 1 : 1.6,
                    circleOfConfusionMM: camera == .nikon ? 0.03 : 0.019,
                    focalRange: camera == .nikon ? 24...70 : 18...55,
                    apertures: [2.8,3.2,3.5,4,4.5,5,5.6,6.3,7.1,8,9,10,11,13,14,16,18,20,22,25,29,32],
                    shutters: fast + [1.3,1.6,2,2.5,3,4,5,6,8,10,13,15,20,25,30],
                    isos: camera == .canon ? [100,200,400,800,1600,3200,6400,12800,25600] :
                        [64,80,100,125,160,200,250,320,400,500,640,800,1000,1250,1600,2000,2500,3200,4000,5000,6400,8000,10000,12800,16000,20000,25600])
    }
    public func apertureRange(focal: Double, override: Double?) throws -> ClosedRange<Double> {
        guard focal.isFinite, focalRange.contains(focal) else { throw SolverError.invalid("焦距超出镜头范围") }
        if camera == .nikon { return 2.8...22 }
        let conservative = focal == 18 ? 4.0 : 5.6
        let open = override ?? conservative
        guard open.isFinite, open >= 4, open <= 5.6, apertures.contains(open), !(focal == 55 && open < 5.6) else {
            throw SolverError.invalid("佳能最大光圈应为相机实际显示的 f/4–f/5.6 档位；55mm 为 f/5.6")
        }
        // EF-S lens minimum aperture varies with zoom. Only allow f/22 at 18mm,
        // f/32 at 55mm; intermediate zoom uses conservative f/22 cap.
        return open...(focal == 55 ? 32 : 22)
    }
}
public struct CalibrationMeasurement: Codable, Sendable, Equatable {
    public var phoneEV: Double
    public var accepted: Exposure
    public var captureID: UUID
    public init(phoneEV: Double, accepted: Exposure, captureID: UUID) {
        self.phoneEV = phoneEV; self.accepted = accepted; self.captureID = captureID
    }
}
public struct CalibrationProfile: Codable, Sendable, Identifiable {
    public var id: UUID
    public var camera: LensCamera
    public var lens: String
    public var focalMM: Double
    public var deltaEV: Double
    public var standardDeviation: Double
    public var measurements: [CalibrationMeasurement]
    public var createdAt: Date
    public var version: Int
    public var algorithmVersion: String
    public static func make(camera: LensCamera, focal: Double, measurements: [CalibrationMeasurement], version: Int) throws -> Self {
        guard measurements.count == 3, Set(measurements.map(\.captureID)).count == 3,
              CameraProfile.standard(camera).focalRange.contains(focal), version > 0 else {
            throw SolverError.invalid("校准需要三个独立拍摄、有效焦距及版本")
        }
        let deltas = try measurements.map { item -> Double in
            guard item.phoneEV.isFinite else { throw SolverError.invalid("校准测光无效") }
            return item.phoneEV - (try item.accepted.referenceEV())
        }
        let average = deltas.reduce(0,+)/3
        guard abs(average) <= 6 else { throw SolverError.invalid("修正量超过 6 EV，请检查输入") }
        let sd = sqrt(deltas.map { pow($0-average,2) }.reduce(0,+)/2)
        return Self(id: UUID(), camera: camera, lens: camera.lens, focalMM: focal,
                    deltaEV: average, standardDeviation: sd, measurements: measurements,
                    createdAt: Date(), version: version, algorithmVersion: "1")
    }
}
public struct Recommendation: Codable, Sendable, Identifiable {
    public var id: LensCamera { camera }
    public var camera: LensCamera
    public var exposure: Exposure?
    public var targetEV: Double
    /// Positive means the candidate is darker than requested.
    public var errorEV: Double?
    public var maxSeconds: Double
    public var minAperture: Double
    public var focusMeters: Double?
    public var calibrationVersion: Int?
    public var compensationEV: Double
    public var warnings: [String]
    public var conflicts: [String]
    public var alternatives: [String]
    public var isFeasible: Bool { exposure != nil && conflicts.isEmpty }
    public var status: String { calibrationVersion == nil ? "起始参数 · 未校准" : "起始参数 · 校准 v\(calibrationVersion!)" }
}
public enum SolverError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}
