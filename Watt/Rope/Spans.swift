//
//  Spans.swift
//  Watt
//
//  Created by David Albert on 8/1/23.
//

import Foundation

struct Span<T> {
    var range: Range<Int>
    var data: T
}

extension Span: Equatable where T: Equatable {
}

struct SpansLeaf<T>: BTreeLeaf {
    static var needsFixupOnAppend: Bool {
        true
    }

    static var minSize: Int { 32 }
    static var maxSize: Int { 64 }

    var count: Int
    var spans: [Span<T>]

    init() {
        count = 0
        spans = []
    }

    init(count: Int, spans: [Span<T>]) {
        self.count = count
        self.spans = spans
    }

    static var zero: SpansLeaf {
        SpansLeaf()
    }

    var isUndersized: Bool {
        spans.count < SpansLeaf.minSize
    }

    mutating func pushMaybeSplitting(other: SpansLeaf) -> SpansLeaf? {
        var newSpans = other.spans

        if !spans.isEmpty, let right = newSpans.first, spans.last!.range.upperBound == count && right.range.lowerBound == 0 {
            var left = spans.removeLast()
            if isEqual(left.data, right.data) {
                left.range = left.range.lowerBound..<(left.range.upperBound + right.range.count)
                newSpans.removeFirst()
            }
            spans.append(left)
        }

        for span in newSpans {
            let range = span.range.offset(by: count)
            spans.append(Span(range: range, data: span.data))
        }
        count += other.count

        if spans.count <= SpansLeaf.maxSize {
            return nil
        } else {
            let splitIndex = spans.count / 2
            let splitCount = spans[splitIndex].range.lowerBound

            var new = Array(spans[splitIndex...])
            for i in 0..<new.count {
                new[i].range = new[i].range.offset(by: -splitCount)
            }
            let newCount = count - splitCount

            spans.removeLast(new.count)
            count = splitCount

            return SpansLeaf(count: newCount, spans: new)
        }
    }

    mutating func fixup(withNext next: inout SpansLeaf<T>) -> Bool {
        if !spans.isEmpty, let right = next.spans.first, spans.last!.range.upperBound == count && right.range.lowerBound == 0 {
            var left = spans.removeLast()
            if isEqual(left.data, right.data) {
                let delta = right.range.count

                left.range = left.range.lowerBound..<(left.range.upperBound + delta)
                next.spans.removeFirst()

                for i in 0..<next.spans.count {
                    next.spans[i].range = next.spans[i].range.offset(by: -delta)
                }
                next.count -= delta

                assert(next.spans[0].range.lowerBound == 0)
            }
            spans.append(left)
            count = max(count, left.range.upperBound)
        }

        return true
    }

    subscript(bounds: Range<Int>) -> SpansLeaf {
        var s: [Span<T>] = []
        for span in spans {
            let range = span.range.clamped(to: bounds).offset(by: -bounds.lowerBound)

            if !range.isEmpty {
                s.append(Span(range: range, data: span.data))
            }
        }

        return SpansLeaf(count: bounds.count, spans: s)
    }
}

struct SpansSummary<T>: BTreeSummary {
    static func += (left: inout SpansSummary<T>, right: SpansSummary<T>) {
        left.spans += right.spans
        left.range = left.range.union(right.range)
    }

    static var zero: SpansSummary<T> {
        SpansSummary()
    }

    var spans: Int
    var range: Range<Int>

    init() {
        self.spans = 0
        self.range = 0..<0
    }

    init(summarizing leaf: SpansLeaf<T>) {
        spans = leaf.spans.count

        var range = 0..<0
        for span in leaf.spans {
            range = range.union(span.range)
        }

        self.range = range
    }
}

struct Spans<T>: BTree {
    var root: BTreeNode<SpansSummary<T>>

    var upperBound: Int {
        root.measure(using: SpansBaseMetric())
    }

    init(_ root: BTreeNode<SpansSummary<T>>) {
        self.root = root
    }

    init(_ slice: SpansSlice<T>) {
        let start = slice.bounds.lowerBound.position
        let end = slice.bounds.upperBound.position
        self.init(slice.root, slicedBy: start..<end)
    }

    func span(at offset: Int) -> Span<T>? {
        let i = root.index(at: offset)

        guard let (leaf, offsetInLeaf) = i.read() else {
            return nil
        }

        for span in leaf.spans {
            if span.range.contains(offsetInLeaf) {
                return Span(range: span.range.offset(by: i.offsetOfLeaf), data: span.data)
            }
        }

        return nil
    }

