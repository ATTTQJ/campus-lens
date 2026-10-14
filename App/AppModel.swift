import SwiftUI
import SwiftData
import Photos
import CampusLensCore

enum CaptureState: Equatable {
    case idle, preparing, ready, capturing, analyzing, failed
    var title: String {
        switch self { case .idle: "点击准备相机"; case .preparing: "正在准备／稳定曝光"; case .ready: "准备就绪";
        case .capturing: "正在拍摄 RAW"; case .analyzing: "正在本机分析"; case .failed: "拍摄未完成" }
    }
    var busy: Bool { self == .preparing || self == .capturing || self == .analyzing }
}
@MainActor @Observable
final class AppModel {
    let captureService = CaptureService()
    let aiClient: AIClient
    var state: CaptureState = .idle
    var message = "相机权限会在首次准备拍摄时申请"
    var error: String?
    var intent = SceneIntent()
    var sample: CaptureSample?
    var rawURL: URL?
    var recommendations: [Recommendation] = []
    var calibrations: [CalibrationProfile] = []
    var adjustments: [String:CameraAdjustment] = [:]
    var suggestion: AISuggestion?
    var aiExplanation: String?
    var aiStatus = ""
    var aiBusy = false
    var confirmed = false
    var needsReshoot = false
    var solvedIntent: SceneIntent?
    var selectedTab = 0
    var endpoint = UserDefaults.standard.string(forKey:"ai.endpoint") ?? ""
    var modelName = UserDefaults.standard.string(forKey:"ai.model") ?? ""
    var aiEnabled = UserDefaults.standard.bool(forKey:"ai.enabled")
    var calibrationCamera: LensCamera = .nikon
    var calibrationMeasurements: [CalibrationMeasurement] = []
    private var calibrationFocal: Double?
    private var captureTask: Task<Void,Never>?
    private var aiTask: Task<Void,Never>?
    private var solveTask: Task<Void,Never>?
    private var generation = UUID()
    private var solveRevision = UUID()
    private var aiRevision = UUID()
    private var autoAIRequestedCaptureID: UUID?
    init(aiClient: AIClient = AIClient()) {
        self.aiClient = aiClient
        do {
            try FileManager.default.createDirectory(at:URL.applicationSupportDirectory,withIntermediateDirectories:true)
            calibrations = try CalibrationStore.load(); try RawFileStore.cleanupOnLaunch()
        }
        catch { self.error = "本机记录读取／清理失败："+error.localizedDescription }
        captureService.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch event {
                case .preparing: self.state = .preparing
                case .capturing: self.state = .capturing
                case .analyzing: self.state = .analyzing
                case .ready(let text): self.state = .ready; self.message = text
                case .failed(let text): self.state = .failed; self.message = text
                case .interrupted: self.state = .failed; self.message = "拍摄被中断，请回到前台重拍"
                }
            }
        }
        #if DEBUG
        if isSimulator && testFault == "timeout" { aiEnabled = true }
        #endif
    }
    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    var testFault: String {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of:"--fault"), args.indices.contains(i+1) { return args[i+1] }
        #endif
        return ""
    }
    func prepareCamera() {
        guard !state.busy else { return }
        state = .preparing
        captureTask = Task {
            do {
                if isSimulator {
                    if testFault == "denied" { throw SolverError.invalid("相机权限被拒绝，请在系统设置中允许校园取景使用相机") }
                    state = .ready; message = "模拟器 · 明确标注的测试数据 · 无 RAW"
                } else { try await captureService.prepare() }
            } catch { state = .failed; message = error.localizedDescription }
        }
    }
    func shoot() {
        guard state == .ready else { return }
        do { try clearCurrent() } catch { self.error = error.localizedDescription; return }
        let id = UUID(); generation = id; state = .preparing
        captureTask = Task {
            do {
                let output: CaptureOutput
                if isSimulator {
                    state = .capturing
                    try await Task.sleep(for:.milliseconds(150))
                    if testFault == "capture" { throw SolverError.invalid("测试注入：拍摄失败，请重试") }
                    state = .analyzing
                    output = CaptureOutput(sample:Fixture.sample(id:id),rawURL:RawFileStore.directory.appendingPathComponent("test-no-raw"))
                } else { output = try await captureService.capture(id:id) }
                guard generation == id, !Task.isCancelled else { try RawFileStore.delete(output.rawURL); return }
                sample = output.sample; rawURL = isSimulator ? nil : output.rawURL
                intent.subjectID = 0; confirmed = false; state = .ready; selectedTab = 1
            } catch {
                guard generation == id else { return }
                state = .failed; message = error.localizedDescription
            }
        }
    }
    func clearCurrent() throws {
        generation = UUID(); solveRevision = UUID(); aiRevision = UUID()
        captureTask?.cancel(); solveTask?.cancel(); aiTask?.cancel()
        try RawFileStore.delete(rawURL)
        rawURL = nil; sample = nil; recommendations = []; adjustments = [:]
        confirmed = false; needsReshoot = false; solvedIntent = nil
        suggestion = nil; aiExplanation = nil; aiStatus = ""; aiBusy = false; autoAIRequestedCaptureID = nil
    }
    func backgrounded() {
        let wasBusy = state.busy
        generation = UUID(); captureTask?.cancel(); aiTask?.cancel(); aiRevision = UUID(); aiBusy = false
        captureService.stop(); state = wasBusy ? .failed : .idle
        message = wasBusy ? "后台中断拍摄，请重拍" : "回到前台后重新准备相机"
    }
    func confirm(context: ModelContext) {
        confirmed = true; needsReshoot = false
        recompute(context:context)
    }
    func changeSubject(_ id: Int) {
        if confirmed && intent.subjectID != id {
            needsReshoot = true; recommendations = []; aiTask?.cancel(); aiRevision = UUID()
            message = "主体变化，需要点选主体后重拍"
        }
        intent.subjectID = id
    }
    func recompute(context: ModelContext) {
        guard let sample, confirmed, !needsReshoot else { return }
        solveTask?.cancel(); aiTask?.cancel(); aiRevision = UUID()
        if aiBusy || suggestion != nil { aiStatus = "拍摄条件已更新，可主动重新请求补充建议" }
        aiBusy = false; suggestion = nil
        let revision = UUID(); solveRevision = revision
        let intent = self.intent, adjustments = self.adjustments, calibrations = self.calibrations
        solveTask = Task {
            do {
                let results = try await Task.detached(priority:.userInitiated) {
                    try LensCamera.allCases.map { camera in
                        let a = adjustments[camera.rawValue] ?? CameraAdjustment()
                        let c = calibrations.filter { $0.camera == camera && abs($0.focalMM-intent.focal(for:camera)) < 0.5 }.max { $0.version < $1.version }
                        return try ExposureSolver.solve(sample:sample,intent:intent,camera:camera,calibration:c,
                                                        compensation:a.compensation,fasterSteps:a.fasterSteps,depthSteps:a.depthSteps)
                    }
                }.value
                guard solveRevision == revision, self.sample?.id == sample.id, !Task.isCancelled else { return }
                recommendations = results; solvedIntent = intent
                try persist(context:context)
                if aiEnabled && autoAIRequestedCaptureID != sample.id {
                    autoAIRequestedCaptureID = sample.id; requestAI()
                }
            } catch { guard solveRevision == revision else { return }; self.error = error.localizedDescription }
        }
    }
    func adjust(_ camera: LensCamera,compensation: Double? = nil,faster: Bool = false,depth: Bool = false,reset: Bool = false,context: ModelContext) {
        var a = reset ? CameraAdjustment() : adjustments[camera.rawValue] ?? CameraAdjustment()
        if let compensation { a.compensation = min(5,max(-5,compensation)) }
        if faster { a.fasterSteps = min(6,a.fasterSteps+1) }
        if depth { a.depthSteps = min(6,a.depthSteps+1) }
        adjustments[camera.rawValue] = a; recompute(context:context)
    }
    func savedResult() -> SavedResult? {
        guard let sample, !recommendations.isEmpty else { return nil }
        return SavedResult(sample:sample,intent:intent,recommendations:recommendations,adjustments:adjustments,
                           calibrations:calibrations.filter { c in recommendations.contains { $0.camera == c.camera && $0.calibrationVersion == c.version } },aiExplanation:aiExplanation)
    }
    func persist(context: ModelContext) throws {
        guard let result = savedResult() else { return }
        let all = try context.fetch(FetchDescriptor<HistoryRecord>(sortBy:[SortDescriptor(\.timestamp,order:.reverse)]))
        if let existing = all.first(where: { $0.id == result.sample.id }) { try existing.update(result:result) }
        else { context.insert(try HistoryRecord(result:result)) }
        let other = all.filter { $0.id != result.sample.id }
        for record in other.dropFirst(99) { context.delete(record) }
        try context.save()
    }
    func requestAI() {
        guard let sample, confirmed, !needsReshoot, aiEnabled else { return }
        aiTask?.cancel(); let revision = UUID(); aiRevision = revision; suggestion = nil; aiBusy = true
        aiStatus = "正在请求补充建议；离线参数已可使用"
        aiTask = Task {
            do {
                let config = AIConfiguration(enabled:aiEnabled,endpoint:endpoint,model:modelName,key:try KeychainStore.read())
                let suggestion: AISuggestion
                if isSimulator && testFault == "timeout" {
                    try await Task.sleep(for:.milliseconds(300)); throw URLError(.timedOut)
                } else { suggestion = try await aiClient.suggest(sample:sample,configuration:config) }
                guard aiRevision == revision, self.sample?.id == sample.id, !Task.isCancelled else { return }
                self.suggestion = suggestion; aiStatus = "有补充建议"; aiBusy = false
            } catch {
                guard aiRevision == revision, self.sample?.id == sample.id, !Task.isCancelled else { return }
                aiStatus = "联网失败／超时，离线结果保留，可主动重试"; aiBusy = false
            }
        }
    }
    func applyAI(context: ModelContext) {
        guard let suggestion else { return }
        aiExplanation = suggestion.explanation; intent.scene = suggestion.scene
        changeSubject(suggestion.subjectID); self.suggestion = nil
        if needsReshoot { error = "AI 建议更换主体，需要重新点选并拍摄后计算" }
        else { recompute(context:context) }
    }
    func saveAI(enabled: Bool,endpoint: String,model: String,key: String) throws {
        if enabled { _ = try AIConfiguration(enabled:enabled,endpoint:endpoint,model:model,key:key).validatedURL() }
        try KeychainStore.write(key)
        self.endpoint = endpoint; modelName = model; aiEnabled = enabled
        UserDefaults.standard.set(endpoint,forKey:"ai.endpoint")
        UserDefaults.standard.set(model,forKey:"ai.model")
        UserDefaults.standard.set(enabled,forKey:"ai.enabled")
        aiTask?.cancel(); aiRevision = UUID(); aiBusy = false; suggestion = nil
    }
    func addCalibration(aperture: Double,seconds: Double,iso: Double) throws {
        guard let sample, !sample.isTestData, !calibrationMeasurements.contains(where: { $0.captureID == sample.id }) else {
            throw SolverError.invalid("每轮校准需要新的真实 RAW 拍摄；模拟器不能校准")
        }
        let profile = CameraProfile.standard(calibrationCamera)
        let focal = intent.focal(for:calibrationCamera)
        if calibrationMeasurements.isEmpty { calibrationFocal = focal }
        guard calibrationFocal == focal else {
            throw SolverError.invalid("本轮校准焦距已变化，请重置本轮并重新拍摄三次")
        }
        let range = try profile.apertureRange(focal:intent.focal(for:calibrationCamera),override:intent.canonOpenAperture)
        guard range.contains(aperture),profile.apertures.contains(aperture),profile.isos.contains(iso),
              profile.shutters.contains(where: { abs($0-seconds) < 1e-8 }) else { throw SolverError.invalid("校准参数不在相机可设置档位中") }
        calibrationMeasurements.append(CalibrationMeasurement(phoneEV:try sample.exposure.referenceEV(),accepted:Exposure(aperture:aperture,seconds:seconds,iso:iso),captureID:sample.id))
    }
    func finishCalibration() throws {
        let version = (calibrations.filter { $0.camera == calibrationCamera }.map(\.version).max() ?? 0)+1
        guard calibrationFocal == intent.focal(for:calibrationCamera) else { throw SolverError.invalid("校准焦距已变化，请重置本轮") }
        let profile = try CalibrationProfile.make(camera:calibrationCamera,focal:intent.focal(for:calibrationCamera),measurements:calibrationMeasurements,version:version)
        let next = calibrations+[profile]; try CalibrationStore.save(next); calibrations = next; calibrationMeasurements = []
    }
    func removeCalibrations() throws { try CalibrationStore.save([]); calibrations = []; calibrationMeasurements = [] }
    func savePreviewToPhotos() async {
        guard let sample else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for:.addOnly)
        guard status == .authorized || status == .limited else { error = "照片图库写入权限被拒绝"; return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with:.photo,data:sample.previewJPEG,options:nil)
            }
            message = "预览已保存到照片图库"
        } catch { self.error = "保存失败："+error.localizedDescription }
    }
}
@MainActor enum Fixture {
    static func sample(id: UUID) -> CaptureSample {
        let renderer = UIGraphicsImageRenderer(size:CGSize(width:720,height:960))
        let image = renderer.image { context in
            UIColor.darkGray.setFill(); context.fill(CGRect(x:0,y:0,width:720,height:960))
            let text = "模拟器测试图\n没有真实 RAW\n不能用于现场测光"
            text.draw(in:CGRect(x:60,y:360,width:600,height:240),withAttributes:[.font:UIFont.systemFont(ofSize:40),.foregroundColor:UIColor.white])
        }
        return CaptureSample(id:id,exposure:Exposure(aperture:1.78,seconds:1.0/125,iso:200),previewJPEG:image.jpegData(compressionQuality:0.85) ?? Data(),
                             subjects:[SubjectCandidate(id:0,label:"测试中央区域",rect:.center)],isTestData:true)
    }
}
