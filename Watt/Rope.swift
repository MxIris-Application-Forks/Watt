//
//  Rope.swift
//
//
//  Created by David Albert on 6/21/23.
//

import Foundation

// MARK: - Core data structures

// a rope made out of a B-tree
// internal nodes are order 8: 4...8 children (see BTree.swift)
// leaf nodes are order 1024: 511..<1024 elements (characters), unless it's root, then 0..<1024 (see Chunk.swift)

struct Rope: BTree {
    var root: BTreeNode<RopeSummary>

    init() {
        self.root = BTreeNode<RopeSummary>()
    }

    init(_ root: BTreeNode<RopeSummary>) {
        self.root = root
    }
}

struct RopeSummary: BTreeSummary {
    var utf16: Int
    var scalars: Int
    var chars: Int
    var newlines: Int

    static func += (left: inout RopeSummary, right: RopeSummary) {
        left.utf16 += right.utf16
        left.scalars += right.scalars
        left.chars += right.chars
        left.newlines += right.newlines
    }

    static var zero: RopeSummary {
        RopeSummary()
    }

    init() {
        self.utf16 = 0
        self.scalars = 0
        self.chars = 0
        self.newlines = 0
    }

    init(summarizing chunk: Chunk) {
        self.utf16 = chunk.string.utf16.count
        self.scalars = chunk.string.unicodeScalars.count
        self.chars = chunk.characters.count

        self.newlines = chunk.string.withExistingUTF8 { buf in
            countNewlines(in: buf[...])
        }
    }
}

extension RopeSummary: BTreeDefaultMetric {
    static var defaultMetric: Rope.UTF8Metric { Rope.UTF8Metric() }
}


struct Chunk: BTreeLeaf {
    static var needsFixupOnAppend: Bool {
        true
    }

    // measured in base units
    static let minSize = 511
    static let maxSize = 1023

    static var zero: Chunk {
        Chunk()
    }

    var string: String

    // The number of bytes that continue a grapheme from
    // the previous chunk.
    var prefixCount: Int

    // does the last grapheme continue on to the next Chunk
    var lastCharSplits: Bool

    // a breaker ready to consume the first
    // scalar in the Chunk. Used for prefix
    // calculation in pushMaybeSplitting(other:)
    // and fixup(withNext:)
    var breaker: Rope.GraphemeBreaker

    var count: Int {
        string.utf8.count
    }

    var isUndersized: Bool {
        count < Chunk.minSize
    }

    var firstBreak: String.Index {
        string.utf8Index(at: prefixCount)
    }

    var lastBreak: String.Index {
        if string.isEmpty {
            return string.startIndex
        } else {
            return string.index(before: string.endIndex)
        }
    }

    var characters: Substring {
        string[firstBreak...]
    }

    init() {
        self.string = ""
        self.prefixCount = 0
        self.lastCharSplits = false
        self.breaker = Rope.GraphemeBreaker()
    }

    init(_ substring: Substring, breaker b: inout Rope.GraphemeBreaker) {
        let s = String(substring)
        assert(s.isContiguousUTF8)
        assert(s.utf8.count <= Chunk.maxSize)

        // save the breaker at the start of the chunk
        self.breaker = b

        self.string = s
        self.prefixCount = consumeAndFindPrefixCount(in: s, using: &b)
        self.lastCharSplits = false
    }

    mutating func pushMaybeSplitting(other: Chunk) -> Chunk? {
        string += other.string
        var b = breaker

        if string.utf8.count <= Chunk.maxSize {
            prefixCount = consumeAndFindPrefixCount(in: string, using: &b)
            lastCharSplits = other.lastCharSplits
            return nil
        } else {
            let i = boundaryForMerge(string[...])

            let rest = String(string.unicodeScalars[i...])
            string = String(string.unicodeScalars[..<i])

            prefixCount = consumeAndFindPrefixCount(in: string, using: &b)
            let next = Chunk(rest[...], breaker: &b)
            if next.prefixCount > 0 {
                lastCharSplits = true
            }
            return next
        }
    }

    mutating func fixup(withNext next: inout Chunk) -> Bool {
        let s = next.string
        var i = s.startIndex
        var first: String.Index?

        var old = next.breaker
        var new = breaker
        new.consume(self.string[...])

        next.breaker = new

        while i < s.unicodeScalars.endIndex {
            let scalar = s.unicodeScalars[i]
            let a = old.hasBreak(before: scalar)
            let b = new.hasBreak(before: scalar)

            if b {
                first = first ?? i
            }

            if a && b {
                // Found the same break. We're done
                break
            } else if !a && !b && old == new {
                // GraphemeBreakers are in the same state. We're done.
                break
            }

            i = s.unicodeScalars.index(after: i)
        }

        if let first {
            // We found a new first break
            next.prefixCount = s.utf8.distance(from: s.startIndex, to: first)
        } else if i >= next.lastBreak {
            // We made it up through lastBreak without finding any breaks
            // and now we're in sync. We know there are no more breaks
            // ahead of us, which means there are no breaks in the chunk.

            // N.b. there is a special case where lastBreak < firstBreak –
            // when there were no breaks in the chunk previously. In that
            // case lastBreak == startIndex and firstBreak == endIndex.

            // But this code works for that situation too. If there were no
            // breaks in the chunk previously, and we get in sync anywhere
            // in the chunk without finding a break, we know there are still
            // no breaks in the chunk, so this code is a no-op.

            next.prefixCount = s.utf8.count
        } else if i >= next.firstBreak {
            // We made it up through firstBreak without finding any breaks
            // but we got in sync before lastBreak. Find a new firstBreak:

            let j = s.unicodeScalars.index(after: i)
            var tmp = new
            let first = tmp.firstBreak(in: s[j...])!.lowerBound
            next.prefixCount = s.utf8.distance(from: s.startIndex, to: first)

            // If this is false, there's a bug in the code, or my assumptions are wrong.
            assert(next.firstBreak <= next.lastBreak)
        }

        // There's an implicit else clause to the above– we're in sync, and we
        // didn't even get to the old firstBreak. This means the breaks didn't
        // change at all.


        lastCharSplits = next.prefixCount > 0

        // We're done if we synced up before the end of the chunk.
        return i < s.endIndex
    }

