import Foundation

public enum ExposureSolver {
    public static let toleranceEV = 1.0/3 + 0.00001
    public static func solve(sample: CaptureSample, intent: SceneIntent, camera: LensCamera,
                             calibration: CalibrationProfile? = nil, compensation: Double = 0,
                             fasterSteps: Int = 0, depthSteps: Int = 0) throws -> Recommendation {
        let profile = CameraProfile.standard(camera)
        let focal = intent.focal(for: camera)
        let range = try profile.apertureRange(focal: focal, override: intent.canonOpenAperture)
        guard compensation.isFinite, abs(compensation) <= 5, (0...6).contains(fasterSteps), (0...6).contains(depthSteps),
              (1...10).contains(intent.rows), sample.subjects.contains(where: { $0.id == intent.subjectID }) else {
            throw SolverError.invalid("场景、补偿或主体输入无效")
        }
        var warnings: [String] = []
        var calibrated: CalibrationProfile?
        if let c = calibration {
            guard c.deltaEV.isFinite, abs(c.deltaEV) <= 6, c.standardDeviation.isFinite, c.standardDeviation >= 0,
                  c.version > 0, c.focalMM.isFinite, c.measurements.count == 3,
                  Set(c.measurements.map(\.captureID)).count == 3,
                  c.measurements.allSatisfy({ $0.phoneEV.isFinite && $0.accepted.isValid }) else { throw SolverError.invalid("校准记录损坏") }
            if c.camera == camera && c.lens == camera.lens && c.algorithmVersion == "1" && abs(c.focalMM-focal) < 0.5 {
                calibrated = c
                if c.standardDeviation > 0.33 { warnings.append("校准离散程度超过 1/3 档，请重复校准") }
            } else { warnings.append("当前焦距没有匹配校准，设备修正为零") }
        }
        let target = try sample.exposure.referenceEV() - (calibrated?.deltaEV ?? 0) - compensation
        guard target.isFinite else { throw SolverError.invalid("测光值无效") }
        var limit = intent.motion.shutterLimit
        if intent.scene == .award && intent.motion != .still { limit = min(limit,1.0/500) }
        if intent.handheld { limit = min(limit,1/(2*focal*profile.cropFactor)) }
        limit /= pow(2,Double(fasterSteps))
        var needed = range.lowerBound
        var focus: Double?
        if intent.scene == .group {
            if let near = intent.nearestMeters, let far = intent.farthestMeters {
                guard near.isFinite, far.isFinite, near > focal/1000, far >= near, far <= 1000 else { throw SolverError.invalid("人物距离无效，最远距离应不小于最近距离") }
                let f = focal; let n = near*1000; let d = far*1000
                let s = 2*n*d/(n+d)
                focus = s/1000
                // Solve the thin-lens DOF limits at harmonic-mean focus distance.
                let required = f*f*(d-n)/(profile.circleOfConfusionMM*(s-f)*(d+n))
                needed = max(needed, required)
                // Avoid underestimating depth on one-row near subjects.
                needed = max(needed, 4)
            } else if intent.nearestMeters != nil || intent.farthestMeters != nil {
                throw SolverError.invalid("请同时输入最近和最远人物距离，或都留空")
            } else {
                needed = max(needed, intent.rows <= 2 ? 5.6 : intent.rows <= 4 ? 8 : 11)
                warnings.append("缺少人物距离，采用保守景深预设；必须试拍检查前后排")
            }
        } else if intent.scene == .classroom { needed = max(needed,4) }
        needed *= pow(2,Double(depthSteps)/2)
        if intent.flash { warnings.append("持续光起始参数；不包含闪光曝光，请关闭闪光后测光或单独测闪光") }
        if sample.isTestData { warnings.append("模拟器测试数据，不能用于现场曝光") }
        warnings += sample.diagnostics
        if let highlight = sample.subjects.first(where: { $0.id == intent.subjectID })?.highlights, highlight.clippedFraction > 0.01 {
            warnings.append(String(format:"重要区域 RAW 饱和 %.1f%%；可试用负曝光补偿并检查相机高光",highlight.clippedFraction*100))
        }
        warnings.append("确认相机为 M 档、关闭自动 ISO，曝光步长 1/3 档；防抖不能消除人物运动")
        var result = Recommendation(camera: camera, exposure: nil, targetEV: target, errorEV: nil,
                                    maxSeconds: limit, minAperture: needed, focusMeters: focus,
                                    calibrationVersion: calibrated?.version, compensationEV: compensation,
                                    warnings: warnings, conflicts: [], alternatives: [])
        let apertures = profile.apertures.filter { range.contains($0) && $0+0.00001 >= needed }
        let shutters = profile.shutters.filter { $0 <= limit+1e-10 }
        guard !apertures.isEmpty, !shutters.isEmpty else {
            if apertures.isEmpty { result.conflicts.append(String(format:"所需景深 f/%.1f 超出镜头可用光圈",needed)); result.alternatives += ["减少排间距，后退并缩短焦距", "分组拍摄；景深不足调整需显式重新确认"] }
            if shutters.isEmpty { result.conflicts.append("人物运动所需快门快于机身上限"); result.alternatives.append("等待人物停稳，重新确认运动程度") }
            return result
        }
        var candidates: [(Exposure,Double)] = []
        var nearest: (Exposure,Double)?
        for aperture in apertures {
            for seconds in shutters {
                // Continuous value is only diagnostic; never round/clamp ISO independently.
                for iso in profile.isos {
                    let exposure = Exposure(aperture: aperture, seconds: seconds, iso: iso)
                    let error = try exposure.referenceEV()-target
                    if nearest == nil || abs(error) < abs(nearest!.1) { nearest = (exposure,error) }
                    if abs(error) <= toleranceEV { candidates.append((exposure,error)) }
                }
            }
        }
        if let best = candidates.min(by: { a,b in
            if a.0.iso != b.0.iso { return a.0.iso < b.0.iso }
            if abs(a.1-b.1) > 0.00001 && abs(abs(a.1)-abs(b.1)) > 0.00001 { return abs(a.1) < abs(b.1) }
            if a.0.aperture != b.0.aperture { return a.0.aperture < b.0.aperture }
            return a.0.seconds > b.0.seconds
        }) {
            result.exposure = best.0; result.errorEV = best.1
        } else if let nearest {
            result.exposure = nearest.0; result.errorEV = nearest.1
            result.conflicts.append(String(format:"可设置档位仍有 %+.2f EV 曝光误差（正值偏暗），超出 1/3 档求解容差",nearest.1))
            result.alternatives = nearest.1 > 0 ? ["增加持续光或移到更亮的位置", "人物停稳后显式降低运动程度", "缩短焦距或减少合影纵深，重新求解"] : ["降低现场亮度或使用减光镜", "检查测光是否对应当前取景"]
        }
        return result
    }
}
