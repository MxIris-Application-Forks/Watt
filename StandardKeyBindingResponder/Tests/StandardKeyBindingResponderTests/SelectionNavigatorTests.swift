//
//  SelectionNavigatorTests.swift
//  Watt
//
//  Created by David Albert on 11/2/23.
//

import XCTest
@testable import StandardKeyBindingResponder

final class SelectionNavigatorTests: XCTestCase {
    // MARK: Creating selections

    func testCreateCaret() {
        let string = "Hello, world!"
        let s = SimpleSelection(caretAt: string.index(at: 1), affinity: .upstream)
        XCTAssert(s.isCaret)
        XCTAssertEqual(string.index(at: 1), s.lowerBound)
        XCTAssertEqual(.upstream, s.affinity)
    }

    func testCreateDownstreamSelection() {
        let string = "Hello, world!"
        let s = SimpleSelection(anchor: string.index(at: 1), head: string.index(at: 5))
        XCTAssert(s.isRange)
        XCTAssertEqual(string.index(at: 1), s.lowerBound)
        XCTAssertEqual(string.index(at: 5), s.upperBound)
        XCTAssertEqual(.downstream, s.affinity)
    }

    func createUpstreamSelection() {
        let string = "Hello, world!"
        let s = SimpleSelection(anchor: string.index(at: 5), head: string.index(at: 1))
        XCTAssert(s.isRange)
        XCTAssertEqual(string.index(at: 1), s.lowerBound)
        XCTAssertEqual(string.index(at: 5), s.upperBound)
        XCTAssertEqual(.upstream, s.affinity)
    }

    // MARK: Selection navigation

