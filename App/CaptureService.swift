@preconcurrency import AVFoundation
import Foundation
import ImageIO
import CampusLensCore

enum CaptureEvent: Sendable {
    case ready(String), preparing, capturing, analyzing, failed(String), interrupted
}
struct CaptureOutput: Sendable {
    var sample: CaptureSample
    var rawURL: URL
}
/// Every session mutation and delegate result is serialized on queue.
/// The preview reads the session only to attach an AVCaptureVideoPreviewLayer.
final class CaptureService: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label:"org.campuslens.capture",qos:.userInitiated)
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var configured = false
    private var rawFormat: OSType?
    private var rawPhoto: AVCapturePhoto?
    private var processedData: Data?
    private var pending: CheckedContinuation<CaptureOutput,Error>?
    private var captureID: UUID?
    private var settingsID: Int64?
    private var captureDate: Date?
    private var manualRegion: UnitRect?
    private var notifications: [NSObjectProtocol] = []
    private var delegateError: String?
    var onEvent: (@Sendable (CaptureEvent) -> Void)?
    override init() {
        super.init()
        notifications.append(NotificationCenter.default.addObserver(forName:AVCaptureSession.wasInterruptedNotification,object:session,queue:nil) { [weak self] _ in
            self?.queue.async { [weak self] in self?.fail("相机被系统中断，请回到前台重拍"); self?.onEvent?(.interrupted) }
        })
        notifications.append(NotificationCenter.default.addObserver(forName:AVCaptureSession.runtimeErrorNotification,object:session,queue:nil) { [weak self] _ in
            self?.queue.async { [weak self] in self?.fail("相机会话发生错误，请重新准备相机") }
        })
    }
    deinit { notifications.forEach(NotificationCenter.default.removeObserver) }
    func prepare() async throws {
        if AVCaptureDevice.authorizationStatus(for:.video) == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for:.video) else { throw SolverError.invalid("相机权限被拒绝，请在系统设置中允许校园取景使用相机") }
        }
        guard AVCaptureDevice.authorizationStatus(for:.video) == .authorized else { throw SolverError.invalid("相机权限被拒绝，请在系统设置中允许校园取景使用相机") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            queue.async { [self] in
                do {
                    onEvent?(.preparing)
                    if !configured {
                        // Physical wide-angle camera only; never virtual triple camera or ProRAW.
                        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else { throw SolverError.invalid("未找到后置物理主摄") }
                        session.beginConfiguration()
                        session.sessionPreset = .photo
                        do {
                            let input = try AVCaptureDeviceInput(device:camera)
                            guard session.canAddInput(input), session.canAddOutput(output) else { throw SolverError.invalid("不能配置 RAW 拍摄会话") }
                            session.addInput(input); session.addOutput(output)
                            output.maxPhotoQualityPrioritization = .quality
                            if output.isAppleProRAWSupported { output.isAppleProRAWEnabled = false }
                            device = camera
                            try camera.lockForConfiguration()
                            camera.videoZoomFactor = 1
                            if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
                            if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
                            camera.unlockForConfiguration()
                            session.commitConfiguration(); configured = true
                        } catch { session.commitConfiguration(); throw error }
                    }
                    if !session.isRunning { session.startRunning() }
                    rawFormat = output.availableRawPhotoPixelFormatTypes.first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
                    guard rawFormat != nil else { throw SolverError.invalid("当前物理主摄不提供 Bayer RAW；未替换为 ProRAW。请确认 iPhone 16 Pro 和系统版本") }
                    onEvent?(.ready("物理主摄 · 1× · Bayer RAW"))
                    continuation.resume()
                } catch { onEvent?(.failed(error.localizedDescription)); continuation.resume(throwing:error) }
            }
        }
    }
    func focus(at point: CGPoint, region: UnitRect) {
        queue.async { [self] in
            guard let device, pending == nil else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.unlockForConfiguration(); manualRegion = region
            } catch { onEvent?(.failed("无法设置主体测光点")) }
        }
    }
    func capture(id: UUID) async throws -> CaptureOutput {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard pending == nil, session.isRunning, let device, let rawFormat else {
                    continuation.resume(throwing:SolverError.invalid("相机未准备好或正在拍摄")); return
                }
                pending = continuation; captureID = id; delegateError = nil
                rawPhoto = nil; processedData = nil; onEvent?(.preparing)
                // Wait for AE/AF for >=0.5s, demand several stable observations, cap at 3s.
                awaitStable(device:device,id:id,iteration:0,stable:0)
                queue.asyncAfter(deadline:.now()+20) { [weak self] in
                    guard let self, self.captureID == id, self.pending != nil else { return }
                    self.fail("拍摄超时，请重新准备相机后重试")
                }
            }
        }
    }
    private func awaitStable(device: AVCaptureDevice,id: UUID,iteration: Int,stable: Int) {
        guard captureID == id, pending != nil else { return }
        let stableCount = !device.isAdjustingExposure && !device.isAdjustingFocus ? stable+1 : 0
        if iteration >= 5 && stableCount >= 3 {
            guard let rawFormat else { fail("Bayer RAW 格式不可用"); return }
            let settings = AVCapturePhotoSettings(rawPixelFormatType:rawFormat,processedFormat:[AVVideoCodecKey:AVVideoCodecType.jpeg])
            settings.flashMode = .off; settings.photoQualityPrioritization = .speed
            if let connection = output.connection(with:.video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            settingsID = settings.uniqueID
            captureDate = Date()
            onEvent?(.capturing); output.capturePhoto(with:settings,delegate:self)
        } else if iteration >= 30 { fail("自动曝光／对焦未稳定，请保持手机和光线稳定后重试") }
        else { queue.asyncAfter(deadline:.now()+0.1) { [self] in awaitStable(device:device,id:id,iteration:iteration+1,stable:stableCount) } }
    }
    func photoOutput(_ output: AVCapturePhotoOutput,didFinishProcessingPhoto photo: AVCapturePhoto,error: Error?) {
        queue.async { [self] in
            guard photo.resolvedSettings.uniqueID == settingsID, pending != nil else { return }
            if let error { delegateError = error.localizedDescription; return }
            if photo.isRawPhoto { rawPhoto = photo } else { processedData = photo.fileDataRepresentation() }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput,didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,error: Error?) {
        queue.async { [self] in
            guard resolvedSettings.uniqueID == settingsID, let id = captureID, pending != nil else { return }
            do {
                if let error { throw error }
                if let delegateError { throw SolverError.invalid(delegateError) }
                guard let photo = rawPhoto, let buffer = photo.pixelBuffer, let dng = photo.fileDataRepresentation(), let processedData else { throw SolverError.invalid("本次未同时获得 Bayer RAW 与处理预览") }
                guard AVCapturePhotoOutput.isBayerRAWPixelFormat(CVPixelBufferGetPixelFormatType(buffer)) else { throw SolverError.invalid("本次格式不是 Bayer RAW") }
                onEvent?(.analyzing)
                let exposure = try ImageAnalysis.exposure(metadata:photo.metadata)
                let jpeg = try ImageAnalysis.sanitizedJPEG(processedData)
                let orientation = (photo.metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
                var diagnostics: [String] = []
                var subjects: [SubjectCandidate]
                do { subjects = try ImageAnalysis.subjects(jpeg:jpeg,manualRegion:manualRegion) }
                catch {
                    diagnostics.append("本机人物检测失败，请手动确认点选区域："+error.localizedDescription)
                    subjects = [SubjectCandidate(id:0,label:"手动重要区域",rect:manualRegion ?? .center)]
                }
                do { subjects = try ImageAnalysis.rawStatistics(buffer:buffer,dng:dng,orientation:orientation,subjects:subjects) }
                catch { diagnostics.append(error.localizedDescription) }
                let url = try RawFileStore.write(dng,id:id)
                let sample = CaptureSample(id:id,timestamp:captureDate ?? Date(),exposure:exposure,previewJPEG:jpeg,subjects:subjects,orientation:orientation,
                                           rawFormat:CVPixelBufferGetPixelFormatType(buffer),diagnostics:diagnostics)
                let continuation = pending; pending = nil; captureID = nil; settingsID = nil
                rawPhoto = nil; self.processedData = nil
                continuation?.resume(returning:CaptureOutput(sample:sample,rawURL:url))
                onEvent?(.ready("物理主摄 · 1× · Bayer RAW"))
            } catch { fail(error.localizedDescription) }
        }
    }
    private func fail(_ reason: String) {
        let continuation = pending; pending = nil; captureID = nil; settingsID = nil
        rawPhoto = nil; processedData = nil; delegateError = nil
        continuation?.resume(throwing:SolverError.invalid(reason)); onEvent?(.failed(reason))
    }
    func stop() {
        queue.async { [self] in
            if pending != nil { fail("拍摄已取消，请重拍") }
            if session.isRunning { session.stopRunning() }
        }
    }
}
enum RawFileStore {
    static var directory: URL { URL.cachesDirectory.appendingPathComponent("CurrentRAW",isDirectory:true) }
    static func write(_ data: Data,id: UUID) throws -> URL {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("dng")
        try data.write(to:url,options:[.atomic,.completeFileProtection])
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
        return url
    }
    static func delete(_ url: URL?) throws {
        guard let url, url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
    }
    static func cleanupOnLaunch() throws {
        guard FileManager.default.fileExists(atPath:directory.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) where url.pathExtension == "dng" { try delete(url) }
    }
}
