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
        for span in other.spans {
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
        root.count
    }

    var count: Int {
        root.summary.spans
    }

    init(_ root: BTreeNode<SpansSummary<T>>) {
        self.root = root
    }

    subscript(_ bounds: Range<Int>) -> Spans<T> {
        Spans(root, slicedBy: bounds)
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

extension Spans: Sequence {
    struct Iterator: IteratorProtocol {
        var base: Spans<T>
        var i: Index
        var ii: Int

        init(_ spans: Spans<T>) {
            self.base = spans
            self.i = spans.root.startIndex
            self.ii = 0
        }

        mutating func next() -> Span<T>? {
            guard let (leaf, _) = i.read() else {
                return nil
            }

            if leaf.spans.isEmpty {
                return nil
            }

            let span = leaf.spans[ii]
            let offsetOfLeaf = i.offsetOfLeaf
            ii += 1
            if ii == leaf.spans.count {
                _ = i.nextLeaf()
                ii = 0
            }

            return Span(range: span.range.offset(by: offsetOfLeaf), data: span.data)
        }
    }

    func makeIterator() -> Iterator {
        Iterator(self)
    }
}

// Collection
extension Spans {
    typealias Index = BTreeNode<SpansSummary<T>>.Index

    func index(at offset: Int) -> Index {
        Index(offsetBy: offset, in: root)
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

    mutating func push(_ other: Spans<T>) {
        push(other, slicedBy: 0..<other.upperBound)
    }

    mutating func push(_ other: Spans<T>, slicedBy range: Range<Int>) {
        precondition(range.lowerBound >= 0 && range.upperBound <= other.upperBound)

        if other.upperBound == 0 || range.isEmpty {
            return
        }

        let sliced = Spans(other.root, slicedBy: range)
        var lowerBoundToPush = 0

        // prefix == what's on the builder when we're first called
        let prefixLength = offsetOfLeaf + (leaf.spans.last?.range.upperBound ?? 0)

        // leaf.spans is only empty when there's nothing on the stack
        assert(b.stack.isEmpty || !leaf.spans.isEmpty)

        if !leaf.spans.isEmpty {
            var iter = sliced.makeIterator()
            var span = iter.next()

            if span != nil, leaf.spans.count == SpansLeaf<T>.maxSize {
                let adjustedRange = span!.range.offset(by: prefixLength)
                let last = leaf.spans.last!
                
                if last.range.upperBound == adjustedRange.lowerBound - offsetOfLeaf && isEqual(last.data, span!.data) {
                    leaf.spans[leaf.spans.count - 1].range = last.range.lowerBound..<(last.range.upperBound + adjustedRange.count)
                    totalCount = max(totalCount, adjustedRange.upperBound)
                    // Note: not adjusted. We'll use this to re-slice sliced later.
                    lowerBoundToPush = span!.range.upperBound
                    span = iter.next()
                }
            } else {
                while span != nil, leaf.spans.count < SpansLeaf<T>.maxSize {
                    add(span!.data, covering: span!.range.offset(by: prefixLength))
                    // Note: not adjusted. See below.
                    lowerBoundToPush = span!.range.upperBound
                    span = iter.next()
                }
            }

            // if there's nothing left in sliced, we're done
            guard let span else {
                return
            }

            assert(leaf.spans.count == SpansLeaf<T>.maxSize)

            let adjustedRange = span.range.offset(by: prefixLength)
            leaf.count = adjustedRange.lowerBound - offsetOfLeaf
            offsetOfLeaf = adjustedRange.lowerBound
            b.push(leaf: leaf)
        }

        // split sliced into a left tree, and its final leaf
        let end = sliced.root.endIndex

        let upperBoundToPush = max(end.offsetOfLeaf, lowerBoundToPush)
        offsetOfLeaf = prefixLength + upperBoundToPush
        var r = sliced.root
        b.push(&r, slicedBy: lowerBoundToPush..<upperBoundToPush)

        // Pretty sure this will always be true at this point. Either
        // we returned early because other or range were empty, or we
        // returned early in the `guard let span { else } return above.
        assert(end.position - upperBoundToPush > 0)

        let rest = Spans(sliced.root, slicedBy: upperBoundToPush..<end.position)
        assert(rest.root.height == 0)
        leaf = rest.root.leaf
        totalCount = max(totalCount, offsetOfLeaf + leaf.count)
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