    func data(at offset: Int) -> T? {
        span(at: offset)?.data
    }

    func merging<O>(_ other: Spans<T>, transform: (T?, T?) -> O?) -> Spans<O> {
        precondition(upperBound == other.upperBound)

        var sb = SpansBuilder<O>(totalCount: upperBound)

        var left = self.makeIterator()
        var right = other.makeIterator()

        var nextLeft = left.next()
        var nextRight = right.next()

        while true {
            if nextLeft == nil && nextRight == nil {
                break
            } else if nextLeft == nil {
                let span = nextRight!

                if let transformed = transform(nil, span.data) {
                    sb.add(transformed, covering: span.range)
                }

                while let span = right.next() {
                    if let transformed = transform(nil, span.data) {
                        sb.add(transformed, covering: span.range)
                    }
                }

                break

            } else if nextRight == nil {
                let span = nextLeft!

                if let transformed = transform(span.data, nil) {
                    sb.add(transformed, covering: span.range)
                }

                while let span = left.next() {
                    if let transformed = transform(span.data, nil) {
                        sb.add(transformed, covering: span.range)
                    }
                }

                break
            }

            let spanLeft = nextLeft!
            let spanRight = nextRight!

            var rangeLeft = spanLeft.range
            var rangeRight = spanRight.range

            if !rangeLeft.overlaps(rangeRight) {
                if rangeLeft.lowerBound < rangeRight.lowerBound {
                    if let transformed = transform(spanLeft.data, nil) {
                        sb.add(transformed, covering: rangeLeft)
                    }
                    nextLeft = left.next()
                } else {
                    if let transformed = transform(spanRight.data, nil) {
                        sb.add(transformed, covering: rangeRight)
                    }
                    nextRight = right.next()
                }

                continue
            }

            if rangeLeft.lowerBound < rangeRight.lowerBound {
                let prefix = rangeLeft.prefix(rangeRight)
                if let transformed = transform(spanLeft.data, nil) {
                    sb.add(transformed, covering: prefix)
                }
                rangeLeft = rangeLeft.suffix(prefix)
            } else if rangeRight.lowerBound < rangeLeft.lowerBound {
                let prefix = rangeRight.prefix(rangeLeft)
                if let transformed = transform(spanRight.data, nil) {
                    sb.add(transformed, covering: prefix)
                }
                rangeRight = rangeRight.suffix(prefix)
            }

            assert(rangeLeft.lowerBound == rangeRight.lowerBound)

            let intersection = rangeLeft.clamped(to: rangeRight)
            assert(!intersection.isEmpty)
            if let transformed = transform(spanLeft.data, spanRight.data) {
                sb.add(transformed, covering: intersection)
            }

            rangeLeft = rangeLeft.suffix(intersection)
            rangeRight = rangeRight.suffix(intersection)

            if rangeLeft.isEmpty {
                nextLeft = left.next()
            } else {
                nextLeft = Span(range: rangeLeft, data: spanLeft.data)
            }

            if rangeRight.isEmpty {
                nextRight = right.next()
            } else {
                nextRight = Span(range: rangeRight, data: spanRight.data)
            }
        }

        return sb.build()
    }
}

extension Spans {
    struct SpansBaseMetric: BTreeMetric {
        func measure(summary: SpansSummary<T>, count: Int) -> Int {
            count
        }

        func convertToBaseUnits(_ measuredUnits: Int, in leaf: SpansLeaf<T>, edge: BTreeMetricEdge) -> Int {
            measuredUnits
        }

        func convertFromBaseUnits(_ baseUnits: Int, in leaf: SpansLeaf<T>, edge: BTreeMetricEdge) -> Int {
            baseUnits
        }

        func isBoundary(_ offset: Int, in leaf: SpansLeaf<T>, edge: BTreeMetricEdge) -> Bool {
            true
        }

        func prev(_ offset: Int, in leaf: SpansLeaf<T>, edge: BTreeMetricEdge) -> Int? {
            assert(offset >= 0)
            if offset == 0 {
                return nil
            }
            return offset - 1
        }

        func next(_ offset: Int, in leaf: SpansLeaf<T>, edge: BTreeMetricEdge) -> Int? {
            assert(offset <= leaf.count)
            if offset == leaf.count {
                return nil
            }
            return offset + 1
        }

