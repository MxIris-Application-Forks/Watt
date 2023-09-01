//
//  SpansTests.swift
//  WattTests
//
//  Created by David Albert on 8/23/23.
//

import XCTest

@testable import Watt
final class SpansTests: XCTestCase {
    // MARK: - Merging adjacent equatable spans
    func testAdjacentEquatableSpansGetMerged() {
        var b = SpansBuilder<Int>(totalCount: 6)
        b.add(1, covering: 0..<3)
        b.add(1, covering: 3..<6)
        var s = b.build()

        XCTAssertEqual(6, s.upperBound)
        XCTAssertEqual(1, s.count)

        var iter = s.makeIterator()
        XCTAssertEqual(Span(range: 0..<6, data: 1), iter.next())
        XCTAssertNil(iter.next())

        b = SpansBuilder<Int>(totalCount: 6)
        b.add(1, covering: 0..<3)
        b.add(2, covering: 3..<6)
        s = b.build()

        XCTAssertEqual(6, s.upperBound)
        XCTAssertEqual(2, s.count)

        iter = s.makeIterator()
        XCTAssertEqual(Span(range: 0..<3, data: 1), iter.next())
        XCTAssertEqual(Span(range: 3..<6, data: 2), iter.next())
        XCTAssertNil(iter.next())
    }

    func testMergingEquatableSpansWithGapsDoesntMerge() {
        var b = SpansBuilder<Int>(totalCount: 6)
        b.add(1, covering: 0..<3)
        b.add(2, covering: 4..<6)
        let s = b.build()

        XCTAssertEqual(6, s.upperBound)
        XCTAssertEqual(2, s.count)

        var iter = s.makeIterator()
        XCTAssertEqual(Span(range: 0..<3, data: 1), iter.next())
        XCTAssertEqual(Span(range: 4..<6, data: 2), iter.next())
        XCTAssertNil(iter.next())
    }

    func testNonEquatableSpanDataDoesntMerge() {
        struct NonEquatable {}

        var b = SpansBuilder<NonEquatable>(totalCount: 6)
        b.add(NonEquatable(), covering: 0..<3)
        b.add(NonEquatable(), covering: 3..<6)
        let s = b.build()

        XCTAssertEqual(6, s.upperBound)
        XCTAssertEqual(2, s.count)

        var iter = s.makeIterator()
        XCTAssertEqual(0..<3, iter.next()!.range)
        XCTAssertEqual(3..<6, iter.next()!.range)
        XCTAssertNil(iter.next())
    }

    func testMergingEquatableSpansThatWouldNormallyTakeUpMultipleLeaves() {
        var b = SpansBuilder<Int>(totalCount: 256)
        for i in stride(from: 0, through: 255, by: 2) {
            b.add(1, covering: i..<i+2)
        }
        var s = b.build()

        XCTAssertEqual(256, s.upperBound)
        XCTAssertEqual(1, s.count)
        XCTAssertEqual(0, s.root.height)

        var iter = s.makeIterator()
        XCTAssertEqual(Span(range: 0..<256, data: 1), iter.next())
        XCTAssertNil(iter.next())

        b = SpansBuilder<Int>(totalCount: 256)
        for i in stride(from: 0, through: 255, by: 2) {
            b.add(i, covering: i..<i+2)
        }
        s = b.build()

        XCTAssertEqual(256, s.upperBound)
        XCTAssertEqual(128, s.count)
        XCTAssertEqual(1, s.root.height)
        XCTAssertEqual(2, s.root.children.count)

        iter = s.makeIterator()
        for i in stride(from: 0, through: 255, by: 2) {
            XCTAssertEqual(Span(range: i..<i+2, data: i), iter.next())
        }
    }

    func testSubscriptRange() {
        var b = SpansBuilder<Int>(totalCount: 6)
        b.add(1, covering: 0..<3)
        b.add(2, covering: 3..<6)
        let s = b.build()

        XCTAssertEqual(6, s.upperBound)
        XCTAssertEqual(2, s.count)

        var iter = s[0..<6].makeIterator()
        XCTAssertEqual(Span(range: 0..<3, data: 1), iter.next())
        XCTAssertEqual(Span(range: 3..<6, data: 2), iter.next())
        XCTAssertNil(iter.next())

        iter = s[0..<3].makeIterator()
        XCTAssertEqual(Span(range: 0..<3, data: 1), iter.next())
        XCTAssertNil(iter.next())

        iter = s[3..<6].makeIterator()
        XCTAssertEqual(Span(range: 0..<3, data: 2), iter.next())
        XCTAssertNil(iter.next())

        iter = s[0..<0].makeIterator()
        XCTAssertNil(iter.next())

        iter = s[0..<1].makeIterator()
        XCTAssertEqual(Span(range: 0..<1, data: 1), iter.next())
        XCTAssertNil(iter.next())

        iter = s[5..<6].makeIterator()
        XCTAssertEqual(Span(range: 0..<1, data: 2), iter.next())
        XCTAssertNil(iter.next())

        iter = s[6..<6].makeIterator()
        XCTAssertNil(iter.next())
    }