    subscript(bounds: Range<Int>) -> Chunk {
        let start = string.utf8Index(at: bounds.lowerBound).samePosition(in: string.unicodeScalars)
        let end = string.utf8Index(at: bounds.upperBound).samePosition(in: string.unicodeScalars)

        guard let start, let end else {
            fatalError("invalid unicode scalar offsets")
        }

        var b = breaker
        b.consume(string[string.startIndex..<start])
        return Chunk(string[start..<end], breaker: &b)
    }

    func isValidUnicodeScalarIndex(_ i: String.Index) -> Bool {
        i.samePosition(in: string.unicodeScalars) != nil
    }

    func isValidCharacterIndex(_ i: String.Index) -> Bool {
        i == characters._index(roundingDown: i)
    }
}

fileprivate func consumeAndFindPrefixCount(in string: String, using breaker: inout Rope.GraphemeBreaker) -> Int {
    guard let r = breaker.firstBreak(in: string[...]) else {
        // uncommon, no character boundaries
        return string.utf8.count
    }

    breaker.consume(string[r.upperBound...])

    return string.utf8.distance(from: string.startIndex, to: r.lowerBound)
}

// MARK: - Metrics

extension Rope {
    // The base metric, which measures UTF-8 code units.
    struct UTF8Metric: BTreeMetric {
        func measure(summary: RopeSummary, count: Int) -> Int {
            count
        }

        func convertToBaseUnits(_ measuredUnits: Int, in leaf: Chunk) -> Int {
            measuredUnits
        }

        func convertFromBaseUnits(_ baseUnits: Int, in leaf: Chunk) -> Int {
            baseUnits
        }

        func isBoundary(_ offset: Int, in chunk: Chunk) -> Bool {
            true
        }

        func prev(_ offset: Int, in chunk: Chunk) -> Int? {
            assert(offset > 0)
            return offset - 1
        }

        func next(_ offset: Int, in chunk: Chunk) -> Int? {
            assert(offset < chunk.count)
            return offset + 1
        }

        var canFragment: Bool {
            false
        }

        var type: BTreeMetricType {
            .atomic
        }
    }
}

extension BTreeMetric<RopeSummary> where Self == Rope.UTF8Metric {
    static var utf8: Rope.UTF8Metric { Rope.UTF8Metric() }
}

// Rope doesn't have a true UTF-16 view like String does. Instead the
// UTF16Metric is mostly useful for counting UTF-16 code units. Its
// prev and next operate the same as UnicodeScalarMetric. Next() and prev()
// will "skip" trailing surrogates, jumping to the next Unicode scalar
// boundary. "Skip" is in quotes because there are not actually any leading
// or trailing surrogates in Rope's storage. It's just Unicode scalars that
// are encoded as UTF-8.
extension Rope {
    struct UTF16Metric: BTreeMetric {
        func measure(summary: RopeSummary, count: Int) -> Int {
            summary.utf16
        }

        func convertToBaseUnits(_ measuredUnits: Int, in chunk: Chunk) -> Int {
            let startIndex = chunk.string.startIndex

            let i = chunk.string.utf16Index(at: measuredUnits)
            return chunk.string.utf8.distance(from: startIndex, to: i)
        }

        func convertFromBaseUnits(_ baseUnits: Int, in chunk: Chunk) -> Int {
            let startIndex = chunk.string.startIndex
            let i = chunk.string.utf8Index(at: baseUnits)

            return chunk.string.utf16.distance(from: startIndex, to: i)
        }

        func isBoundary(_ offset: Int, in chunk: Chunk) -> Bool {
            let i = chunk.string.utf8Index(at: offset)
            return chunk.isValidUnicodeScalarIndex(i)
        }

        func prev(_ offset: Int, in chunk: Chunk) -> Int? {
            assert(offset > 0)

            let startIndex = chunk.string.startIndex
            let current = chunk.string.utf8Index(at: offset)

            var target = chunk.string.unicodeScalars._index(roundingDown: current)
            if target == current {
                target = chunk.string.unicodeScalars.index(before: target)
            }
            return chunk.string.utf8.distance(from: startIndex, to: target)
        }

        func next(_ offset: Int, in chunk: Chunk) -> Int? {
            assert(offset < chunk.count)

            let startIndex = chunk.string.startIndex
            let current = chunk.string.utf8Index(at: offset)

            let target = chunk.string.unicodeScalars.index(after: current)
            return chunk.string.utf8.distance(from: startIndex, to: target)
        }

        var canFragment: Bool {
            false
        }

        var type: BTreeMetricType {
            .atomic
        }
    }
}

extension BTreeMetric<RopeSummary> where Self == Rope.UTF16Metric {
    static var utf16: Rope.UTF16Metric { Rope.UTF16Metric() }
}

extension Rope {
    struct UnicodeScalarMetric: BTreeMetric {
        func measure(summary: RopeSummary, count: Int) -> Int {
            summary.scalars
        }

        func convertToBaseUnits(_ measuredUnits: Int, in chunk: Chunk) -> Int {
            let startIndex = chunk.string.startIndex

            let i = chunk.string.unicodeScalarIndex(at: measuredUnits)
            return chunk.string.utf8.distance(from: startIndex, to: i)
        }

        func convertFromBaseUnits(_ baseUnits: Int, in chunk: Chunk) -> Int {
            let startIndex = chunk.string.startIndex
            let i = chunk.string.utf8Index(at: baseUnits)

            return chunk.string.unicodeScalars.distance(from: startIndex, to: i)
        }

        func isBoundary(_ offset: Int, in chunk: Chunk) -> Bool {
            let i = chunk.string.utf8Index(at: offset)
            return chunk.isValidUnicodeScalarIndex(i)
        }

        func prev(_ offset: Int, in chunk: Chunk) -> Int? {
            assert(offset > 0)

            let startIndex = chunk.string.startIndex
            let current = chunk.string.utf8Index(at: offset)

            var target = chunk.string.unicodeScalars._index(roundingDown: current)
            if target == current {
                target = chunk.string.unicodeScalars.index(before: target)
            }
            return chunk.string.utf8.distance(from: startIndex, to: target)
        }

        func next(_ offset: Int, in chunk: Chunk) -> Int? {
            assert(offset < chunk.count)

            let startIndex = chunk.string.startIndex
            let current = chunk.string.utf8Index(at: offset)

            let target = chunk.string.unicodeScalars.index(after: current)
            return chunk.string.utf8.distance(from: startIndex, to: target)
        }

