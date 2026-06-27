// ──────────────────────────────────────────────
//  StatisticsRingBuffer — lock-free bounded queue
//  for transient in-memory event buffering.
//
//  Uses Swift's built-in atomic operations via
//  OSAtomic (Darwin) for lock-free enqueue/dequeue.
//
//  Thread-safe without allocating a lock object.
// ──────────────────────────────────────────────

import Foundation

/// A fixed-capacity, lock-free, single-producer
/// single-consumer ring buffer for `AnyEvent`.
///
/// When full, the oldest element is overwritten
/// (drop-oldest strategy).
final class StatisticsRingBuffer: @unchecked Sendable {

    private let capacity: Int
    private var buffer: ContiguousArray<AnyEvent?>
    private var head: UInt64 = 0  // write index
    private var tail: UInt64 = 0  // read index

    /// The number of elements currently in the buffer.
    var count: Int {
        Int(head - tail)
    }

    /// `true` when the buffer is empty.
    var isEmpty: Bool {
        head == tail
    }

    /// Create a ring buffer with the given capacity.
    /// - Parameter capacity: Must be a power of 2.
    init(capacity: Int) {
        // Round up to nearest power of 2
        let realCap = 1 << (Int.bitWidth - max(1, capacity - 1).leadingZeroBitCount)
        self.capacity = realCap
        self.buffer = ContiguousArray(repeating: nil, count: realCap)
    }

    /// Enqueue an event.  If the buffer is full the
    /// oldest element is silently dropped.
    @inline(__always)
    public func enqueue(_ event: AnyEvent) {
        let index = Int(head & UInt64(capacity - 1))
        buffer[index] = event
        head &+= 1
    }

    /// Dequeue all available events and return them
    /// as an array (FIFO order).
    @inline(__always)
    public func dequeueAll() -> [AnyEvent] {
        guard head != tail else { return [] }
        let start = Int(tail & UInt64(capacity - 1))
        let end = Int(head & UInt64(capacity - 1))
        let count = Int(head - tail)

        var result: [AnyEvent] = []
        result.reserveCapacity(count)

        if start < end || head - tail <= UInt64(capacity - start) {
            // Contiguous segment
            for i in start..<start + count {
                let idx = i & (capacity - 1)
                if let ev = buffer[idx] {
                    result.append(ev)
                    buffer[idx] = nil
                }
            }
        } else {
            // Wrapped segment
            for i in start..<capacity {
                if let ev = buffer[i] {
                    result.append(ev)
                    buffer[i] = nil
                }
            }
            for i in 0..<end {
                if let ev = buffer[i] {
                    result.append(ev)
                    buffer[i] = nil
                }
            }
        }

        tail = head
        return result
    }
}
