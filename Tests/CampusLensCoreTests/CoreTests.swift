import XCTest
@testable import CampusLensCore

final class CoreTests: XCTestCase {
    func sample(ev: Double = 8) -> CaptureSample {
        CaptureSample(id: UUID(), exposure: Exposure(aperture: 2,seconds: 1/pow(2,ev-2),iso: 100),previewJPEG: Data(),
                      subjects: [SubjectCandidate(id: 0,label: "中心",rect: .center)])
    }
    func testFormulaAndCompensationDirection() throws {
        XCTAssertEqual(try Exposure(aperture: 4,seconds: 1.0/250,iso: 400).referenceEV(), log2(1000),accuracy: 1e-10)
        let original = try ExposureSolver.solve(sample: sample(),intent: SceneIntent(),camera: .nikon)
        let brighter = try ExposureSolver.solve(sample: sample(),intent: SceneIntent(),camera: .nikon,compensation: 1)
        XCTAssertEqual(brighter.targetEV,original.targetEV-1,accuracy: 1e-10)
        XCTAssertLessThan(try XCTUnwrap(brighter.exposure).referenceEV(),try XCTUnwrap(original.exposure).referenceEV())
    }
    func testCanonWholeStopsAndLensLimits() throws {
        var intent = SceneIntent(); intent.canonFocal = 35
        for ev in stride(from: 3.0,through: 17,by: 0.37) {
            let result = try ExposureSolver.solve(sample: sample(ev:ev),intent: intent,camera: .canon)
            if let e = result.exposure {
                XCTAssertTrue(CameraProfile.standard(.canon).isos.contains(e.iso))
                XCTAssertGreaterThanOrEqual(e.aperture,5.6)
                XCTAssertLessThanOrEqual(e.aperture,22)
                XCTAssertLessThanOrEqual(e.seconds,result.maxSeconds)
            }
        }
        intent.canonFocal = 55; intent.canonOpenAperture = 4
        XCTAssertThrowsError(try ExposureSolver.solve(sample:sample(),intent:intent,camera:.canon))
    }
    func testJointSolverAndLowestISO() throws {
        var intent = SceneIntent(); intent.scene = .award
        let r = try ExposureSolver.solve(sample:sample(ev:9.41),intent:intent,camera:.canon)
        XCTAssertTrue(r.isFeasible)
        let best = try XCTUnwrap(r.exposure)
        XCTAssertLessThanOrEqual(abs(try best.referenceEV()-r.targetEV),ExposureSolver.toleranceEV)
        for n in CameraProfile.standard(.canon).apertures where n >= r.minAperture && n <= 22 {
            for t in CameraProfile.standard(.canon).shutters where t <= r.maxSeconds {
                for iso in CameraProfile.standard(.canon).isos where iso < best.iso {
                    XCTAssertGreaterThan(abs(try Exposure(aperture:n,seconds:t,iso:iso).referenceEV()-r.targetEV),ExposureSolver.toleranceEV)
                }
            }
        }
    }
    func testNoSolutionReportsConflictWithoutChangingConstraints() throws {
        let r = try ExposureSolver.solve(sample:sample(ev:-5),intent:SceneIntent(),camera:.canon)
        XCTAssertFalse(r.isFeasible); XCTAssertFalse(r.conflicts.isEmpty); XCTAssertFalse(r.alternatives.isEmpty)
        XCTAssertLessThanOrEqual(try XCTUnwrap(r.exposure).seconds,r.maxSeconds)
        var intent = SceneIntent(); intent.scene = .group; intent.nearestMeters = 0.5; intent.farthestMeters = 20; intent.nikonFocal = 70
        let depth = try ExposureSolver.solve(sample:sample(),intent:intent,camera:.nikon)
        XCTAssertNil(depth.exposure); XCTAssertFalse(depth.conflicts.isEmpty)
    }
    func testIllegalInputs() throws {
        for bad in [0.0,-1,.infinity,.nan] { XCTAssertThrowsError(try Exposure(aperture:bad,seconds:1,iso:100).referenceEV()) }
        var intent = SceneIntent(); intent.canonFocal = 60
        XCTAssertThrowsError(try ExposureSolver.solve(sample:sample(),intent:intent,camera:.canon))
        intent = SceneIntent(); intent.scene = .group; intent.nearestMeters = 3
        XCTAssertThrowsError(try ExposureSolver.solve(sample:sample(),intent:intent,camera:.nikon))
    }
    func testCalibrationThreeDistinctCapturesAndPersistence() throws {
        let measures = [8.0,8.1,7.9].map { CalibrationMeasurement(phoneEV:$0,accepted:Exposure(aperture:4,seconds:1.0/125,iso:1600),captureID:UUID()) }
        let c = try CalibrationProfile.make(camera:.nikon,focal:35,measurements:measures,version:2)
        let decoded = try JSONDecoder().decode(CalibrationProfile.self,from:JSONEncoder().encode(c))
        XCTAssertEqual(decoded.deltaEV,8-log2(125),accuracy:1e-10)
        XCTAssertEqual(decoded.standardDeviation,0.1,accuracy:1e-10)
        let r = try ExposureSolver.solve(sample:sample(),intent:SceneIntent(),camera:.nikon,calibration:decoded)
        XCTAssertEqual(r.targetEV,8-c.deltaEV,accuracy:1e-10); XCTAssertEqual(r.calibrationVersion,2)
        XCTAssertThrowsError(try CalibrationProfile.make(camera:.nikon,focal:35,measurements:Array(repeating:measures[0],count:3),version:1))
        var intent = SceneIntent(); intent.nikonFocal = 50
        XCTAssertNil(try ExposureSolver.solve(sample:sample(),intent:intent,camera:.nikon,calibration:c).calibrationVersion)
    }
    func testRawLevelsSaturationAndOrientation() throws {
        XCTAssertEqual(try RawMath.normalize(512,black:512,white:4095),0)
        XCTAssertEqual(try RawMath.normalize(4095,black:512,white:4095),1)
        XCTAssertThrowsError(try RawMath.normalize(100,black:512,white:512))
        let stats = try RawMath.statistics(values:[0,0.5,0.98,1])
        XCTAssertEqual(stats.clippedFraction,0.5)
        for orientation in 1...8 {
            let sensor = try RawMath.sensorPoint(x:0.2,y:0.3,orientation:orientation)
            let back = try RawMath.uprightPoint(x:sensor.0,y:sensor.1,orientation:orientation)
            XCTAssertEqual(back.0,0.2,accuracy:1e-10); XCTAssertEqual(back.1,0.3,accuracy:1e-10)
        }
        let rotated = try RawMath.sensorPoint(x:0.2,y:0.3,orientation:6)
        XCTAssertEqual(rotated.0,0.3); XCTAssertEqual(rotated.1,0.8)
        XCTAssertThrowsError(try RawMath.sensorPoint(x:0,y:0,orientation:9))
    }
    func testDepthAndFeedbackMaintainExposure() throws {
        var intent = SceneIntent(); intent.scene = .group; intent.nearestMeters = 3; intent.farthestMeters = 5
        let base = try ExposureSolver.solve(sample:sample(ev:12),intent:intent,camera:.nikon)
        let adjusted = try ExposureSolver.solve(sample:sample(ev:12),intent:intent,camera:.nikon,fasterSteps:1,depthSteps:1)
        XCTAssertEqual(adjusted.maxSeconds,base.maxSeconds/2,accuracy:1e-10)
        XCTAssertEqual(adjusted.minAperture,base.minAperture*sqrt(2),accuracy:1e-10)
        XCTAssertEqual(try XCTUnwrap(base.focusMeters),3.75,accuracy:1e-10)
        XCTAssertEqual(adjusted.targetEV,base.targetEV)
    }
    func testExplicitStationaryAwardCanRelaxMotionConstraint() throws {
        var intent = SceneIntent(); intent.scene = .award; intent.motion = .walking
        let walking = try ExposureSolver.solve(sample:sample(),intent:intent,camera:.nikon)
        intent.motion = .still
        let stationary = try ExposureSolver.solve(sample:sample(),intent:intent,camera:.nikon)
        XCTAssertEqual(walking.maxSeconds,1.0/500,accuracy:1e-10)
        XCTAssertEqual(stationary.maxSeconds,1.0/125,accuracy:1e-10)
    }
    func testAIRejectsNumbersUnknownSubjectAndMalformedSchema() throws {
        let subjects = sample().subjects
        let valid = Data(#"{"scene":"award","subjectID":0,"explanation":"交接时注意手势"}"#.utf8)
        XCTAssertEqual(try AISuggestion.validated(json:valid,subjects:subjects).scene,.award)
        for json in [#"{"scene":"award","subjectID":0,"explanation":"hi","iso":800}"#,
                     #"{"scene":"stage","subjectID":0,"explanation":"hi"}"#,
                     #"{"scene":"award","subjectID":1,"explanation":"hi"}"#,
                     #"{"scene":"award","subjectID":false,"explanation":"hi"}"#] {
            XCTAssertThrowsError(try AISuggestion.validated(json:Data(json.utf8),subjects:subjects))
        }
    }
    func testJPEGMetadataSegmentsAreRemovedWithoutChangingScan() throws {
        let header: [UInt8] = [0xff,0xd8,0xff,0xe1,0,8,69,120,105,102,0,0,
                               0xff,0xfe,0,4,65,66,0xff,0xdb,0,4,1,2]
        let scan: [UInt8] = [0xff,0xda,0,2,10,0xff,0,20,0xff,0xd9]
        let cleaned = try JPEGMetadata.stripped(Data(header+scan))
        XCTAssertEqual([UInt8](cleaned),[0xff,0xd8,0xff,0xdb,0,4,1,2]+scan)
        XCTAssertThrowsError(try JPEGMetadata.stripped(Data([0xff,0xd8,0xff,0xe1,0,20])))
    }
}