        var canFragment: Bool {
            false
        }

        var type: BTreeMetricType {
            .atomic
        }
    }
}

extension BTreeMetric<RopeSummary> where Self == Rope.UnicodeScalarMetric {
    static var unicodeScalars: Rope.UnicodeScalarMetric { Rope.UnicodeScalarMetric() }
}

extension Rope {
    struct CharacterMetric: BTreeMetric {
        func measure(summary: RopeSummary, count: Int) -> Int {
            summary.chars
        }

        func convertToBaseUnits(_ measuredUnits: Int, in chunk: Chunk) -> Int {
            assert(measuredUnits <= chunk.characters.count)

            let startIndex = chunk.characters.startIndex
            let i = chunk.characters.index(startIndex, offsetBy: measuredUnits)

            assert(chunk.isValidCharacterIndex(i))

            return chunk.prefixCount + chunk.string.utf8.distance(from: startIndex, to: i)
        }

        func convertFromBaseUnits(_ baseUnits: Int, in chunk: Chunk) -> Int {
            let startIndex = chunk.characters.startIndex
            let i = chunk.string.utf8Index(at: baseUnits)

            return chunk.characters.distance(from: startIndex, to: i)
        }

        func isBoundary(_ offset: Int, in chunk: Chunk) -> Bool {
            assert(offset < chunk.count)

            if offset < chunk.prefixCount {
                return false
            }

            let i = chunk.string.utf8Index(at: offset)
            return chunk.isValidCharacterIndex(i)
        }

        func prev(_ offset: Int, in chunk: Chunk) -> Int? {
            assert(offset > 0)

            let startIndex = chunk.string.startIndex
            let current = chunk.string.utf8Index(at: offset)

            if current <= chunk.firstBreak {
                return nil
            }

            var target = chunk.string._index(roundingDown: current)
            if target == current {
                target = chunk.string.index(before: target)
            }

            return chunk.string.utf8.distance(from: startIndex, to: target)
        }

        func next(_ offset: Int, in chunk: Chunk) -> Int? {
            assert(offset < chunk.count)

            let startIndex = chunk.string.startIndex
            let current = chunk.string.utf8Index(at: offset)

            if current >= chunk.lastBreak && chunk.lastCharSplits {
                return nil
            }

            let target = chunk.string.index(after: current)
            return chunk.string.utf8.distance(from: startIndex, to: target)
        }

        var canFragment: Bool {
            true
        }

        var type: BTreeMetricType {
            .atomic
        }
    }
}

extension BTreeMetric<RopeSummary> where Self == Rope.CharacterMetric {
    static var characters: Rope.CharacterMetric { Rope.CharacterMetric() }
}

extension Rope {
    struct NewlinesMetric: BTreeMetric {
        func measure(summary: RopeSummary, count: Int) -> Int {
            summary.newlines
        }

        func convertToBaseUnits(_ measuredUnits: Int, in chunk: Chunk) -> Int {
            let nl = UInt8(ascii: "\n")

            var offset = 0
            var count = 0
            chunk.string.withExistingUTF8 { buf in
                while count < measuredUnits {
                    precondition(offset <= buf.count)
                    offset = buf[offset...].firstIndex(of: nl)! + 1
                    count += 1
                }
            }

            return offset
        }

        func convertFromBaseUnits(_ baseUnits: Int, in chunk: Chunk) -> Int {
            return chunk.string.withExistingUTF8 { buf in
                precondition(baseUnits <= buf.count)
                return countNewlines(in: buf[..<baseUnits])
            }
        }

        func isBoundary(_ offset: Int, in chunk: Chunk) -> Bool {
            precondition(offset > 0 && offset <= chunk.count)

            return chunk.string.withExistingUTF8 { buf in
                buf[offset - 1] == UInt8(ascii: "\n")
            }
        }

        func prev(_ offset: Int, in chunk: Chunk) -> Int? {
            precondition(offset > 0 && offset <= chunk.count)

            let nl = UInt8(ascii: "\n")
            return chunk.string.withExistingUTF8 { buf in
                buf[..<(offset - 1)].lastIndex(of: nl).map { $0 + 1 }
            }
        }

        func next(_ offset: Int, in chunk: Chunk) -> Int? {
            precondition(offset >= 0 && offset <= chunk.count)

            let nl = UInt8(ascii: "\n")
            return chunk.string.withExistingUTF8 { buf in
                buf[offset...].firstIndex(of: nl).map { $0 + 1 }
            }
        }

        var canFragment: Bool {
            true
        }

        var type: BTreeMetricType {
            .trailing
        }
    }
}

extension BTreeMetric<RopeSummary> where Self == Rope.NewlinesMetric {
    static var newlines: Rope.NewlinesMetric { Rope.NewlinesMetric() }
}

// MARK: - Builder

// An optimized builder that handles grapheme breaking and skips unnecessary
// calls to fixup.
struct RopeBuilder {
    var b: BTreeBuilder<Rope>
    var breaker: Rope.GraphemeBreaker

    init() {
        self.b = BTreeBuilder<Rope>()
        self.breaker = Rope.GraphemeBreaker()
    }

    mutating func push<S>(characters: S) where S: Sequence<Character>{
        if var r = characters as? Rope {
            push(&r)
            return
        } else if var r = characters as? Subrope {
            push(&r.base, slicedBy: r.bounds)
            return
        }

        var s = String(characters)[...]
        s.makeContiguousUTF8()
        var br = breaker

        func nextChunk() -> Chunk? {
            if s.isEmpty {
                return nil
            }

            let end: String.Index
            if s.utf8.count <= Chunk.maxSize {
                end = s.endIndex
            } else {
                end = boundaryForBulkInsert(s)
            }

            let chunk = Chunk(s[..<end], breaker: &br)
            s = s[end...]
            return chunk
        }

        var chunk = nextChunk()
        let iter = AnyIterator<Chunk> {
            guard var c = chunk else {
                return nil
            }
            let next = nextChunk()
            defer { chunk = next }
            c.lastCharSplits = (next?.prefixCount ?? 0) > 0
            return c
        }

        b.push(leaves: iter)
        breaker = br
    }

    mutating func push(_ rope: inout Rope) {
        breaker = Rope.GraphemeBreaker(for: rope, upTo: rope.endIndex)
        b.push(&rope.root)
    }

