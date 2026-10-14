import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision
import CoreVideo
import CampusLensCore

enum ImageAnalysis {
    /// Decode, orient and encode a new JPEG. Never copy EXIF/GPS dictionaries.
    static func sanitizedJPEG(_ data: Data, maxEdge: Int = 1280) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:maxEdge
              ] as CFDictionary) else { throw SolverError.invalid("无法解码拍摄预览") }
        guard let colorSpace = CGColorSpace(name:CGColorSpace.sRGB),
              let bitmap = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:0,
                                     space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw SolverError.invalid("无法创建 sRGB 预览")
        }
        bitmap.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        guard let rgb = bitmap.makeImage() else { throw SolverError.invalid("无法转换预览色彩") }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded,UTType.jpeg.identifier as CFString,1,nil) else { throw SolverError.invalid("无法创建 JPEG") }
        CGImageDestinationAddImage(destination,rgb,[kCGImageDestinationLossyCompressionQuality:0.85,
                                                  kCGImagePropertyJFIFDictionary:[kCGImagePropertyJFIFIsProgressive:false]] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw SolverError.invalid("无法编码预览") }
        return try JPEGMetadata.stripped(encoded as Data)
    }
    static func subjects(jpeg: Data, manualRegion: UnitRect?) throws -> [SubjectCandidate] {
        let faces = VNDetectFaceRectanglesRequest()
        let people = VNDetectHumanRectanglesRequest(); people.upperBodyOnly = false
        try VNImageRequestHandler(data:jpeg,orientation:.up).perform([faces,people])
        func rect(_ b: CGRect) -> UnitRect { UnitRect(x:b.minX,y:1-b.maxY,width:b.width,height:b.height) }
        var output = [SubjectCandidate(id:0,label:manualRegion == nil ? "中央重要区域" : "点选重要区域",rect:manualRegion ?? .center)]
        for face in (faces.results ?? []).prefix(12) {
            let r = rect(face.boundingBox)
            if r.isValid { output.append(SubjectCandidate(id:output.count,label:"面部 \(output.count)",rect:r)) }
        }
        for person in (people.results ?? []).prefix(12) {
            let r = rect(person.boundingBox)
            if r.isValid { output.append(SubjectCandidate(id:output.count,label:"人物 \(output.count)",rect:r)) }
        }
        return output
    }
    static func exposure(metadata: [String:Any]) throws -> Exposure {
        guard let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String:Any],
              let n = exif[kCGImagePropertyExifFNumber as String] as? NSNumber,
              let t = exif[kCGImagePropertyExifExposureTime as String] as? NSNumber,
              let isos = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber],let iso = isos.first else {
            throw SolverError.invalid("本次 RAW 缺少同次 EXIF 光圈、快门或 ISO，不能使用取景实时值替代")
        }
        let e = Exposure(aperture:n.doubleValue,seconds:t.doubleValue,iso:iso.doubleValue)
        guard e.isValid else { throw SolverError.invalid("本次 EXIF 曝光无效") }
        return e
    }
    static func numbers(_ value: Any?) -> [Double] {
        if let a = value as? [NSNumber] { return a.map(\.doubleValue) }
        if let n = value as? NSNumber { return [n.doubleValue] }
        return []
    }
    /// Analyze unpacked Bayer samples with DNG-declared black/white levels.
    /// No demosaiced preview brightness or skin-tone target enters the EV solver.
    static func rawStatistics(buffer: CVPixelBuffer, dng: Data, orientation: Int,
                              subjects: [SubjectCandidate]) throws -> [SubjectCandidate] {
        guard let source = CGImageSourceCreateWithData(dng as CFData,nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],
              let tags = props[kCGImagePropertyDNGDictionary as String] as? [String:Any] else { throw SolverError.invalid("DNG 缺少黑白电平元数据，高光检查未完成") }
        return try rawStatistics(buffer:buffer,tags:tags,orientation:orientation,subjects:subjects)
    }
    static func rawStatistics(buffer: CVPixelBuffer,tags: [String:Any],orientation: Int,
                              subjects: [SubjectCandidate]) throws -> [SubjectCandidate] {
        let blacks = numbers(tags[kCGImagePropertyDNGBlackLevel as String])
        let whites = numbers(tags[kCGImagePropertyDNGWhiteLevel as String])
        let repeatDim = numbers(tags[kCGImagePropertyDNGBlackLevelRepeatDim as String])
        guard !blacks.isEmpty, let white = whites.first,
              whites.allSatisfy({ $0 == white }), white <= 65535,
              blacks.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < white }) else { throw SolverError.invalid("不支持的 DNG 黑白电平，高光检查未完成") }
        guard repeatDim.isEmpty || (repeatDim.count == 2 && repeatDim.allSatisfy({ $0.isFinite && $0 >= 1 && $0 <= 16 && $0.rounded() == $0 })) else {
            throw SolverError.invalid("DNG 黑电平重复模式无效，高光检查未完成")
        }
        let rows = repeatDim.count == 2 ? Int(repeatDim[0]) : 1
        let columns = repeatDim.count == 2 ? Int(repeatDim[1]) : 1
        guard rows > 0, columns > 0, rows*columns == blacks.count,
              numbers(tags["BlackLevelDeltaH"]).isEmpty, numbers(tags["BlackLevelDeltaV"]).isEmpty else {
            throw SolverError.invalid("不支持空间变化的 RAW 黑电平，高光检查未完成")
        }
        guard CVPixelBufferLockBaseAddress(buffer,.readOnly) == kCVReturnSuccess else { throw SolverError.invalid("无法读取 RAW 像素缓冲") }
        defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard !CVPixelBufferIsPlanar(buffer), stride >= width*2, let base = CVPixelBufferGetBaseAddress(buffer) else { throw SolverError.invalid("不支持的 Bayer 缓冲布局，高光检查未完成") }
        // A regular sparse grid can alias Bayer colors; sample all four pixels of each 2×2 block.
        let step = max(2,(max(width,height)/600/2)*2)
        var count = Array(repeating:0,count:subjects.count)
        var saturated = count
        var sum = Array(repeating:0.0,count:subjects.count)
        for by in Swift.stride(from:0,to:height-1,by:step) {
            for bx in Swift.stride(from:0,to:width-1,by:step) {
                for dy in 0...1 { for dx in 0...1 {
                    let x = bx+dx, y = by+dy
                    let upright = try RawMath.uprightPoint(x:(Double(x)+0.5)/Double(width),y:(Double(y)+0.5)/Double(height),orientation:orientation)
                    let p = base.advanced(by:y*stride+x*2).assumingMemoryBound(to:UInt16.self)
                    let value = Double(UInt16(littleEndian:p.pointee))
                    let normalized = try RawMath.normalize(value,black:blacks[(y%rows)*columns+x%columns],white:white)
                    for index in subjects.indices where subjects[index].rect.contains(x:upright.0,y:upright.1) {
                        count[index] += 1; sum[index] += normalized
                        if normalized >= 0.98 { saturated[index] += 1 }
                    }
                } }
            }
        }
        var result = subjects
        for index in result.indices where count[index] > 0 {
            result[index].highlights = RawStatistics(sampledPixels:count[index],clippedFraction:Double(saturated[index])/Double(count[index]),meanNormalized:sum[index]/Double(count[index]))
        }
        return result
    }
}