        var canFragment: Bool {
            false
        }

        var isAtomic: Bool {
            true
        }
    }
}

// A metric counting spans. Leading boundaries are at span.range.upperBound, trailing boundaries
// are **after** span.range.upperBound-1 – i.e. trailing boundaries are at span.range.upperBound.
//
// Consider a Spans of length 10 containing 2..<4 and 7..<8:
//
// 0 1 2 3 4 5 6 7 8 9
//     ---       -
//
// Leading boundaries are at 2, 7, and 10
// Trailing boundaries are at 0, 4, and 8.
//
// count(SpansMetric(), upTo: 0) -> 0
// count(SpansMetric(), upTo: 1) -> 0
// count(SpansMetric(), upTo: 2) -> 0
// count(SpansMetric(), upTo: 3) -> 0
// count(SpansMetric(), upTo: 4) -> 1
// count(SpansMetric(), upTo: 5)  -> 1
// count(SpansMetric(), upTo: 6)  -> 1
// count(SpansMetric(), upTo: 7)  -> 1
// count(SpansMetric(), upTo: 8)  -> 2
// count(SpansMetric(), upTo: 9)  -> 2
// count(SpansMetric(), upTo: 10) -> 2
extension Spans {
    struct SpansMetric: BTreeMetric {
        func measure(summary: SpansSummary<T>, count: Int) -> Int {
            summary.spans
        }
        
        func convertToBaseUnits(_ measuredUnits: Int, in leaf: SpansLeaf<T>, edge: BTreeMetricEdge) -> Int {
            if measuredUnits == 0 {
                return 0
            }
            switch edge {
            case .leading:
                return leaf.spans[measuredUnits-1].range.lowerBound + 1
            case .trailing:
                return leaf.spans[measuredUnits-1].range.upperBound
            }
        }
        
        func convertFromBaseUnits(_ baseUnits: Int, in leaf: SpansLeaf<T>, edge: BTreeMetricEdge) -> Int {
            for i in 0..<leaf.spans.count {
                let range = leaf.spans[i].range
                let target = edge == .leading ? range.lowerBound + 1 : range.upperBound

                if baseUnits < target {
                    return i
                }
            }
            return leaf.spans.count
        }

        func isBoundary(_ offset: Int, in leaf: SpansLeaf<T>, edge: BTreeMetricEdge) -> Bool {
            let found: Bool
            switch edge {
            case .leading:
                (_, found) = leaf.spans.map(\.range.lowerBound).binarySearch(for: offset)
            case .trailing:
                (_, found) = leaf.spans.map(\.range.upperBound).binarySearch(for: offset)
            }
            return found
        }
        
        func prev(_ offset: Int, in leaf: SpansLeaf<T>, edge: BTreeMetricEdge) -> Int? {
            let bound: KeyPath<Range<Int>, Int> = edge == .leading ? \.lowerBound : \.upperBound
            let (i, _) = leaf.spans.map { $0.range[keyPath: bound] }.binarySearch(for: offset)
            if i == 0 {
                return nil
            }
            return leaf.spans[i-1].range[keyPath: bound]
        }
        
        func next(_ offset: Int, in leaf: SpansLeaf<T>, edge: BTreeMetricEdge) -> Int? {
            let bound: KeyPath<Range<Int>, Int> = edge == .leading ? \.lowerBound : \.upperBound

            let (i, found) = leaf.spans.map { $0.range[keyPath: bound] }.binarySearch(for: offset)
            assert(i >= 0 && i <= leaf.spans.count)
            if i == leaf.spans.count || (found && i == leaf.spans.count - 1) {
                return nil
            } else if found {
                return leaf.spans[i+1].range[keyPath: bound]
            }
            return leaf.spans[i].range[keyPath: bound]
        }
        
        var canFragment: Bool {
            false
        }

        var isAtomic: Bool {
            false
        }
    }
}

extension SpansSummary: BTreeDefaultMetric {
    static var defaultMetric: Spans<T>.SpansBaseMetric {
        Spans.SpansBaseMetric()
    }
}