    mutating func push(_ rope: inout Rope, slicedBy range: Range<Rope.Index>) {
        breaker = Rope.GraphemeBreaker(for: rope, upTo: range.upperBound)
        b.push(&rope.root, slicedBy: Range(range, in: rope))
    }

    consuming func build() -> Rope {
        return b.build()
    }
}

fileprivate func boundaryForBulkInsert(_ s: Substring) -> String.Index {
    boundary(for: s, startingAt: Chunk.minSize)
}

fileprivate func boundaryForMerge(_ s: Substring) -> String.Index {
    // for the smallest chunk that needs splitting (n = maxSize + 1 = 1024):
    // minSplit = max(511, 1024 - 1023) = max(511, 1) = 511
    // maxSplit = min(1023, 1024 - 511) = min(1023, 513) = 513
    boundary(for: s, startingAt: max(Chunk.minSize, s.utf8.count - Chunk.maxSize))
}

fileprivate func boundary(for s: Substring, startingAt minSplit: Int) -> String.Index {
    let maxSplit = min(Chunk.maxSize, s.utf8.count - Chunk.minSize)

    precondition(minSplit >= 1 && maxSplit <= s.utf8.count)

    let nl = UInt8(ascii: "\n")
    let lineBoundary = s.withExistingUTF8 { buf in
        buf[(minSplit-1)..<maxSplit].lastIndex(of: nl)
    }

    let offset = lineBoundary ?? maxSplit
    let i = s.utf8Index(at: offset)
    return s.unicodeScalars._index(roundingDown: i)
}


// MARK: - Index

extension Rope {
    struct Index {
        var i: BTreeNode<RopeSummary>.Index
        var lineViewEnd: Bool

        init(_ i: BTreeNode<RopeSummary>.Index) {
            self.i = i
            self.lineViewEnd = false
        }

        init(_ i: BTreeNode<RopeSummary>.Index, lineViewEnd: Bool) {
            self.i = i
            self.lineViewEnd = lineViewEnd
        }

        init(_ i: Index, lineViewEnd: Bool) {
            self.i = i.i
            self.lineViewEnd = lineViewEnd
        }

        var position: Int {
            i.position
        }

        func validate(for rope: Rope) {
            i.validate(for: rope.root)
        }

        func validate(_ other: Index) {
            i.validate(other.i)
        }
    }
}

extension Rope.Index {
    func readUTF8() -> UTF8.CodeUnit? {
        guard let (chunk, offset) = i.read() else {
            return nil
        }

        if offset == chunk.count {
            // We're at the end of the rope
            return nil
        }

        return chunk.string.utf8[chunk.string.utf8Index(at: offset)]
    }

    func readScalar() -> Unicode.Scalar? {
        guard let (chunk, offset) = i.read() else {
            return nil
        }

        if offset == chunk.count {
            // We're at the end of the rope
            return nil
        }

        let i = chunk.string.utf8Index(at: offset)
        assert(chunk.isValidUnicodeScalarIndex(i))

        return chunk.string.unicodeScalars[i]
    }

    func readChar() -> Character? {
        guard var (chunk, offset) = i.read() else {
            return nil
        }

        if offset == chunk.count {
            // We're at the end of the rope
            return nil
        }

        assert(offset >= chunk.prefixCount)
        let ci = chunk.string.utf8Index(at: offset)

        assert(chunk.isValidCharacterIndex(ci))

        if ci < chunk.lastBreak {
            // the common case, the full character is in this chunk
            return chunk.string[ci]
        }

        var end = self
        if end.i.next(using: .characters) == nil {
            end = Rope(BTreeNode(storage: i.rootStorage!)).endIndex
        }

        var s = ""
        s.reserveCapacity(end.position - position)

        var i = self
        while true {
            let count = min(chunk.count - offset, end.position - i.position)

            let endOffset = offset + count
            assert(endOffset <= chunk.count)

            let cstart = chunk.string.utf8Index(at: offset)
            let cend = chunk.string.utf8Index(at: endOffset)

            s += chunk.string[cstart..<cend]

            if i.position + count == end.position {
                break
            }

            (chunk, offset) = i.i.nextLeaf()!
        }

        assert(s.count == 1)
        return s[s.startIndex]
    }

    func readLine() -> Substring? {
        guard var (chunk, offset) = i.read() else {
            return nil
        }

        // An optimization: if the entire line is within
        // the chunk, return a Substring.
        var end = self
        if let endOffset = end.i.next(withinLeafUsing: .newlines) {
            let i = chunk.string.utf8Index(at: offset)
            let j = chunk.string.utf8Index(at: endOffset - self.i.offsetOfLeaf)

            return chunk.string[i..<j]
        }

        end = self
        if end.i.next(using: .newlines) == nil {
            end = Rope(BTreeNode(storage: i.rootStorage!)).endIndex
        }

        var s = ""
        s.reserveCapacity(end.position - position)

        var i = self
        while true {
            let count = min(chunk.count - offset, end.position - i.position)

            let endOffset = offset + count
            assert(endOffset <= chunk.count)

            let cstart = chunk.string.utf8Index(at: offset)
            let cend = chunk.string.utf8Index(at: endOffset)

            s += chunk.string[cstart..<cend]

            if i.position + count == end.position {
                break
            }

            (chunk, offset) = i.i.nextLeaf()!
        }

        return s[...]
    }
}

extension Rope.Index: CustomDebugStringConvertible {
    var debugDescription: String {
        "\(position)[utf8]\(lineViewEnd ? "+lend" : "")"
    }
}


// MARK: - Collection conformances

// TODO: audit default methods from Collection, BidirectionalCollection and RangeReplaceableCollection for default implementations that perform poorly.
extension Rope: BidirectionalCollection {
    var count: Int {
        root.measure(using: .characters)
    }

    var startIndex: Index {
        Index(root.startIndex)
    }

    var endIndex: Index {
        Index(root.endIndex)
    }