    func testSpanBuilderPushSlicedByEmptyBuilder() {
        var b1 = SpansBuilder<Int>(totalCount: 256)
        for i in stride(from: 0, through: 255, by: 2) {
            b1.add(i, covering: i..<i+2)
        }
        let s1 = b1.build()

        XCTAssertEqual(256, s1.upperBound)
        XCTAssertEqual(128, s1.count)

        var b2 = SpansBuilder<Int>(totalCount: 254)
        b2.push(s1, slicedBy: 1..<255)
        let s2 = b2.build()

        XCTAssertEqual(254, s2.upperBound)
        XCTAssertEqual(128, s2.count)

        var iter = s2.makeIterator()
        let first = iter.next()!
        XCTAssertEqual(0..<1, first.range)
        XCTAssertEqual(0, first.data)

        for i in stride(from: 1, through: 251, by: 2) {
            let span = iter.next()!
            XCTAssertEqual(i..<i+2, span.range)
            XCTAssertEqual(i+1, span.data)
        }

        let last = iter.next()!
        XCTAssertEqual(253..<254, last.range)
        XCTAssertEqual(254, last.data)

        XCTAssertNil(iter.next())
    }

    func testSpanBuilderPushSlicedByNonEmptyBuilder() {
        var b1 = SpansBuilder<Int>(totalCount: 256)
        for i in stride(from: 0, through: 255, by: 2) {
            b1.add(i, covering: i..<i+2)
        }
        let s1 = b1.build()

        XCTAssertEqual(256, s1.upperBound)
        XCTAssertEqual(128, s1.count)

        var b2 = SpansBuilder<Int>(totalCount: 5) // set totalCount low to make sure it gets bumped up correctly.
        b2.add(-1, covering: 0..<3)
        b2.push(s1, slicedBy: 1..<255)
        let s2 = b2.build()

        XCTAssertEqual(257, s2.upperBound)
        XCTAssertEqual(129, s2.count)

        var iter = s2.makeIterator()
        let first = iter.next()!
        XCTAssertEqual(0..<3, first.range)
        XCTAssertEqual(-1, first.data)

        let second = iter.next()!
        XCTAssertEqual(3..<4, second.range)
        XCTAssertEqual(0, second.data)

        for i in stride(from: 4, through: 254, by: 2) {
            let span = iter.next()!
            XCTAssertEqual(i..<i+2, span.range)
            XCTAssertEqual(i-2, span.data)
        }

        let last = iter.next()!
        XCTAssertEqual(256..<257, last.range)
        XCTAssertEqual(254, last.data)

        XCTAssertNil(iter.next())
    }

    func testSpansBuilderPushSlicedByCombineSpans() {
        var b1 = SpansBuilder<Int>(totalCount: 256)
        for i in stride(from: 0, through: 255, by: 2) {
            b1.add(i, covering: i..<i+2)
        }
        let s1 = b1.build()

        XCTAssertEqual(256, s1.upperBound)
        XCTAssertEqual(128, s1.count)

        var b2 = SpansBuilder<Int>(totalCount: 257)
        b2.add(0, covering: 0..<3)
        b2.push(s1, slicedBy: 1..<255)
        let s2 = b2.build()

        XCTAssertEqual(257, s2.upperBound)
        XCTAssertEqual(128, s2.count)

        var iter = s2.makeIterator()
        let first = iter.next()!
        XCTAssertEqual(0..<4, first.range)
        XCTAssertEqual(0, first.data)

        for i in stride(from: 4, through: 254, by: 2) {
            let span = iter.next()!
            XCTAssertEqual(i..<i+2, span.range)
            XCTAssertEqual(i-2, span.data)
        }

        let last = iter.next()!
        XCTAssertEqual(256..<257, last.range)
        XCTAssertEqual(254, last.data)

        XCTAssertNil(iter.next())
    }

