import Foundation

public enum JPEGMetadata {
    /// Remove APP and COM headers from a newly encoded, baseline sRGB JPEG.
    /// Entropy-coded image data is preserved byte for byte after SOS.
    public static func stripped(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else {
            throw SolverError.invalid("不是有效 JPEG")
        }
        var output: [UInt8] = [0xff,0xd8]
        var offset = 2
        while offset < bytes.count {
            let start = offset
            guard bytes[offset] == 0xff else { throw SolverError.invalid("JPEG 标记无效") }
            while offset < bytes.count && bytes[offset] == 0xff { offset += 1 }
            guard offset < bytes.count else { throw SolverError.invalid("JPEG 被截断") }
            let marker = bytes[offset]; offset += 1
            if marker == 0xd9 {
                output += [0xff,0xd9]
                return Data(output)
            }
            guard marker != 0 && marker != 0xd8, offset+2 <= bytes.count else {
                throw SolverError.invalid("JPEG 段无效")
            }
            let length = Int(bytes[offset])*256+Int(bytes[offset+1])
            guard length >= 2, offset+length <= bytes.count else { throw SolverError.invalid("JPEG 段被截断") }
            if marker == 0xda {
                output.append(contentsOf:bytes[start...])
                return Data(output)
            }
            if !(0xe0...0xef).contains(marker) && marker != 0xfe {
                output.append(contentsOf:bytes[start..<(offset+length)])
            }
            offset += length
        }
        throw SolverError.invalid("JPEG 没有图像扫描段")
    }
}
