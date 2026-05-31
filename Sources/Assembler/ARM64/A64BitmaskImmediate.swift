import Foundation

internal enum A64BitmaskImmediate {
    static func encode(_ value: UInt64, width: Int) -> (n: UInt32, immr: UInt32, imms: UInt32)? {
        let fullMask: UInt64 = width == 64 ? UInt64.max : 0xffff_ffff
        let value = value & fullMask
        guard value != 0, value != fullMask else { return nil }

        for elementSize in [2, 4, 8, 16, 32, 64] where elementSize <= width {
            let elementMask = mask(width: elementSize)
            let element = value & elementMask
            guard replicate(element, elementSize: elementSize, width: width) == value else { continue }

            for onesLength in 1..<elementSize {
                let ones = mask(width: onesLength)
                for rotation in 0..<elementSize {
                    if rotateRight(ones, by: rotation, width: elementSize) == element {
                        let immr = UInt32(rotation)
                        let immsValue = (((~(elementSize - 1)) << 1) | (onesLength - 1)) & 0x3f
                        let imms = UInt32(immsValue)
                        let n: UInt32 = elementSize == 64 ? 1 : 0
                        return (n, immr, imms)
                    }
                }
            }
        }

        return nil
    }

    static func decode(n: UInt32, immr: UInt32, imms: UInt32, width: Int) -> UInt64? {
        let combined = (Int(n) << 6) | (Int(~imms) & 0x3f)
        var len = -1
        for index in stride(from: 6, through: 0, by: -1) where (combined >> index) & 1 == 1 {
            len = index
            break
        }
        guard len >= 1 else { return nil }
        let elementSize = 1 << len
        guard elementSize <= width else { return nil }
        let levels = UInt32(elementSize - 1)
        let s = imms & levels
        let r = immr & levels
        guard s != levels else { return nil }
        let onesLength = Int(s) + 1
        let ones = mask(width: onesLength)
        let element = rotateRight(ones, by: Int(r), width: elementSize)
        return replicate(element, elementSize: elementSize, width: width)
    }

    static func mask(width: Int) -> UInt64 {
        width >= 64 ? UInt64.max : ((UInt64(1) << UInt64(width)) - 1)
    }

    static func replicate(_ value: UInt64, elementSize: Int, width: Int) -> UInt64 {
        var result: UInt64 = 0
        let element = value & mask(width: elementSize)
        var shift = 0
        while shift < width {
            result |= element << UInt64(shift)
            shift += elementSize
        }
        return result & mask(width: width)
    }

    static func rotateRight(_ value: UInt64, by amount: Int, width: Int) -> UInt64 {
        let amount = amount % width
        let value = value & mask(width: width)
        if amount == 0 { return value }
        return ((value >> UInt64(amount)) | (value << UInt64(width - amount))) & mask(width: width)
    }
}