// Not all possible indices are valid for a given Spans. Spans' base metric is an Int ranging from 0 to upperBound,
// and you can create an index for any number in that range with index(withBaseOffset:). But there can be empty
// space between individual Span elements, as well space before the first Span and after the last Span.
//
// You can slice a Spans with any index, but attempting to read a Span at and index that doesn't fall within a Span
// will trap.
//
// Additionally, because Spans is conceptually a collection of Spans, startIndex points to the start of the first
// Span, which is not necessarily 0[pos].
extension Spans: BidirectionalCollection {
    typealias Index = BTreeNode<SpansSummary<T>>.Index

    var count: Int {
        root.measure(using: SpansMetric())
    }

    var startIndex: Index {
        if count == 0 {
            return root.startIndex
        }

        var i = root.startIndex
        let (leaf, _) = i.read()!
        i.set(i.offsetOfLeaf + leaf.spans[0].range.lowerBound)
        return i
    }

    var endIndex: Index {
        if count == 0 {
            return root.startIndex
        }

        var i = root.endIndex
        let (leaf, _) = i.read()!
        i.set(i.offsetOfLeaf + leaf.spans[leaf.spans.count - 1].range.upperBound)
        return i
    }

    subscript(position: Index) -> Span<T> {
        // Let SpanSlice take care of the actual subscript logic. We use root.startIndex and root.endIndex
        // instead of startIndex and endIndex because we don't want to slice off empty space at the beginning
        // and end of self.
        self[root.startIndex..<root.endIndex][position]
    }

    subscript(bounds: Range<Index>) -> SpansSlice<T> {
        bounds.lowerBound.validate(for: root)
        bounds.upperBound.validate(for: root)

        return SpansSlice<T>(base: self, bounds: bounds)
    }

    func index(before i: consuming Index) -> Index {
        root.index(before: i, in: startIndex..<endIndex, using: SpansMetric(), edge: .leading)
    }

    func index(after i: Index) -> Index {
        root.index(after: i, in: startIndex..<endIndex, using: SpansMetric(), edge: .leading)
    }

    func index(_ i: consuming Index, offsetBy distance: Int) -> Index {
        root.index(i, offsetBy: distance, in: startIndex..<endIndex, using: SpansMetric(), edge: .leading)
    }

    func index(_ i: consuming Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
        root.index(i, offsetBy: distance, limitedBy: limit, in: startIndex..<endIndex, using: SpansMetric(), edge: .leading)
    }

    func distance(from start: Index, to end: Index) -> Int {
        root.distance(from: start, to: end, in: startIndex..<endIndex, using: SpansMetric())
    }
}

extension Spans {
    func index(roundingDown i: consuming Index) -> Index {
        root.index(roundingDown: i, in: startIndex..<endIndex, using: SpansMetric(), edge: .leading)
    }

    func index(withBaseOffset offset: Int) -> Index {
        root.index(at: offset)
    }
}

struct SpansSlice<T> {
    var base: Spans<T>
    var bounds: Range<Index>

    init(base: Spans<T>, bounds: Range<Index>) {
        self.base = base
        self.bounds = bounds
    }

    var root: BTreeNode<SpansSummary<T>> {
        base.root
    }

    var upperBound: Int {
        root.distance(from: bounds.lowerBound, to: bounds.upperBound, in: bounds.lowerBound..<bounds.upperBound, using: Spans.SpansBaseMetric())
    }
}

extension SpansSlice: BidirectionalCollection {
    typealias Index = Spans<T>.Index

    var count: Int {
        root.count(in: bounds, using: Spans.SpansMetric())
    }

    var startIndex: Index {
        if count == 0 {
            return bounds.lowerBound
        }

        var i = bounds.lowerBound
        let (leaf, offsetInLeaf) = i.read()!
        let span = leaf.spans.first { offsetInLeaf < $0.range.upperBound }!
        i.set(Swift.max(i.offsetOfLeaf + span.range.lowerBound, bounds.lowerBound.position))
        return i
    }

    var endIndex: Index {
        if count == 0 {
            return bounds.lowerBound
        }

        var i = bounds.upperBound
        let (leaf, offsetInLeaf) = i.read()!
        let span = leaf.spans.reversed().first { $0.range.lowerBound <= offsetInLeaf }!
        i.set(Swift.min(i.offsetOfLeaf + span.range.upperBound, bounds.upperBound.position))
        return i
    }

