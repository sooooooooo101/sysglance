/// 固定容量のリングバッファ。容量を超えたら最も古い要素から捨てる。
public struct RingBuffer<Element> {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0  // 最も古い要素の位置（満杯時のみ意味を持つ）

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// 古い順
    public var elements: [Element] {
        Array(storage[head...]) + Array(storage[..<head])
    }

    /// 新しい方から最大 n 件（古い順で返す）
    public func suffix(_ n: Int) -> [Element] {
        Array(elements.suffix(n))
    }

    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage[(head + storage.count - 1) % storage.count]
    }
}

extension RingBuffer: Sendable where Element: Sendable {}
