import Foundation

/// Decides who an unpinned chore belongs to in a given period. Pinned chores never consult this.
/// Fairness rules are not final; keep implementations pure and deterministic so both phones agree.
public protocol Rotation: Sendable {
    func assignee(for chore: Chore, periodIndex: Int) -> Person
}

/// Default: each chore alternates between the two people every period. The starting person is derived
/// from a stable hash of the chore id, so roughly half the chores start with Anne and half with Wes.
public struct RoundRobinRotation: Rotation {
    public init() {}

    public func assignee(for chore: Chore, periodIndex: Int) -> Person {
        let start = Int(RoundRobinRotation.fnv1a(chore.id) & 1)
        let slot = (start + periodIndex) & 1
        return slot == 0 ? .anne : .wes
    }

    /// FNV-1a 64-bit. Swift's `hashValue` is randomized per process and must not be used for this.
    static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
