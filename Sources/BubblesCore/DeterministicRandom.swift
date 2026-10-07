import Foundation

public struct DeterministicRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }

    public mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    public mutating func shuffled<T>(_ input: [T]) -> [T] {
        guard input.count > 1 else { return input }
        var copy = input
        for i in stride(from: copy.count - 1, through: 1, by: -1) {
            let j = int(in: 0...i)
            if i != j { copy.swapAt(i, j) }
        }
        return copy
    }
}

public enum SeedMixer {
    public static func hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    public static func mix(_ parts: UInt64...) -> UInt64 {
        var x: UInt64 = 0xD6E8FEB86659FD93
        for part in parts {
            x ^= part &+ 0x9E3779B97F4A7C15 &+ (x << 6) &+ (x >> 2)
        }
        return x == 0 ? 1 : x
    }
}