    // N.b. This has a different behavior than String when subscripting on a
    // non-character boundary. String will round down to the closest UnicodeScalar
    // and then do some interesting things depending on what the index is
    // pointing to:
    //
    // All example indices are unicode scalar indices.
    //
    // s = "e\u{0301}"          - "e" + combining accute accent
    //   s[0] = "e\u{0301}"
    //   s[1] = "\u{0301}"
    //
    // s = "👨‍👩‍👧‍👦"
    //   = "👨\u{200D}👩\u{200D}👧\u{200D}👦"
    //   = "\u{0001F468}\u{200D}\u{0001F469}\u{200D}\u{0001F467}\u{200D}\u{0001F466}"
    //
    //   s[0] = "👨‍👩‍👧‍👦"
    //   s[1] = "\u{200D}"
    //   s[2] = "👩\u{200D}👧\u{200D}👦"
    //   s[3] = "\u{200D}"
    //   s[4] = "👧\u{200D}👦"
    //   s[5] = "\u{200D}"
    //   s[6] = "👦"
    //
    // This is pretty gnarley behavior that is doing special things with grapheme breaking,
    // so it's not worth reproducing.
    subscript(position: Index) -> Character {
        index(roundingDown: position).readChar()!
    }

    subscript(bounds: Range<Index>) -> Subrope {
        let start = index(roundingDown: bounds.lowerBound)
        let end = index(roundingDown: bounds.upperBound)
        return Subrope(base: self, bounds: start..<end)
    }

    func index(before i: Index) -> Index {
        Index(root.index(before: i.i, using: .characters))
    }

    func index(after i: Index) -> Index {
        Index(root.index(after: i.i, using: .characters))
    }

    func index(_ i: Index, offsetBy distance: Int) -> Index {
        Index(root.index(i.i, offsetBy: distance, using: .characters))
    }

    func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
        guard let j = root.index(i.i, offsetBy: distance, limitedBy: limit.i, using: .characters) else {
            return nil
        }
        return Index(j)
    }

    func distance(from start: Rope.Index, to end: Rope.Index) -> Int {
        root.distance(from: start.i, to: end.i, using: .characters)
    }
}

extension Rope.Index: Comparable {
    static func < (lhs: Rope.Index, rhs: Rope.Index) -> Bool {
        lhs.i < rhs.i || (!lhs.lineViewEnd && rhs.lineViewEnd)
    }
}

extension Rope: RangeReplaceableCollection {
    mutating func replaceSubrange<C>(_ subrange: Range<Index>, with newElements: C) where C: Collection, C.Element == Element {
        let rangeStart = index(roundingDown: subrange.lowerBound)
        let rangeEnd = index(roundingDown: subrange.upperBound)

        // We have to ensure that root isn't mutated directly because that would
        // invalidate indices and counts when we push the suffix (rangeEnd..<endIndex)
        // onto the builder.
        //
        // A nice optimization would be to make BTreeBuilder more like the RopeBuilder
        // in swift-collections, which has two stacks: a prefix stack descending in
        // height, and a suffix stack ascending in height. Then you have a "split"
        // operation that pushes the prefix and suffix onto the builder simultaneously
        // and then push() pushes in between prefix and suffix.
        //
        // Pushing both the prefix and suffix onto the builder in one step should
        // make the copying here unnecessary.
        var dup = self

        var b = RopeBuilder()
        b.push(&dup, slicedBy: startIndex..<rangeStart)
        b.push(characters: newElements)
        b.push(&dup, slicedBy: rangeEnd..<endIndex)

        self = b.build()
    }

    // The deafult implementation calls append(_:) in a loop. This should be faster.
    mutating func append<S>(contentsOf newElements: S) where S: Sequence, S.Element == Element {
        var b = RopeBuilder()
        b.push(&self)
        b.push(characters: newElements)
        self = b.build()
    }
}

// MARK: - Conveniences

// A few niceties that make Rope more like String.
extension Rope {
    static func + (_ left: Rope, _ right: Rope) -> Rope {
        var l = left
        var r = right

        var b = RopeBuilder()
        b.push(&l)
        b.push(&r)
        return b.build()
    }

    mutating func append(_ string: String) {
        append(contentsOf: string)
    }

    mutating func append(_ rope: Rope) {
        append(contentsOf: rope)
    }

    func index(roundingDown i: Index) -> Index {
        Index(root.index(roundingDown: i.i, using: .characters))
    }
}

// Some convenience methods that make string indexing not
// a total pain to work with.
extension Rope {
    func index(at offset: Int) -> Index {
        index(startIndex, offsetBy: offset)
    }

    func index(fromOldIndex oldIndex: Index) -> Index {
        Index(root.index(at: oldIndex.position, using: .utf8))
    }

    subscript(offset: Int) -> Character {
        self[index(at: offset)]
    }

    subscript(bounds: Range<Int>) -> Subrope {
        let start = utf8.index(at: bounds.lowerBound)
        let end = utf8.index(at: bounds.upperBound)
        return self[start..<end]
    }
}

// MARK: - Grapheme breaking

extension Rope {
    struct GraphemeBreaker: Equatable {
        #if swift(<5.9)
        static func == (lhs: GraphemeBreaker, rhs: GraphemeBreaker) -> Bool {
            false
        }
        #endif

        var recognizer: Unicode._CharacterRecognizer

        init(_ recognizer: Unicode._CharacterRecognizer = Unicode._CharacterRecognizer(), consuming s: Substring? = nil) {
            self.recognizer = recognizer

            if let s {
                consume(s)
            }
        }

        // assumes upperBound is valid in rope
        init(for rope: Rope, upTo upperBound: Rope.Index, withKnownNextScalar next: Unicode.Scalar? = nil) {
            assert(rope.unicodeScalars.isBoundary(upperBound))

            if rope.isEmpty || upperBound.position == 0 {
                self.init()
                return
            }

            if let next {
                let i = rope.unicodeScalars.index(before: upperBound)
                let prev = rope.unicodeScalars[i]

                if Unicode._CharacterRecognizer.quickBreak(between: prev, and: next) ?? false {
                    self.init()
                    return
                }
            }

            let (chunk, offset) = upperBound.i.read()!
            let i = chunk.string.utf8Index(at: offset)

            if i <= chunk.firstBreak {
                self.init(chunk.breaker.recognizer, consuming: chunk.string[..<i])
                return
            }

            let prev = chunk.characters.index(before: i)

            self.init(consuming: chunk.string[prev..<i])
        }

        mutating func hasBreak(before next: Unicode.Scalar) -> Bool {
            recognizer.hasBreak(before: next)
        }

