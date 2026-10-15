import XCTest
import SwiftData
import UIKit
@testable import CampusLens
import CampusLensCore

@MainActor
final class AdjustmentTests: XCTestCase {
    private func prepared(phoneISO: Double = 200) async throws -> (AppModel,ModelContainer) {
        let model = AppModel()
        let container = try ModelContainer(for:HistoryRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        var sample = Fixture.sample(id:UUID()); sample.exposure.iso = phoneISO
        model.sample = sample; model.confirm(context:container.mainContext)
        try await settled(model)
        return (model,container)
    }
    private func settled(_ model: AppModel) async throws {
        for _ in 0..<200 {
            if !model.isSolving { XCTAssertEqual(model.recommendations.count,2); return }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTFail("Solver did not finish")
    }
    private func apply(_ action: AdjustmentAction,camera: LensCamera = .nikon,model: AppModel,context: ModelContext) async throws {
        let preview = try await model.previewAdjustment(camera,action:action)
        try model.applyAdjustment(preview,context:context); try await settled(model)
    }
    func testPreviewDoesNotChangeParametersOrHistory() async throws {
        let (model,container) = try await prepared()
        let original = model.recommendations[0].exposure
        let preview = try await model.previewAdjustment(.nikon,action:.faster)
        XCTAssertNotEqual(preview.after.exposure,original)
        XCTAssertEqual(model.recommendations[0].exposure,original)
        XCTAssertTrue(model.adjustments.isEmpty); XCTAssertFalse(model.canUndo(.nikon))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<HistoryRecord>())[0].decoded().adjustments.isEmpty)
    }
    func testUndoRestoresCompensationAndCameraSnapshotsIndependently() async throws {
        let (model,container) = try await prepared()
        let context = container.mainContext
        try await apply(.compensation(1.0/3),model:model,context:context)
        let compensated = model.recommendations.first { $0.camera == .nikon }!.exposure
        try await apply(.faster,model:model,context:context)
        try await apply(.depth,camera:.canon,model:model,context:context)
        let canon = model.recommendations.first { $0.camera == .canon }!.exposure
        try model.undoAdjustment(.nikon,context:context); try await settled(model)
        XCTAssertEqual(model.adjustments["nikon"],CameraAdjustment(compensation:1.0/3))
        XCTAssertEqual(model.recommendations.first { $0.camera == .nikon }!.exposure,compensated)
        XCTAssertEqual(model.recommendations.first { $0.camera == .canon }!.exposure,canon)
        XCTAssertEqual(model.adjustmentCount(.nikon),1); XCTAssertEqual(model.adjustmentCount(.canon),1)
        let records = try context.fetch(FetchDescriptor<HistoryRecord>())
        XCTAssertEqual(records.count,1)
        XCTAssertEqual(try records[0].decoded().adjustments["nikon"],CameraAdjustment(compensation:1.0/3))
    }
    func testRestoreInitialCanBeUndone() async throws {
        let (model,container) = try await prepared(); let context = container.mainContext
        try await apply(.faster,model:model,context:context)
        try await apply(.compensation(1.0/3),model:model,context:context)
        let previous = model.adjustments["nikon"], exposure = model.recommendations[0].exposure
        try await apply(.restore,model:model,context:context)
        XCTAssertEqual(model.adjustments["nikon"],CameraAdjustment())
        XCTAssertEqual(model.adjustmentCount(.nikon),0)
        try model.undoAdjustment(.nikon,context:context); try await settled(model)
        XCTAssertEqual(model.adjustments["nikon"],previous); XCTAssertEqual(model.recommendations[0].exposure,exposure)
        XCTAssertEqual(model.adjustmentCount(.nikon),2)
    }
    func testOldPreviewCannotApplyAfterConditionsChangeOrReshoot() async throws {
        let (model,container) = try await prepared()
        let preview = try await model.previewAdjustment(.nikon,action:.faster)
        model.intent.nikonFocal = 70
        XCTAssertThrowsError(try model.applyAdjustment(preview,context:container.mainContext))
        model.intent.nikonFocal = 35
        try model.clearCurrent()
        model.sample = Fixture.sample(id:UUID()); model.confirm(context:container.mainContext); try await settled(model)
        XCTAssertThrowsError(try model.applyAdjustment(preview,context:container.mainContext))
        XCTAssertFalse(model.canUndo(.nikon)); XCTAssertEqual(model.adjustmentCount(.canon),0)
    }
    func testRepeatedApplyAndStaleSiblingPreviewCannotStack() async throws {
        let (model,container) = try await prepared()
        let first = try await model.previewAdjustment(.nikon,action:.faster)
        let sibling = try await model.previewAdjustment(.canon,action:.depth)
        try model.applyAdjustment(first,context:container.mainContext); try await settled(model)
        XCTAssertThrowsError(try model.applyAdjustment(first,context:container.mainContext))
        XCTAssertThrowsError(try model.applyAdjustment(sibling,context:container.mainContext))
        XCTAssertEqual(model.adjustmentCount(.nikon),1); XCTAssertEqual(model.adjustmentCount(.canon),0)
    }
    func testInfeasibleAdjustmentIsRejectedWithoutMutation() async throws {
        let (model,container) = try await prepared(phoneISO:1600)
        let original = model.recommendations[0].exposure
        let preview = try await model.previewAdjustment(.nikon,action:.faster)
        XCTAssertFalse(preview.after.isFeasible)
        XCTAssertThrowsError(try model.applyAdjustment(preview,context:container.mainContext))
        XCTAssertEqual(model.recommendations[0].exposure,original); XCTAssertTrue(model.adjustments.isEmpty)
    }
    func testAdjustmentLimitsAndNoOpRestoreAreExplicit() async throws {
        XCTAssertThrowsError(try CameraAdjustment(fasterSteps:6).applying(.faster))
        XCTAssertThrowsError(try CameraAdjustment(depthSteps:6).applying(.depth))
        XCTAssertThrowsError(try CameraAdjustment().applying(.compensation(.nan)))
        XCTAssertThrowsError(try CameraAdjustment().applying(.compensation(5.1)))
        let (model,_) = try await prepared()
        do { _ = try await model.previewAdjustment(.nikon,action:.restore); XCTFail("Initial restore should be a no-op") }
        catch { XCTAssertFalse(model.canUndo(.nikon)) }
    }
    func testCaptureFrameKeepsWholeFourThreeImageOutsideControls() {
        for size in [CGSize(width:393,height:699),CGSize(width:375,height:620),CGSize(width:430,height:740)] {
            let frame = CaptureLayout.previewSize(in:size,reservedHeight:202)
            XCTAssertEqual(frame.width/frame.height,0.75,accuracy:1e-10)
            XCTAssertLessThanOrEqual(frame.width,size.width)
            XCTAssertLessThanOrEqual(frame.height+202,size.height+0.0001)
        }
    }
    func testSubjectChangeInvalidatesPreviewAndRunningSolver() async throws {
        let (model,container) = try await prepared()
        let preview = try await model.previewAdjustment(.nikon,action:.faster)
        model.recompute(context:container.mainContext)
        model.changeSubject(1)
        try await Task.sleep(for:.milliseconds(200))
        XCTAssertTrue(model.needsReshoot); XCTAssertTrue(model.recommendations.isEmpty); XCTAssertFalse(model.isSolving)
        XCTAssertThrowsError(try model.applyAdjustment(preview,context:container.mainContext))
    }
    func testConditionsChangedDuringSolveCannotMislabelHistory() async throws {
        let model = AppModel()
        let container = try ModelContainer(for:HistoryRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        model.sample = Fixture.sample(id:UUID())
        model.confirm(context:container.mainContext)
        model.intent.nikonFocal = 70
        for _ in 0..<200 {
            if !model.isSolving { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertFalse(model.isSolving); XCTAssertTrue(model.recommendations.isEmpty)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<HistoryRecord>()),0)
        model.recompute(context:container.mainContext); try await settled(model)
        let saved = try container.mainContext.fetch(FetchDescriptor<HistoryRecord>())[0].decoded()
        XCTAssertEqual(saved.intent.nikonFocal,70)
    }
}