    subscript(position: Index) -> Span<T> {
        position.validate(for: base.root)
        precondition(position.position >= bounds.lowerBound.position && position.position < bounds.upperBound.position)

        let (leaf, offsetInLeaf) = position.read()!

        for span in leaf.spans {
            if span.range.contains(offsetInLeaf) {
                let rangeInRoot = span.range.offset(by: position.offsetOfLeaf)
                let rangeInSlice = rangeInRoot.clamped(to: bounds.lowerBound.position..<bounds.upperBound.position).offset(by: -bounds.lowerBound.position)

                return Span(range: rangeInSlice, data: span.data)
            }
        }

        fatalError("Didn't find span at \(position) in \(self).")
    }

    subscript(r: Range<Index>) -> SpansSlice {
        r.lowerBound.validate(for: base.root)
        r.upperBound.validate(for: base.root)

        precondition(r.lowerBound.position >= bounds.lowerBound.position)
        precondition(r.upperBound.position <= bounds.upperBound.position)

        return SpansSlice(base: base, bounds: r)
    }

    func index(before i: Index) -> Index {
        root.index(before: i, in: startIndex..<endIndex, using: Spans.SpansMetric(), edge: .leading)
    }

    func index(after i: Index) -> Index {
        root.index(after: i, in: startIndex..<endIndex, using: Spans.SpansMetric(), edge: .leading)
    }

    func index(_ i: Index, offsetBy distance: Int) -> Index {
        root.index(i, offsetBy: distance, in: startIndex..<endIndex, using: Spans.SpansMetric(), edge: .leading)
    }

    func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
        root.index(i, offsetBy: distance, limitedBy: limit, in: startIndex..<endIndex, using: Spans.SpansMetric(), edge: .leading)
    }

    func distance(from start: Index, to end: Index) -> Int {
        root.distance(from: start, to: end, in: startIndex..<endIndex, using: Spans.SpansMetric())
    }
}

extension SpansSlice {
    func index(roundingDown i: Index) -> Index {
        root.index(roundingDown: i, in: startIndex..<endIndex, using: Spans.SpansMetric(), edge: .leading)
    }

    func index(withBaseOffset offset: Int) -> Index {
        base.index(withBaseOffset: startIndex.position + offset)
    }
}

struct SpansBuilder<T> {
    var b: BTreeBuilder<Spans<T>>
    var leaf: SpansLeaf<T>
    var offsetOfLeaf: Int
    var totalCount: Int

    init(totalCount: Int) {
        self.b = BTreeBuilder<Spans>()
        self.leaf = SpansLeaf()
        self.offsetOfLeaf = 0
        self.totalCount = totalCount
    }

    mutating func add(_ data: T, covering range: Range<Int>) {
        precondition(range.lowerBound >= offsetOfLeaf + (leaf.spans.last?.range.upperBound ?? 0))

        // merge with previous span if T is equatable and the previous span is equal and adajacent.
        if let last = leaf.spans.last, last.range.upperBound == range.lowerBound - offsetOfLeaf {
            if isEqual(last.data, data) {
                leaf.spans[leaf.spans.count - 1].range = last.range.lowerBound..<(last.range.upperBound + range.count)
                totalCount = max(totalCount, range.upperBound)
                return
            }
        }

        if leaf.spans.count == SpansLeaf<T>.maxSize {
            leaf.count = range.lowerBound - offsetOfLeaf
            self.offsetOfLeaf = range.lowerBound
            b.push(leaf: leaf)
            leaf = SpansLeaf()
        }

        leaf.spans.append(Span(range: range.offset(by: -offsetOfLeaf), data: data))
        totalCount = max(totalCount, range.upperBound)
    }

    consuming func build() -> Spans<T> {
        leaf.count = totalCount - offsetOfLeaf
        b.push(leaf: leaf)

        return b.build()
    }
}

fileprivate extension Range {
    func union(_ other: Range<Bound>) -> Range<Bound> {
        let start = Swift.min(lowerBound, other.lowerBound)
        let end = Swift.max(upperBound, other.upperBound)

        return start..<end
    }

    // The porton of `self` that comes before `other`.
    // If `other` starts before `self`, returns an empty
    // starting at other.lowerBounds.
    func prefix(_ other: Range) -> Range {
        return Swift.min(lowerBound, other.lowerBound)..<Swift.min(upperBound, other.lowerBound)
    }

    // The portion of `self` that comes after `other`.
    // If `other` ends after `self`, returns an empty
    // range ending at other.upperBound.
    func suffix(_ other: Range) -> Range {
        return Swift.max(lowerBound, other.upperBound)..<Swift.max(upperBound, other.upperBound)
    }
}