        mutating func firstBreak(in s: Substring) -> Range<String.Index>? {
            let r = s.withExistingUTF8 { buf in
                recognizer._firstBreak(inUncheckedUnsafeUTF8Buffer: buf)
            }

            if let r {
                return s.utf8Index(at: r.lowerBound)..<s.utf8Index(at: r.upperBound)
            } else {
                return nil
            }
        }

        mutating func consume(_ s: Substring) {
            for u in s.unicodeScalars {
                _ = recognizer.hasBreak(before: u)
            }
        }
    }
}


// MARK: - Views

// TODO: RopeView is really an implementation detail for code deduplication.
// Consider making it fileprivate and making each view conform to
// BidirectionalCollection directly, forwarding to a private struct implementing
// RopeView. It's possible we could use a macro to generate the forwarding methods.
protocol RopeView: BidirectionalCollection where Index == Rope.Index {
    associatedtype Element
    associatedtype Metric: BTreeMetric<RopeSummary> where Metric.Unit == Int

    var base: Rope { get }
    var bounds: Range<Rope.Index> { get }
    var metric: Metric { get }

    init(base: Rope, bounds: Range<Index>)
    func readElement(at i: Index) -> Element
}

extension RopeView {
    var root: BTreeNode<RopeSummary> {
        base.root
    }
}

// BidirectionalCollection
extension RopeView {
    var count: Int {
        root.distance(from: startIndex.i, to: endIndex.i, using: metric)
    }

    var startIndex: Index {
        bounds.lowerBound
    }

    var endIndex: Index {
        bounds.upperBound
    }

    subscript(position: Index) -> Element {
        precondition(position >= startIndex && position < endIndex, "Index out of bounds")
        let i = Index(root.index(roundingDown: position.i, using: metric))
        precondition(i >= startIndex, "Index out of bounds")
        return readElement(at: i)
    }

    subscript(r: Range<Index>) -> Self {
        precondition(r.lowerBound >= startIndex && r.upperBound <= endIndex, "Index out of bounds")
        let start = Index(root.index(roundingDown: r.lowerBound.i, using: metric))
        let end = Index(root.index(roundingDown: r.upperBound.i, using: metric))
        precondition(start >= startIndex && end <= endIndex, "Index out of bounds")
        return Self(base: base, bounds: start..<end)
    }

    func index(before i: Index) -> Index {
        precondition(i > startIndex, "Index out of bounds")
        return Index(root.index(before: i.i, using: metric))
    }

    func index(after i: Index) -> Index {
        precondition(i < endIndex, "Index out of bounds")
        return Index(root.index(after: i.i, using: metric))
    }

    func index(_ i: Index, offsetBy distance: Int) -> Index {
        precondition(i >= startIndex && i <= endIndex, "Index out of bounds")
        let j = Index(root.index(i.i, offsetBy: distance, using: metric))
        precondition(j >= startIndex && j <= endIndex, "Index out of bounds")
        return j
    }

    func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
        precondition(i >= startIndex && i <= endIndex, "Index out of bounds")
        guard let b = root.index(i.i, offsetBy: distance, limitedBy: limit.i, using: metric) else {
            return nil
        }
        let j = Index(b)
        precondition(j >= startIndex && j <= endIndex, "Index out of bounds")
        return j
    }

    func distance(from start: Index, to end: Index) -> Int {
        precondition(start >= startIndex && start <= endIndex, "Index out of bounds")
        return root.distance(from: start.i, to: end.i, using: metric)
    }
}

extension RopeView {
    func index(at offset: Int) -> Index {
        precondition(offset >= 0 && offset <= count)
        return index(startIndex, offsetBy: offset)
    }

    func index(roundingDown i: Index) -> Index {
        precondition(i >= startIndex && i <= endIndex, "Index out of bounds")
        let j = Index(root.index(roundingDown: i.i, using: metric))
        precondition(j >= startIndex, "Index out of bounds")
        return j
    }

    subscript(offset: Int) -> Element {
        self[index(at: offset)]
    }

    func isBoundary(_ i: Index) -> Bool {
        i.i.assertValid(for: root)

        // checking startIndex isn't technically necessary because
        // none of our RopeViews use leading metrics, but it's nicer
        // to never have to worry about that.
        if i == endIndex || i == startIndex {
            return true
        }
        return i.i.isBoundary(in: metric)
    }
}

extension Rope {
    var utf8: UTF8View {
        UTF8View(base: self, bounds: startIndex..<endIndex)
    }

    struct UTF8View: RopeView {
        // I don't think I should need this typealias – Element should
        // be inferred from readElement(at:), but as of Swift 5.9, UTF8View
        // doesn't conform to RopeView without it.
        //
        // Even stranger, the other views works fine without the typealias.
        typealias Element = UTF8.CodeUnit

        var base: Rope
        var bounds: Range<Index>

        var metric: UTF8Metric {
            .utf8
        }

        func readElement(at i: Index) -> UTF8.CodeUnit {
            i.readUTF8()!
        }
    }
}

// We don't have a full UTF-16 view because dealing with trailing surrogates
// was a pain. If we need it, we'll add it.
//
// TODO: if we add a proper UTF-16 view, make sure to change the block passed
// to CTLineEnumerateCaretOffsets in layoutInsertionPoints to remove the
// prev == i check and replace it with i.isBoundary(in: .characters), as
// buffer.utf16.index(_:offsetBy:) will no longer round down. If we don't
// do this, our ability to click on a line fragment after an emoji will fail.
extension Rope {
    var utf16: UTF16View {
        UTF16View(base: self, bounds: startIndex..<endIndex)
    }

    struct UTF16View {
        var base: Rope
        var bounds: Range<Index>
    }
}

extension Rope.UTF16View {
    var root: BTreeNode<RopeSummary> {
        base.root
    }
}

extension Rope.UTF16View {
    typealias Index = Rope.Index

    var count: Int {
        root.distance(from: startIndex.i, to: endIndex.i, using: .utf16)
    }

   var startIndex: Index {
       bounds.lowerBound
   }

   var endIndex: Index {
       bounds.upperBound
   }

    func index(_ i: Index, offsetBy distance: Int) -> Index {
        precondition(i >= startIndex && i <= endIndex, "Index out of bounds")
        let j = Index(root.index(i.i, offsetBy: distance, using: .utf16))
        precondition(j >= startIndex && j <= endIndex, "Index out of bounds")
        return j
    }

