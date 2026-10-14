import Foundation

public struct RawStatistics: Codable, Sendable, Equatable {
    public var sampledPixels: Int
    public var clippedFraction: Double
    public var meanNormalized: Double
    public init(sampledPixels: Int, clippedFraction: Double, meanNormalized: Double) {
        self.sampledPixels = sampledPixels; self.clippedFraction = clippedFraction; self.meanNormalized = meanNormalized
    }
}
public enum RawMath {
    public static func normalize(_ value: Double, black: Double, white: Double) throws -> Double {
        guard [value,black,white].allSatisfy(\.isFinite), white > black, black >= 0 else { throw SolverError.invalid("RAW 黑白电平无效") }
        return min(1,max(0,(value-black)/(white-black)))
    }
    /// Map upright top-left coordinates into unrotated sensor coordinates (EXIF 1…8).
    public static func sensorPoint(x: Double, y: Double, orientation: Int) throws -> (Double,Double) {
        guard x.isFinite,y.isFinite,(0...1).contains(x),(0...1).contains(y) else { throw SolverError.invalid("主体坐标无效") }
        switch orientation {
        case 1: return (x,y)
        case 2: return (1-x,y)
        case 3: return (1-x,1-y)
        case 4: return (x,1-y)
        case 5: return (y,x)
        case 6: return (y,1-x)
        case 7: return (1-y,1-x)
        case 8: return (1-y,x)
        default: throw SolverError.invalid("不支持的照片旋转方向")
        }
    }
    public static func uprightPoint(x: Double, y: Double, orientation: Int) throws -> (Double,Double) {
        let inverse = orientation == 6 ? 8 : orientation == 8 ? 6 : orientation
        return try sensorPoint(x: x,y: y,orientation: inverse)
    }
    public static func statistics(values: [Double]) throws -> RawStatistics {
        guard !values.isEmpty, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw SolverError.invalid("没有有效 RAW 像素") }
        return RawStatistics(sampledPixels: values.count,
                             clippedFraction: Double(values.filter { $0 >= 0.98 }.count)/Double(values.count),
                             meanNormalized: values.reduce(0,+)/Double(values.count))
    }
}