    func testMoveHorizontallyByCharacter() {
        let string = "ab\ncd\n"
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        var s = SimpleSelection(caretAt: string.index(at: 0), affinity: .downstream)
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 1), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 2), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 3), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 4), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 5), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 6), affinity: .upstream, dataSource: d)
        // going right at the end doesn't move the caret
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 6), affinity: .upstream, dataSource: d)

        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 5), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 4), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 3), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 2), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 1), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        // going left at the beginning doesn't move the caret
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
    }

    func testMoveRightToEndOfFrag() {
        let string = "a"
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        var s = SimpleSelection(caretAt: string.index(at: 0), affinity: .downstream)

        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 1), affinity: .upstream, dataSource: d)
    }

    func testMoveRightFromSelection() {
        let string = "foo bar baz"
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // select "oo b"
        var s = SimpleSelection(anchor: string.index(at: 1), head: string.index(at: 5))
        // the caret moves to the end of the selection
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 5), affinity: .downstream, dataSource: d)

        // it doesn't matter if the selection is reversed
        s = SimpleSelection(anchor: string.index(at: 5), head: string.index(at: 1))
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 5), affinity: .downstream, dataSource: d)

        // select "baz"
        s = SimpleSelection(anchor: string.index(at: 8), head: string.index(at: 11))
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 11), affinity: .upstream, dataSource: d)

        // reverse
        s = SimpleSelection(anchor: string.index(at: 11), head: string.index(at: 8))
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 11), affinity: .upstream, dataSource: d)

        // select all
        s = SimpleSelection(anchor: string.index(at: 0), head: string.index(at: 11))
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 11), affinity: .upstream, dataSource: d)

        // reverse
        s = SimpleSelection(anchor: string.index(at: 11), head: string.index(at: 0))
        s = moveAndAssert(s, direction: .right, caretAt: string.index(at: 11), affinity: .upstream, dataSource: d)
    }

    func testMoveLeftFromSelection() {
        let string = "foo bar baz"
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // select "oo b"
        var s = SimpleSelection(anchor: string.index(at: 1), head: string.index(at: 5))
        // the caret moves to the beginning of the selection
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 1), affinity: .downstream, dataSource: d)

        // reverse the selection
        s = SimpleSelection(anchor: string.index(at: 5), head: string.index(at: 1))
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 1), affinity: .downstream, dataSource: d)

        // select "foo"
        s = SimpleSelection(anchor: string.index(at: 0), head: string.index(at: 3))
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)

        // reverse
        s = SimpleSelection(anchor: string.index(at: 3), head: string.index(at: 0))
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)

        // select all
        s = SimpleSelection(anchor: string.index(at: 0), head: string.index(at: 11))
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)

        // reverse
        s = SimpleSelection(anchor: string.index(at: 11), head: string.index(at: 0))
        s = moveAndAssert(s, direction: .left, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
    }

    func testMoveVertically() {
        let string = """
        qux
        0123456789abcdefghijwrap
        xyz
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // caret at "1"
        var s = SimpleSelection(caretAt: string.index(at: 5), affinity: .downstream)
        s = moveAndAssert(s, direction: .up, caret: "u", affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .up, caret: "q", affinity: .downstream, dataSource: d)
        s = moveAndAssertNoop(s, direction: .up, dataSource: d)
        s = moveAndAssert(s, direction: .down, caret: "0", affinity: .downstream, dataSource: d)

        // caret at "1"
        s = SimpleSelection(caretAt: string.index(at: 5), affinity: .downstream)
        s = moveAndAssert(s, direction: .down, caret: "b", affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .down, caret: "r", affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .down, caret: "y", affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .down, caretAt: string.endIndex, affinity: .upstream, dataSource: d)
        s = moveAndAssertNoop(s, direction: .down, dataSource: d)
        s = moveAndAssert(s, direction: .up, caret: "p", affinity: .downstream, dataSource: d)


        // caret at "5"
        s = SimpleSelection(caretAt: string.index(at: 9), affinity: .downstream)
        // after "qux"
        s = moveAndAssert(s, direction: .up, caret: "\n", affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .down, caret: "5", affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .down, caret: "f", affinity: .downstream, dataSource: d)
        // after "wrap"
        s = moveAndAssert(s, direction: .down, caret: "\n", affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .down, caretAt: string.endIndex, affinity: .upstream, dataSource: d)
        s = moveAndAssertNoop(s, direction: .down, dataSource: d)
        s = moveAndAssert(s, direction: .up, caret: "\n", affinity: .downstream, dataSource: d)
    }

    func testMoveVerticallyWithEmptyLastLine() {
        let string = "abc\n"
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // after "\n"
        var s = SimpleSelection(caretAt: string.endIndex, affinity: .upstream)
        s = moveAndAssert(s, direction: .up, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)

        // after "c"
        s = SimpleSelection(caretAt: string.index(at: 3), affinity: .downstream)
        s = moveAndAssert(s, direction: .down, caretAt: string.endIndex, affinity: .upstream, dataSource: d)
        s = moveAndAssert(s, direction: .up, caret: "\n", affinity: .downstream, dataSource: d)
    }

    func testMoveHorizontallyByWord() {
        let string = "  hello, world; this is (a test) "
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        var s = SimpleSelection(caretAt: string.index(at: 0), affinity: .downstream)

        // between "o" and ","
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 7), affinity: .downstream, dataSource: d)
        // between "d" and ";"
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 14), affinity: .downstream, dataSource: d)
        // after "this"
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 20), affinity: .downstream, dataSource: d)
        // after "is"
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 23), affinity: .downstream, dataSource: d)
        // after "a"
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 26), affinity: .downstream, dataSource: d)
        // after "test"
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 31), affinity: .downstream, dataSource: d)
        // end of buffer
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)
        // doesn't move right
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)


        // beginning of "test"
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 27), affinity: .downstream, dataSource: d)
        // beginning of "a"
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 25), affinity: .downstream, dataSource: d)
        // beginning of "is"
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 21), affinity: .downstream, dataSource: d)
        // beginning of "this"
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 16), affinity: .downstream, dataSource: d)
        // beginning of "world"
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 9), affinity: .downstream, dataSource: d)
        // beginning of "hello"
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 2), affinity: .downstream, dataSource: d)
        // beginning of buffer
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        // doesn't move left
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
    }

    func testMoveRightWordFromSelection() {
        let string = "  hello, world; this is (a test) "
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // select "ello, w"
        var s = SimpleSelection(anchor: string.index(at: 3), head: string.index(at: 10))
        // the caret moves to the end of "world"
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 14), affinity: .downstream, dataSource: d)

        // reverse the selection
        s = SimpleSelection(anchor: string.index(at: 10), head: string.index(at: 3))
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 14), affinity: .downstream, dataSource: d)

        // select "(a test"
        s = SimpleSelection(anchor: string.index(at: 24), head: string.index(at: 31))
        // the caret moves to the end of the buffer
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)

        // reverse the selection
        s = SimpleSelection(anchor: string.index(at: 31), head: string.index(at: 24))
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)

        // select all
        s = SimpleSelection(anchor: string.index(at: 0), head: string.index(at: 33))
        // the caret moves to the end of the buffer
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)

        // reverse the selection
        s = SimpleSelection(anchor: string.index(at: 33), head: string.index(at: 0))
        s = moveAndAssert(s, direction: .rightWord, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)
    }

    func testMoveLeftWordFromSelection() {
        let string = "  hello, world; this is (a test) "
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // select "lo, w"
        var s = SimpleSelection(anchor: string.index(at: 5), head: string.index(at: 10))
        // the caret moves to the beginning of "hello"
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 2), affinity: .downstream, dataSource: d)

        // reverse the selection
        s = SimpleSelection(anchor: string.index(at: 10), head: string.index(at: 5))
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 2), affinity: .downstream, dataSource: d)

        // select "(a test"
        s = SimpleSelection(anchor: string.index(at: 24), head: string.index(at: 31))
        // the caret moves to the beginning of "is"
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 21), affinity: .downstream, dataSource: d)

        // reverse the selection
        s = SimpleSelection(anchor: string.index(at: 31), head: string.index(at: 24))
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 21), affinity: .downstream, dataSource: d)

        // select all
        s = SimpleSelection(anchor: string.index(at: 0), head: string.index(at: 33))
        // the caret moves to the beginning of the buffer
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)

        // reverse the selection
        s = SimpleSelection(anchor: string.index(at: 33), head: string.index(at: 0))
        s = moveAndAssert(s, direction: .leftWord, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
    }

    func testMoveLineEmpty() {
        let string = ""
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        var s = SimpleSelection(caretAt: string.startIndex, affinity: .upstream)
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.startIndex, affinity: .upstream, dataSource: d)
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.startIndex, affinity: .upstream, dataSource: d)
    }

    func testMoveLineSingleFragments() {
        let string = "foo bar\nbaz qux\n"
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // between "a" and "r"
        var s = SimpleSelection(caretAt: string.index(at: 6), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        // moving again is a no-op
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)

        // end of line
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 7), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 7), affinity: .downstream, dataSource: d)

        // from end to beginning
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)

        // between "o" and "o"
        s = SimpleSelection(caretAt: string.index(at: 2), affinity: .downstream)
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 7), affinity: .downstream, dataSource: d)



        // between "r" and "\n"
        s = SimpleSelection(caretAt: string.index(at: 7), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)

        // between "z" and " "
        s = SimpleSelection(caretAt: string.index(at: 11), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 8), affinity: .downstream, dataSource: d)
        // no-op
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 8), affinity: .downstream, dataSource: d)

        // end of line
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 15), affinity: .downstream, dataSource: d)
        // no-op
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 15), affinity: .downstream, dataSource: d)

        // end of buffer
        s = SimpleSelection(caretAt: string.index(at: 16), affinity: .upstream)
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 16), affinity: .upstream, dataSource: d)
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 16), affinity: .upstream, dataSource: d)
    }

    func testMoveLineMultipleFragments() {
        let string = """
        0123456789abcdefghijwrap
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // between "0" and "1"
        var s = SimpleSelection(caretAt: string.index(at: 1), affinity: .downstream)
        // end of line
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 10), affinity: .upstream, dataSource: d)

        // reset
        s = SimpleSelection(caretAt: string.index(at: 1), affinity: .downstream)
        // beginning of line
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)

        // no-op
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 10), affinity: .upstream, dataSource: d)
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 10), affinity: .upstream, dataSource: d)

        // between "a" and "b"
        s = SimpleSelection(caretAt: string.index(at: 11), affinity: .downstream)
        // end of line
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 20), affinity: .upstream, dataSource: d)

        // reset
        s = SimpleSelection(caretAt: string.index(at: 11), affinity: .downstream)
        // beginning of line
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 10), affinity: .downstream, dataSource: d)

        // no-op
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 10), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 20), affinity: .upstream, dataSource: d)
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 20), affinity: .upstream, dataSource: d)

        // between "w" and "r"
        s = SimpleSelection(caretAt: string.index(at: 21), affinity: .downstream)
        // end of line
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 24), affinity: .upstream, dataSource: d)

        // reset
        s = SimpleSelection(caretAt: string.index(at: 21), affinity: .downstream)
        // beginning of line
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 20), affinity: .downstream, dataSource: d)

        // no-op
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 20), affinity: .downstream, dataSource: d)
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 24), affinity: .upstream, dataSource: d)
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 24), affinity: .upstream, dataSource: d)
    }

    func testMoveLineMultipleFragmentsOnFragmentBoundary() {
        let string = """
        0123456789abcdefghijwrap
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // upstream between "9" and "a"
        var s = SimpleSelection(caretAt: string.index(at: 10), affinity: .upstream)
        // left
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        // reset
        s = SimpleSelection(caretAt: string.index(at: 10), affinity: .upstream)
        // moving right is a no-op
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 10), affinity: .upstream, dataSource: d)

        // downstream between "9" and "a"
        s = SimpleSelection(caretAt: string.index(at: 10), affinity: .downstream)
        // right
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 20), affinity: .upstream, dataSource: d)
        // reset
        s = SimpleSelection(caretAt: string.index(at: 10), affinity: .downstream)
        // moving left is a no-op
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 10), affinity: .downstream, dataSource: d)
    }

    func testMoveLineFromSelection() {
        let string = """
        0123456789abcdefghijwrap
        bar
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // select "0123"
        var s = SimpleSelection(anchor: string.index(at: 0), head: string.index(at: 4))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 0), head: string.index(at: 4))
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 10), affinity: .upstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 4), head: string.index(at: 0))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 4), head: string.index(at: 0))
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 10), affinity: .upstream, dataSource: d)

        // select "1234"
        s = SimpleSelection(anchor: string.index(at: 1), head: string.index(at: 5))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 1), head: string.index(at: 5))
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 10), affinity: .upstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 5), head: string.index(at: 1))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 5), head: string.index(at: 1))
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 10), affinity: .upstream, dataSource: d)

        // select "9abc"
        s = SimpleSelection(anchor: string.index(at: 9), head: string.index(at: 13))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 9), head: string.index(at: 13))
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 20), affinity: .upstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 13), head: string.index(at: 9))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 13), head: string.index(at: 9))
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 20), affinity: .upstream, dataSource: d)

        // select "9abcdefghijw"
        s = SimpleSelection(anchor: string.index(at: 9), head: string.index(at: 21))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 9), head: string.index(at: 21))
        // downstream because we're before a hard line break
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 21), head: string.index(at: 9))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 21), head: string.index(at: 9))
        // ditto
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // select "ijwr"
        s = SimpleSelection(anchor: string.index(at: 18), head: string.index(at: 22))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 10), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 18), head: string.index(at: 22))
        // ditto
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 22), head: string.index(at: 18))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 10), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 22), head: string.index(at: 18))
        // ditto
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // select "ap\nba"
        s = SimpleSelection(anchor: string.index(at: 22), head: string.index(at: 27))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 20), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 22), head: string.index(at: 27))
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 28), affinity: .upstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 27), head: string.index(at: 22))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 20), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 27), head: string.index(at: 22))
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 28), affinity: .upstream, dataSource: d)

        // select "a"
        s = SimpleSelection(anchor: string.index(at: 26), head: string.index(at: 27))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 25), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 26), head: string.index(at: 27))
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 28), affinity: .upstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 27), head: string.index(at: 26))
        s = moveAndAssert(s, direction: .beginningOfLine, caretAt: string.index(at: 25), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 27), head: string.index(at: 26))
        s = moveAndAssert(s, direction: .endOfLine, caretAt: string.index(at: 28), affinity: .upstream, dataSource: d)
    }

    func testMoveBeginningOfParagraph() {
        let string = """
        0123456789abcdefghijwrap
        foo

        baz
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // no-ops
        var s = SimpleSelection(caretAt: string.index(at: 0), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 24), affinity: .downstream)
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // no-op around "baz"
        s = SimpleSelection(caretAt: string.index(at: 30), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 30), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 33), affinity: .upstream)
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)

        // no-op in blank line
        s = SimpleSelection(caretAt: string.index(at: 29), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 29), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 29), affinity: .downstream)

        // between "0" and "1"
        s = SimpleSelection(caretAt: string.index(at: 1), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 1), affinity: .downstream)
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // between "9" and "a" upstream
        s = SimpleSelection(caretAt: string.index(at: 10), affinity: .upstream)
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 10), affinity: .upstream)
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // between "9" and "a" downstream
        s = SimpleSelection(caretAt: string.index(at: 10), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 10), affinity: .downstream)
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // between "a" and "b"
        s = SimpleSelection(caretAt: string.index(at: 11), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 11), affinity: .downstream)
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // between "w" and "r"
        s = SimpleSelection(caretAt: string.index(at: 21), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 21), affinity: .downstream)
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // between "o" and "o"
        s = SimpleSelection(caretAt: string.index(at: 27), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 25), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 27), affinity: .downstream)
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 28), affinity: .downstream, dataSource: d)

        // between "a" and "z"
        s = SimpleSelection(caretAt: string.index(at: 32), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 30), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 32), affinity: .downstream)
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)
    }

    func testMoveParagraphFromSelection() {
        let string = """
        0123456789abcdefghijwrap
        foo

        baz
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // select "0123"
        var s = SimpleSelection(anchor: string.index(at: 0), head: string.index(at: 4))
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 0), head: string.index(at: 4))
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 4), head: string.index(at: 0))
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 4), head: string.index(at: 0))
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // select "9abcdefghi"
        s = SimpleSelection(anchor: string.index(at: 9), head: string.index(at: 19))
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 9), head: string.index(at: 19))
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 19), head: string.index(at: 9))
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 19), head: string.index(at: 9))
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 24), affinity: .downstream, dataSource: d)

        // select "rap\nfo"
        s = SimpleSelection(anchor: string.index(at: 21), head: string.index(at: 27))
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 21), head: string.index(at: 27))
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 28), affinity: .downstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 27), head: string.index(at: 21))
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 27), head: string.index(at: 21))
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 28), affinity: .downstream, dataSource: d)

        // select "o\n\nba"
        s = SimpleSelection(anchor: string.index(at: 26), head: string.index(at: 32))
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 25), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 26), head: string.index(at: 32))
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 32), head: string.index(at: 26))
        s = moveAndAssert(s, direction: .beginningOfParagraph, caretAt: string.index(at: 25), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 32), head: string.index(at: 26))
        s = moveAndAssert(s, direction: .endOfParagraph, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)
    }

    func testMoveDocument() {
        let string = """
        0123456789abcdefghijwrap
        foo

        baz
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // no-ops
        var s = SimpleSelection(caretAt: string.index(at: 0), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfDocument, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 33), affinity: .upstream)
        s = moveAndAssert(s, direction: .endOfDocument, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)

        // between "f" and "o"
        s = SimpleSelection(caretAt: string.index(at: 26), affinity: .downstream)
        s = moveAndAssert(s, direction: .beginningOfDocument, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(caretAt: string.index(at: 26), affinity: .downstream)
        s = moveAndAssert(s, direction: .endOfDocument, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)
    }

    func testMoveDocumentFromSelection() {
        let string = """
        0123456789abcdefghijwrap
        foo

        baz
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // select "ijwrap\nfoo\n\nb"
        var s = SimpleSelection(anchor: string.index(at: 18), head: string.index(at: 31))
        s = moveAndAssert(s, direction: .beginningOfDocument, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 18), head: string.index(at: 31))
        s = moveAndAssert(s, direction: .endOfDocument, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)

        // swap anchor and head
        s = SimpleSelection(anchor: string.index(at: 31), head: string.index(at: 18))
        s = moveAndAssert(s, direction: .beginningOfDocument, caretAt: string.index(at: 0), affinity: .downstream, dataSource: d)
        s = SimpleSelection(anchor: string.index(at: 31), head: string.index(at: 18))
        s = moveAndAssert(s, direction: .endOfDocument, caretAt: string.index(at: 33), affinity: .upstream, dataSource: d)
    }

    func testExtendSelectionByCharacter() {
        let string = "Hello, world!"
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // caret at "!"
        var s = SimpleSelection(caretAt: string.index(at: 12), affinity: .downstream)
        s = extendAndAssert(s, direction: .right, selected: "!", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .right, dataSource: d)
        s = extendAndAssert(s, direction: .left, caret: "!", affinity: .downstream, dataSource: d)
        s = extendAndAssert(s, direction: .left, selected: "d", affinity: .upstream, dataSource: d)
        s = extendAndAssert(s, direction: .right, caret: "!", affinity: .downstream, dataSource: d)

        // caret at "e"
        s = SimpleSelection(caretAt: string.index(at: 1), affinity: .downstream)
        s = extendAndAssert(s, direction: .left, selected: "H", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .left, dataSource: d)
        s = extendAndAssert(s, direction: .right, caret: "e", affinity: .downstream, dataSource: d)
        s = extendAndAssert(s, direction: .right, selected: "e", affinity: .downstream, dataSource: d)
        s = extendAndAssert(s, direction: .left, caret: "e", affinity: .downstream, dataSource: d)
    }

    func testExtendSelectionVertically() {
        let string = """
        qux
        0123456789abcdefghijwrap
        xyz
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // caret at "b"
        var s = SimpleSelection(caretAt: string.index(at: 15), affinity: .downstream)
        s = extendAndAssert(s, direction: .up, selected: "123456789a", affinity: .upstream, dataSource: d)
        s = extendAndAssert(s, direction: .up, selected: "ux\n0123456789a", affinity: .upstream, dataSource: d)
        s = extendAndAssert(s, direction: .up, selected: "qux\n0123456789a", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .up, dataSource: d)
        // Even though we went left to the start of the document, we don't adjust xOffset while extending.
        s = extendAndAssert(s, direction: .down, selected: "123456789a", affinity: .upstream, dataSource: d)
        s = extendAndAssert(s, direction: .down, caret: "b", affinity: .downstream, dataSource: d)
        s = extendAndAssert(s, direction: .down, selected: "bcdefghijw", affinity: .downstream, dataSource: d)
        s = extendAndAssert(s, direction: .down, selected: "bcdefghijwrap\nx", affinity: .downstream, dataSource: d)
        s = extendAndAssert(s, direction: .down, selected: "bcdefghijwrap\nxyz", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .down, dataSource: d)
        s = extendAndAssert(s, direction: .up, selected: "bcdefghijw", affinity: .downstream, dataSource: d)
        s = extendAndAssert(s, direction: .up, caret: "b", affinity: .downstream, dataSource: d)
    }

    func testExtendSelectionByWord() {
        let string = "foo; (bar) qux"
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // caret at "a"
        var s = SimpleSelection(caretAt: string.index(at: 7), affinity: .downstream)
        s = extendAndAssert(s, direction: .rightWord, selected: "ar", affinity: .downstream, dataSource: d)
        s = extendAndAssert(s, direction: .rightWord, selected: "ar) qux", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .rightWord, dataSource: d)
        s = extendAndAssert(s, direction: .leftWord, selected: "ar) ", affinity: .downstream, dataSource: d)
        s = extendAndAssert(s, direction: .leftWord, caret: "a", affinity: .downstream, dataSource: d)
        s = extendAndAssert(s, direction: .leftWord, selected: "b", affinity: .upstream, dataSource: d)
        s = extendAndAssert(s, direction: .leftWord, selected: "foo; (b", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .leftWord, dataSource: d)
        s = extendAndAssert(s, direction: .rightWord, selected: "; (b", affinity: .upstream, dataSource: d)
        s = extendAndAssert(s, direction: .rightWord, caret: "a", affinity: .downstream, dataSource: d)
    }

    func testExtendSelectionByLineEmpty() {
        let string = ""
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        var s = SimpleSelection(caretAt: string.startIndex, affinity: .upstream)
        s = extendAndAssert(s, direction: .endOfLine, caretAt: string.startIndex, affinity: .upstream, dataSource: d)
        s = extendAndAssert(s, direction: .beginningOfLine, caretAt: string.startIndex, affinity: .upstream, dataSource: d)
    }

    func testExtendSelectionByLineSoftWrap() {
        let string = "Hello, world!"
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10) // Wraps after "r"

        // caret at "o"
        var s = SimpleSelection(caretAt: string.index(at: 8), affinity: .downstream)
        s = extendAndAssert(s, direction: .endOfLine, selected: "or", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .endOfLine, dataSource: d)
        s = extendAndAssert(s, direction: .beginningOfLine, selected: "Hello, wor", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .beginningOfLine, dataSource: d)

        // caret at "o"
        s = SimpleSelection(caretAt: string.index(at: 8), affinity: .downstream)
        s = extendAndAssert(s, direction: .beginningOfLine, selected: "Hello, w", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .beginningOfLine, dataSource: d)
        s = extendAndAssert(s, direction: .endOfLine, selected: "Hello, wor", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .endOfLine, dataSource: d)
    }

    func testExtendSelectionByLineHardWrap() {
        let string = "foo\nbar\nqux"
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // caret at first "a"
        var s = SimpleSelection(caretAt: string.index(at: 5), affinity: .downstream)
        s = extendAndAssert(s, direction: .endOfLine, selected: "ar", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .endOfLine, dataSource: d)
        s = extendAndAssert(s, direction: .beginningOfLine, selected: "bar", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .beginningOfLine, dataSource: d)

        // caret at first "a"
        s = SimpleSelection(caretAt: string.index(at: 5), affinity: .downstream)
        s = extendAndAssert(s, direction: .beginningOfLine, selected: "b", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .beginningOfLine, dataSource: d)
        s = extendAndAssert(s, direction: .endOfLine, selected: "bar", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .endOfLine, dataSource: d)
    }

    func testExtendSelectionByParagraph() {
        let string = """
        foo
        0123456789wrap
        bar
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // caret at "5"
        var s = SimpleSelection(caretAt: string.index(at: 9), affinity: .downstream)
        s = extendAndAssert(s, direction: .endOfParagraph, selected: "56789wrap", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .endOfParagraph, dataSource: d)
        s = extendAndAssert(s, direction: .beginningOfParagraph, selected: "0123456789wrap", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .beginningOfParagraph, dataSource: d)

        // caret at "5"
        s = SimpleSelection(caretAt: string.index(at: 9), affinity: .downstream)
        s = extendAndAssert(s, direction: .beginningOfParagraph, selected: "01234", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .beginningOfParagraph, dataSource: d)
        s = extendAndAssert(s, direction: .endOfParagraph, selected: "0123456789wrap", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .endOfParagraph, dataSource: d)
    }

    func testExtendSelectionByDocument() {
        let string = """
        foo
        0123456789wrap
        bar
        """
        let d = SimpleSelectionDataSource(string: string, charsPerLine: 10)

        // caret at "5"
        var s = SimpleSelection(caretAt: string.index(at: 9), affinity: .downstream)
        s = extendAndAssert(s, direction: .endOfDocument, selected: "56789wrap\nbar", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .endOfDocument, dataSource: d)
        s = extendAndAssert(s, direction: .beginningOfDocument, selected: "foo\n0123456789wrap\nbar", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .beginningOfDocument, dataSource: d)

        // caret at "5"
        s = SimpleSelection(caretAt: string.index(at: 9), affinity: .downstream)
        s = extendAndAssert(s, direction: .beginningOfDocument, selected: "foo\n01234", affinity: .downstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .beginningOfDocument, dataSource: d)
        s = extendAndAssert(s, direction: .endOfDocument, selected: "foo\n0123456789wrap\nbar", affinity: .upstream, dataSource: d)
        s = extendAndAssertNoop(s, direction: .endOfDocument, dataSource: d)
    }

    func extendAndAssert(_ s: SimpleSelection, direction: Movement, caret c: Character, affinity: SimpleSelection.Affinity, dataSource: SimpleSelectionDataSource, file: StaticString = #file, line: UInt = #line) -> SimpleSelection {
        let s2 = SelectionNavigator(selection: s).extend(direction, dataSource: dataSource)
        assert(selection: s2, hasCaretBefore: c, affinity: affinity, dataSource: dataSource, file: file, line: line)
        return s2
    }

    func extendAndAssert(_ s: SimpleSelection, direction: Movement, selected string: String, affinity: SimpleSelection.Affinity, dataSource: SimpleSelectionDataSource, file: StaticString = #file, line: UInt = #line) -> SimpleSelection {
        let s2 = SelectionNavigator(selection: s).extend(direction, dataSource: dataSource)
        assert(selection: s2, hasRangeCovering: string, affinity: affinity, dataSource: dataSource, file: file, line: line)
        return s2
    }

    func extendAndAssertNoop(_ s: SimpleSelection, direction: Movement, dataSource: SimpleSelectionDataSource, file: StaticString = #file, line: UInt = #line) -> SimpleSelection {
        let s2 = SelectionNavigator(selection: s).extend(direction, dataSource: dataSource)
        XCTAssertEqual(s, s2, file: file, line: line)
        return s2
    }

    func extendAndAssert(_ s: SimpleSelection, direction: Movement, caretAt caret: String.Index, affinity: SimpleSelection.Affinity, dataSource: SimpleSelectionDataSource, file: StaticString = #file, line: UInt = #line) -> SimpleSelection {
        let s2 = SelectionNavigator(selection: s).extend(direction, dataSource: dataSource)
        assert(selection: s2, hasCaretAt: caret, andSelectionAffinity: affinity, file: file, line: line)
        return s2
    }

    func moveAndAssert(_ s: SimpleSelection, direction: Movement, caret c: Character, affinity: SimpleSelection.Affinity, dataSource: SimpleSelectionDataSource, file: StaticString = #file, line: UInt = #line) -> SimpleSelection {
        let s2 = SelectionNavigator(selection: s).move(direction, dataSource: dataSource)
        assert(selection: s2, hasCaretBefore: c, affinity: affinity, dataSource: dataSource, file: file, line: line)
        return s2
    }

    func moveAndAssert(_ s: SimpleSelection, direction: Movement, selected string: String, affinity: SimpleSelection.Affinity, dataSource: SimpleSelectionDataSource, file: StaticString = #file, line: UInt = #line) -> SimpleSelection {
        let s2 = SelectionNavigator(selection: s).move(direction, dataSource: dataSource)
        assert(selection: s2, hasRangeCovering: string, affinity: affinity, dataSource: dataSource, file: file, line: line)
        return s2
    }

    func moveAndAssertNoop(_ s: SimpleSelection, direction: Movement, dataSource: SimpleSelectionDataSource, file: StaticString = #file, line: UInt = #line) -> SimpleSelection {
        let s2 = SelectionNavigator(selection: s).move(direction, dataSource: dataSource)
        XCTAssertEqual(s, s2, file: file, line: line)
        return s2
    }

    func moveAndAssert(_ s: SimpleSelection, direction: Movement, caretAt caret: String.Index, affinity: SimpleSelection.Affinity, dataSource: SimpleSelectionDataSource, file: StaticString = #file, line: UInt = #line) -> SimpleSelection {
        let s2 = SelectionNavigator(selection: s).move(direction, dataSource: dataSource)
        assert(selection: s2, hasCaretAt: caret, andSelectionAffinity: affinity, file: file, line: line)
        return s2
    }

    func assert(selection: SimpleSelection, hasCaretBefore c: Character, affinity: SimpleSelection.Affinity, dataSource: SimpleSelectionDataSource, file: StaticString = #file, line: UInt = #line) {
        XCTAssert(selection.isCaret, "selection is not a caret", file: file, line: line)
        XCTAssertEqual(dataSource.string[selection.range.lowerBound], c, "caret is not at '\(c)'", file: file, line: line)
        XCTAssertEqual(affinity, selection.affinity, file: file, line: line)
    }

    func assert(selection: SimpleSelection, hasRangeCovering string: String, affinity: SimpleSelection.Affinity, dataSource: SimpleSelectionDataSource, file: StaticString = #file, line: UInt = #line) {
        let range = selection.range
        XCTAssert(selection.isRange, "selection is not a range", file: file, line: line)
        XCTAssertEqual(String(dataSource.string[range]), string, "selection does not contain \"\(string)\"", file: file, line: line)
        XCTAssertEqual(affinity, selection.affinity, file: file, line: line)
    }

    func assert(selection: SimpleSelection, hasCaretAt caretIndex: String.Index, andSelectionAffinity affinity: SimpleSelection.Affinity, file: StaticString = #file, line: UInt = #line) {
        XCTAssert(selection.isCaret)
        XCTAssertEqual(selection.lowerBound, caretIndex, file: file, line: line)
        XCTAssertEqual(affinity, selection.affinity, file: file, line: line)
    }
}