    func distance(from start: Index, to end: Index) -> Int {
        precondition(start >= startIndex && start <= endIndex, "Index out of bounds")
        return root.distance(from: start.i, to: end.i, using: .utf16)
    }
}

extension Rope {
    var unicodeScalars: UnicodeScalarView {
        UnicodeScalarView(base: self, bounds: startIndex..<endIndex)
    }

    struct UnicodeScalarView: RopeView {
        let base: Rope
        let bounds: Range<Index>

        var metric: UnicodeScalarMetric {
            .unicodeScalars
        }

        func readElement(at i: Index) -> UnicodeScalar {
            i.readScalar()!
        }
    }
}

extension Rope {
    var lines: LineView {
        LineView(base: self, bounds: startIndex..<endIndex)
    }

    struct LineView {
        var base: Rope
        var bounds: Range<Index>

        var root: BTreeNode<RopeSummary> {
            base.root
        }
    }
}

extension Rope.LineView: BidirectionalCollection {
    typealias Index = Rope.Index
    var count: Int {
        root.distance(from: startIndex.i, to: endIndex.i, using: .newlines) + 1
    }

    var startIndex: Index {
        bounds.lowerBound
    }

    var endIndex: Index {
        Index(bounds.upperBound, lineViewEnd: true)
    }

    subscript(position: Index) -> Subrope {
        precondition(position >= startIndex && position < endIndex, "Index out of bounds")
        let start = index(roundingDown: position)

        var end = index(after: start)
        if end == endIndex {
            end = base.endIndex
        }

        return Subrope(base: base, bounds: start..<end)
    }

    subscript(r: Range<Index>) -> Self {
        precondition(r.lowerBound >= startIndex && r.upperBound <= endIndex, "Index out of bounds")
        let start = base.index(roundingDown: r.lowerBound)
        let end = base.index(roundingDown: r.upperBound)
        return Self(base: base, bounds: start..<end)
    }

    func index(before i: Index) -> Index {
        if i == endIndex {
            return index(roundingDown: bounds.upperBound)
        }

        let j = index(roundingDown: i)

        precondition(j > startIndex, "Index out of bounds")
        return Index(root.index(before: j.i, using: .newlines))
    }

    func index(after i: Index) -> Index {
        precondition(i < endIndex, "Index out of bounds")

        var j = i.i
        if j.next(using: .newlines) == nil {
            return endIndex
        }
        return Index(j)
    }

    func index(_ i: Index, offsetBy distance: Int) -> Index {
        // Even though we're not using root's index methods, we don't need to
        // validate because the index comparison operators will do it for us.
        precondition(i >= startIndex && i <= endIndex, "Index out of bounds")

        if distance > 0 && i == endIndex {
            preconditionFailure("Index out of bounds")
        }

        if distance == 0 && i == endIndex {
            return i
        }

        // when we start counting newlines below, there will be no difference
        // between base.endIndex and endIndex. If we're at endIndex and going
        // negative, just treat it as if we're at base.endIndex and adjust
        // distance accordingly.
        var distance = distance
        if distance < 0 && i == endIndex {
            distance += 1
        }

        var j = i.i
        let m = root.count(.newlines, upThrough: j.position)
        precondition(m+distance >= 0 && m+distance <= count, "Index out of bounds")
        if m + distance == count {
            return endIndex
        }
        let pos = root.countBaseUnits(upThrough: m + distance, measuredIn: .newlines)
        j.set(pos)

        return Index(j)
    }

    func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
        // ditto
        precondition(i >= startIndex && i <= endIndex, "Index out of bounds")
        precondition(limit >= startIndex && limit <= endIndex, "Limit out of bounds")

        let l = self.distance(from: i, to: limit)
        if distance > 0 ? l >= 0 && l < distance : l <= 0 && l > distance {
            return nil
        }
        return index(i, offsetBy: distance)
    }

    func distance(from start: Index, to end: Index) -> Int {
        precondition(start >= startIndex && start <= endIndex, "Index out of bounds")
        precondition(end >= startIndex && end <= endIndex, "Index out of bounds")

        var d = root.distance(from: start.i, to: end.i, using: .newlines)
        if start < end && end == endIndex {
            d += 1
        } else if start > end && start == endIndex {
            d -= 1
        }

        return d
    }
}

extension Rope.LineView {
    func index(at offset: Int) -> Index {
        precondition(offset >= 0 && offset <= count)
        return index(startIndex, offsetBy: offset)
    }

    subscript(offset: Int) -> Subrope {
        self[index(at: offset)]
    }

    func index(roundingDown i: Index) -> Index {
        precondition(i >= startIndex && i <= endIndex, "Index out of bounds")
        if isBoundary(i) {
            return i
        }
        return Index(root.index(before: i.i, using: .newlines))
    }

    func index(roundingUp i: Index) -> Index {
        precondition(i >= startIndex && i <= endIndex, "Index out of bounds")
        if isBoundary(i) {
            return i
        }
        return index(after: i)
    }

    func isBoundary(_ i: Index) -> Bool {
        i.i.assertValid(for: root)
        if i == endIndex {
            // lines.endIndex (i.e. index(startIndex, offsetBy: lines.count)) is always a boundary.
            return true
        }
        return i.i.isBoundary(in: .newlines)
    }
}

// MARK: - Subropes

struct Subrope: RopeView {
    typealias Element = Character
    
    init(base: Rope, bounds: Range<Rope.Index>) {
        self.base = base
        self.bounds = bounds
    }

    init(root: BTreeNode<RopeSummary>, bounds: Range<Rope.Index>) {
        self.init(base: Rope(root), bounds: bounds)
    }
    
    var base: Rope
    var bounds: Range<Rope.Index>

    var root: BTreeNode<RopeSummary> {
        base.root
    }

    var metric: Rope.CharacterMetric {
        .characters
    }

    func readElement(at i: Rope.Index) -> Character {
        i.readChar()!
    }
}


extension Subrope {
    typealias UTF8View = Rope.UTF8View
    typealias UTF16View = Rope.UTF16View
    typealias UnicodeScalarView = Rope.UnicodeScalarView
    typealias LineView = Rope.LineView

    var utf8: UTF8View {
        UTF8View(base: base, bounds: bounds)
    }

    var utf16: UTF16View {
        UTF16View(base: base, bounds: bounds)
    }