    func testSpansBuilderPushSlicedWithFullLeaf() {
        XCTAssertEqual(64, SpansLeaf<Int>.maxSize)

        var b1 = SpansBuilder<Int>(totalCount: 128)
        for i in stride(from: 0, through: 127, by: 2) {
            b1.add(i, covering: i..<i+2)
        }
        let s1 = b1.build()

        XCTAssertEqual(128, s1.upperBound)
        XCTAssertEqual(64, s1.count)
        XCTAssertEqual(0, s1.root.height)
        XCTAssertEqual(64, s1.root.leaf.spans.count)

        var b2 = SpansBuilder<Int>(totalCount: 64)
        for i in stride(from: 0, through: 63, by: 2) {
            b2.add(i, covering: i..<i+2)
        }
        let s2 = b2.build()

        XCTAssertEqual(64, s2.upperBound)
        XCTAssertEqual(32, s2.count)
        XCTAssertEqual(0, s2.root.height)
        XCTAssertEqual(32, s2.root.leaf.spans.count)

        var b3 = SpansBuilder<Int>(totalCount: 0) // set totalCount low to make sure it gets bumped up correctly.
        b3.push(s1, slicedBy: 0..<128)

        XCTAssertEqual(128, b3.totalCount)
        XCTAssertEqual(0, b3.offsetOfLeaf)
        XCTAssertEqual(64, b3.leaf.spans.count)

        b3.push(s2, slicedBy: 1..<63)
        let s3 = b3.build()

        XCTAssertEqual(190, s3.upperBound)
        XCTAssertEqual(96, s3.count)

        var iter = s3.makeIterator()
        for i in stride(from: 0, through: 127, by: 2) {
            let span = iter.next()!
            XCTAssertEqual(i..<i+2, span.range)
            XCTAssertEqual(i, span.data)
        }

        let next = iter.next()!
        XCTAssertEqual(128..<129, next.range)
        XCTAssertEqual(0, next.data)

        for i in stride(from: 1, through: 60, by: 2) {
            let span = iter.next()!
            XCTAssertEqual(128+i..<128+i+2, span.range)
            XCTAssertEqual(i+1, span.data)
        }

        let last = iter.next()!
        XCTAssertEqual(189..<190, last.range)
        XCTAssertEqual(62, last.data)

        XCTAssertNil(iter.next())
    }

    func testSpansBuilderPushSlicedWithFullLeafCombineSpans() {
        XCTAssertEqual(64, SpansLeaf<Int>.maxSize)

        var b1 = SpansBuilder<Int>(totalCount: 128)
        for i in stride(from: 0, through: 127, by: 2) {
            b1.add(i, covering: i..<i+2)
        }
        let s1 = b1.build()

        XCTAssertEqual(128, s1.upperBound)
        XCTAssertEqual(64, s1.count)
        XCTAssertEqual(0, s1.root.height)
        XCTAssertEqual(64, s1.root.leaf.spans.count)

        var b2 = SpansBuilder<Int>(totalCount: 64)
        for i in stride(from: 0, through: 63, by: 2) {
            b2.add(126+i, covering: i..<i+2)
        }
        let s2 = b2.build()

        XCTAssertEqual(64, s2.upperBound)
        XCTAssertEqual(32, s2.count)
        XCTAssertEqual(0, s2.root.height)
        XCTAssertEqual(32, s2.root.leaf.spans.count)

        var b3 = SpansBuilder<Int>(totalCount: 0) // set totalCount low to make sure it gets bumped up correctly.
        b3.push(s1, slicedBy: 0..<128)

        XCTAssertEqual(128, b3.totalCount)
        XCTAssertEqual(0, b3.offsetOfLeaf)
        XCTAssertEqual(64, b3.leaf.spans.count)

        b3.push(s2, slicedBy: 1..<63)
        let s3 = b3.build()

        XCTAssertEqual(190, s3.upperBound)
        XCTAssertEqual(95, s3.count)

        var iter = s3.makeIterator()
        for i in stride(from: 0, through: 125, by: 2) {
            let span = iter.next()!
            XCTAssertEqual(i..<i+2, span.range)
            XCTAssertEqual(i, span.data)
        }

        let combined = iter.next()!
        XCTAssertEqual(126..<129, combined.range)
        XCTAssertEqual(126, combined.data)

        for i in stride(from: 1, through: 60, by: 2) {
            let span = iter.next()!
            XCTAssertEqual(128+i..<128+i+2, span.range)
            XCTAssertEqual(126+i+1, span.data)
        }

        let last = iter.next()!
        XCTAssertEqual(189..<190, last.range)
        XCTAssertEqual(188, last.data)

        XCTAssertNil(iter.next())
    }

    // MARK: - Regressions

    func testOverlappingMerge() {
        var b1 = SpansBuilder<Int>(totalCount: 3)
        b1.add(1, covering: 0..<3)

        var b2 = SpansBuilder<Int>(totalCount: 3)
        b2.add(2, covering: 2..<3)

        let s1 = b1.build()
        XCTAssertEqual(3, s1.upperBound)
        XCTAssertEqual(1, s1.count)

        var iter = s1.makeIterator()
        XCTAssertEqual(Span(range: 0..<3, data: 1), iter.next())
        XCTAssertNil(iter.next())

        let s2 = b2.build()
        XCTAssertEqual(3, s2.upperBound)
        XCTAssertEqual(1, s2.count)

        iter = s2.makeIterator()
        XCTAssertEqual(Span(range: 2..<3, data: 2), iter.next())
        XCTAssertNil(iter.next())

        let merged = s1.merging(s2) { left, right in
            if right == nil {
                return 3
            } else {
                return 4
            }
        }

        XCTAssertEqual(3, merged.upperBound)
        XCTAssertEqual(2, merged.count)

        iter = merged.makeIterator()
        XCTAssertEqual(Span(range: 0..<2, data: 3), iter.next())
        XCTAssertEqual(Span(range: 2..<3, data: 4), iter.next())
        XCTAssertNil(iter.next())
    }
}
