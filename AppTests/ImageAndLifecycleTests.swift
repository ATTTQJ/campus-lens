import XCTest
import UIKit
import ImageIO
import CoreVideo
import SwiftData
@testable import CampusLens
import CampusLensCore

@MainActor
final class ImageAndLifecycleTests: XCTestCase {
    func testJPEGIsUprightSmallAndHasNoGPSOrExif() throws {
        let fixture = Fixture.sample(id:UUID())
        let source = try XCTUnwrap(CGImageSourceCreateWithData(fixture.previewJPEG as CFData,nil))
        let original = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(destination,original,[kCGImagePropertyOrientation:6,
                                                       kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:31.0],
                                                       kCGImagePropertyExifDictionary:[kCGImagePropertyExifUserComment:"private"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let cleaned = try ImageAnalysis.sanitizedJPEG(data as Data,maxEdge:640)
        let cleanSource = try XCTUnwrap(CGImageSourceCreateWithData(cleaned as CFData,nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(cleanSource,0,nil) as? [String:Any])
        XCTAssertNil(props[kCGImagePropertyGPSDictionary as String])
        XCTAssertNil(props[kCGImagePropertyExifDictionary as String])
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(cleanSource,0,nil))
        XCTAssertLessThanOrEqual(max(image.width,image.height),640)
        XCTAssertGreaterThan(image.width,image.height) // EXIF 6 rotates portrait fixture into landscape.
    }
    func testMissingMetadataFailsInsteadOfUsingLiveExposure() {
        XCTAssertThrowsError(try ImageAnalysis.exposure(metadata:[:]))
    }
    func testSyntheticRawBlackPatternStrideRotationAndHighlightRegion() throws {
        var optional: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault,4,4,kCVPixelFormatType_OneComponent16,nil,&optional),kCVReturnSuccess)
        let buffer = try XCTUnwrap(optional)
        CVPixelBufferLockBaseAddress(buffer,[])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let black: [UInt16] = [512,520,528,536]
        for y in 0..<4 { for x in 0..<4 {
            base.advanced(by:y*stride+x*2).assumingMemoryBound(to:UInt16.self).pointee = black[(y%2)*2+x%2].littleEndian
        } }
        base.advanced(by:3*2).assumingMemoryBound(to:UInt16.self).pointee = UInt16(4095).littleEndian
        CVPixelBufferUnlockBaseAddress(buffer,[])
        let tags: [String:Any] = [kCGImagePropertyDNGBlackLevel as String:black.map { NSNumber(value:$0) },
                                kCGImagePropertyDNGWhiteLevel as String:4095,
                                kCGImagePropertyDNGBlackLevelRepeatDim as String:[2,2]]
        let regions = [SubjectCandidate(id:0,label:"全图",rect:UnitRect(x:0,y:0,width:1,height:1)),
                       SubjectCandidate(id:1,label:"旋转后右下",rect:UnitRect(x:0.75,y:0.75,width:0.25,height:0.25))]
        let result = try ImageAnalysis.rawStatistics(buffer:buffer,tags:tags,orientation:6,subjects:regions)
        XCTAssertEqual(try XCTUnwrap(result[0].highlights).sampledPixels,16)
        XCTAssertEqual(try XCTUnwrap(result[0].highlights).clippedFraction,1.0/16,accuracy:1e-10)
        XCTAssertEqual(try XCTUnwrap(result[0].highlights).meanNormalized,1.0/16,accuracy:1e-10)
        XCTAssertEqual(try XCTUnwrap(result[1].highlights).clippedFraction,1)
        XCTAssertThrowsError(try ImageAnalysis.rawStatistics(buffer:buffer,tags:[:],orientation:6,subjects:regions))
    }
    func testOldResultCannotReplaceNewCaptureAndHistoryTrims() async throws {
        let model = AppModel()
        let container = try ModelContainer(for:HistoryRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let context = container.mainContext
        let first = Fixture.sample(id:UUID())
        model.sample = first; model.confirm(context:context)
        try model.clearCurrent()
        let second = Fixture.sample(id:UUID())
        model.sample = second; model.confirm(context:context)
        try await Task.sleep(for:.milliseconds(500))
        XCTAssertEqual(model.sample?.id,second.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HistoryRecord>()).map(\.id),[second.id])
        for _ in 0..<105 {
            model.sample = Fixture.sample(id:UUID())
            try model.persist(context:context)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HistoryRecord>()),100)
    }
    func testChangingConfirmedSubjectInvalidatesParameters() throws {
        let model = AppModel(); model.confirmed = true; model.intent.subjectID = 0
        model.changeSubject(1)
        XCTAssertTrue(model.needsReshoot); XCTAssertTrue(model.recommendations.isEmpty)
    }
    func testPersistUpdatesSameCaptureWithoutDuplicate() throws {
        let model = AppModel()
        let container = try ModelContainer(for:HistoryRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        model.sample = Fixture.sample(id:UUID())
        model.recommendations = [try ExposureSolver.solve(sample:XCTUnwrap(model.sample),intent:model.intent,camera:.nikon)]
        try model.persist(context:container.mainContext)
        model.adjustments["nikon"] = CameraAdjustment(compensation:1)
        model.recommendations = [try ExposureSolver.solve(sample:XCTUnwrap(model.sample),intent:model.intent,camera:.nikon,compensation:1)]
        try model.persist(context:container.mainContext)
        let records = try container.mainContext.fetch(FetchDescriptor<HistoryRecord>())
        XCTAssertEqual(records.count,1)
        XCTAssertEqual(try records[0].decoded().recommendations[0].compensationEV,1)
        XCTAssertEqual(try records[0].decoded().adjustments["nikon"]?.compensation,1)
    }
    func testTemporaryRAWDeletion() throws {
        let url = try RawFileStore.write(Data([1,2,3]),id:UUID())
        XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
        try RawFileStore.delete(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
    }
    func testBackgroundInterruptsAndRetainsCompletedOfflineResult() {
        let model = AppModel(); model.sample = Fixture.sample(id:UUID()); model.state = .capturing
        model.backgrounded()
        XCTAssertEqual(model.state,.failed); XCTAssertNotNil(model.sample)
    }
    func testEndpointRejectsInsecureAndCredentialURLs() {
        for endpoint in ["http://example.com/chat/completions","https://user:pass@example.com/chat/completions","file:///tmp/a"] {
            XCTAssertThrowsError(try AIConfiguration(enabled:true,endpoint:endpoint,model:"test",key:"test").validatedURL())
        }
    }
}