    var unicodeScalars: UnicodeScalarView {
        UnicodeScalarView(base: base, bounds: bounds)
    }

    var lines: LineView {
        LineView(base: base, bounds: bounds)
    }
}

extension Subrope: RangeReplaceableCollection {
    init() {
        let r = Rope()
        base = r
        bounds = r.startIndex..<r.endIndex
    }

    mutating func replaceSubrange<C>(_ subrange: Range<Index>, with newElements: C) where C: Collection, C.Element == Element {
        precondition(subrange.lowerBound >= startIndex && subrange.upperBound <= endIndex, "Index out of bounds")
        base.replaceSubrange(subrange, with: newElements)
        bounds = base.index(fromOldIndex: startIndex)..<base.index(fromOldIndex: endIndex)
    }

    // The deafult implementation calls append(_:) in a loop. This should be faster.
    mutating func append<S>(contentsOf newElements: S) where S: Sequence, S.Element == Element {
        let new = Rope(newElements)
        base.replaceSubrange(endIndex..<endIndex, with: new)
        let start = base.index(fromOldIndex: startIndex)
        let end = base.index(base.index(fromOldIndex: endIndex), offsetBy: new.count)
        bounds = start..<end
    }
}


// MARK: - Standard library integration

// TODO: normalized comparisons
extension Rope: Equatable {
    static func == (lhs: Rope, rhs: Rope) -> Bool {
        if lhs.root == rhs.root {
            return true
        }

        if lhs.utf8.count != rhs.utf8.count {
            return false
        }

        // TODO: this should be O(1). It currently iterates.
        if lhs.root.leaves.count != rhs.root.leaves.count {
            return false
        }

        for (l, r) in zip(lhs.root.leaves, rhs.root.leaves) {
            if l.string != r.string {
                return false
            }
        }

        return true
    }
}

// TODO: normalized comparisons
extension Subrope: Equatable {
    static func == (lhs: Subrope, rhs: Subrope) -> Bool {
        if lhs.base.root == rhs.base.root && Range(uncheckedRange: lhs.bounds) == Range(uncheckedRange: rhs.bounds) {
            return true
        }
        return Rope(lhs) == Rope(rhs)
    }
}

extension Rope: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.init(value)
    }
}

extension Subrope: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.init(value)
    }
}

extension String {
    init(_ rope: Rope) {
        self.init()
        self.reserveCapacity(rope.utf8.count)
        for chunk in rope.root.leaves {
            append(chunk.string)
        }
    }

    init(_ subrope: Subrope) {
        let r = Rope(subrope)
        self.init(r)
    }
}

extension NSString {
    convenience init(_ rope: Rope) {
        self.init(string: String(rope))
    }
}

extension Data {
    init(_ rope: Rope) {
        self.init(capacity: rope.utf8.count)
        for chunk in rope.root.leaves {
            chunk.string.withExistingUTF8 { p in
                append(p.baseAddress!, count: p.count)
            }
        }
    }
}

extension Range where Bound == Rope.Index {
    init?(_ range: NSRange, in rope: Rope) {
        if range == .notFound {
            return nil
        }

        guard range.lowerBound >= 0 && range.lowerBound <= rope.utf16.count else {
            return nil
        }

        guard range.upperBound >= 0 && range.upperBound <= rope.utf16.count else {
            return nil
        }

        var i = rope.root.countBaseUnits(upThrough: range.lowerBound, measuredIn: .utf16)
        var j = rope.root.countBaseUnits(upThrough: range.upperBound, measuredIn: .utf16)

        // NSTextInputClient seems to sometimes receive ranges that start
        // or end on a trailing surrogate. Round them to the nearest
        // unicode scalar.
        if rope.root.count(.utf16, upThrough: i) != range.lowerBound {
            assert(rope.root.count(.utf16, upThrough: i) == range.lowerBound - 1)
            print("!!! got NSRange starting on a trailing surrogate: \(range). I think this is expected, but try to reproduce and figure out if it's ok")
            i -= 1
        }

        if rope.root.count(.utf16, upThrough: j) != range.upperBound {
            assert(rope.root.count(.utf16, upThrough: j) == range.upperBound - 1)
            j += 1
        }

        self.init(uncheckedBounds: (rope.utf8.index(at: i), rope.utf8.index(at: j)))
    }

    init(_ range: Range<Int>, in rope: Rope) {
        precondition(range.lowerBound >= 0 || range.lowerBound < rope.utf8.count + 1, "lowerBound is out of bounds")
        precondition(range.upperBound >= 0 || range.upperBound < rope.utf8.count + 1, "upperBound is out of bounds")

        let i = range.lowerBound
        let j = range.upperBound

        self.init(uncheckedBounds: (rope.utf8.index(at: i), rope.utf8.index(at: j)))
    }
}

extension Range where Bound == Int {
    // Don't use for user provided ranges.
    init(uncheckedRange range: Range<Rope.Index>) {
        self.init(uncheckedBounds: (range.lowerBound.position, range.upperBound.position))
    }

    init(_ range: Range<Rope.Index>, in rope: Rope) {
        let start = rope.utf8.distance(from: rope.utf8.startIndex, to: range.lowerBound)
        let end = rope.utf8.distance(from: rope.utf8.startIndex, to: range.upperBound)

        self.init(uncheckedBounds: (start, end))
    }
}

extension NSRange {
    init<R>(_ region: R, in rope: Rope) where R : RangeExpression, R.Bound == Rope.Index {
        let range = region.relative(to: rope)

        range.lowerBound.validate(for: rope)
        range.upperBound.validate(for: rope)

        assert(range.lowerBound.position >= 0 && range.lowerBound.position <= rope.root.count)
        assert(range.upperBound.position >= 0 && range.upperBound.position <= rope.root.count)

        // TODO: is there a reason the majority of this initializer isn't just distance(from:to:)?
        let i = rope.root.count(.utf16, upThrough: range.lowerBound.position)
        let j = rope.root.count(.utf16, upThrough: range.upperBound.position)

        self.init(location: i, length: j-i)
    }
}

// MARK: - Helpers

fileprivate func countNewlines(in buf: Slice<UnsafeBufferPointer<UInt8>>) -> Int {
    let nl = UInt8(ascii: "\n")
    var count = 0

    for b in buf {
        if b == nl {
            count += 1
        }
    }

    return count
}
