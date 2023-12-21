//
//  TextView+Input.swift
//  Watt
//
//  Created by David Albert on 5/24/23.
//

import Cocoa

extension TextView {
    override func keyDown(with event: NSEvent) {
        NSCursor.setHiddenUntilMouseMoves(true)

        if inputContext?.handleEvent(event) ?? false {
            return
        }

        // I was able to find some odd key combinations that caused inputContext
        // not to handle a keyDown event. I don't remember what they were. Just log
        // them in Release, crash in Debug.
        assertionFailure("keyDown: inputContext didn't handle this event: \(event)")
        print("keyDown: inputContext didn't handle this event: \(event)")
    }
}

extension TextView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let range = getReplacementRange(for: replacementRange) else {
            return
        }

        let attrRope: AttributedRope
        if let attrStr = string as? NSAttributedString {
            attrRope = AttributedRope(attrStr, merging: typingAttributes)
        } else {
            attrRope = AttributedRope(string as! String, attributes: typingAttributes)
        }

        replaceSubrange(range, with: attrRope)

        print("insertText - ", terminator: "")
        unmarkText()
    }

    override func doCommand(by selector: Selector) {
        print("doCommand(by: #selector(\(selector)))")
        if responds(to: selector) {
            perform(selector, with: nil)
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        print("setMarkedText")
        guard let range = getReplacementRange(for: replacementRange) else {
            return
        }

        let attrRope: AttributedRope
        if let attrStr = string as? NSAttributedString {
            attrRope = AttributedRope(attrStr, merging: typingAttributes)
        } else {
            attrRope = AttributedRope(string as! String, attributes: typingAttributes.merging(markedTextAttributes))
        }

        replaceSubrange(range, with: attrRope)

        let start = buffer.index(fromOldIndex: range.lowerBound)
        let anchor = buffer.utf16.index(start, offsetBy: selectedRange.lowerBound)
        let head = buffer.utf16.index(anchor, offsetBy: selectedRange.length)

        let markedRange: Range<Buffer.Index>?
        if attrRope.count == 0 {
            markedRange = nil
        } else {
            let end = buffer.index(start, offsetBy: attrRope.count)
            markedRange = start..<end
        }

        if anchor == head {
            layoutManager.selection = Selection(caretAt: anchor, affinity: anchor == buffer.endIndex ? .upstream : .downstream, granularity: .character, xOffset: nil, markedRange: markedRange)
        } else {
            layoutManager.selection = Selection(anchor: anchor, head: head, granularity: .character, xOffset: nil, markedRange: markedRange)
        }
    }

    func unmarkText() {
        print("unmarkText")

        layoutManager.selection = layoutManager.selection.unmarked

        // TODO: if we're the only one who calls unmarkText(), we can remove
        // these layout calls, because we already do layout in didInvalidateLayout(for layoutManager: LayoutManager)
        textLayer.setNeedsLayout()
        selectionLayer.setNeedsLayout()
        insertionPointLayer.setNeedsLayout()
    }

    func selectedRange() -> NSRange {
        NSRange(layoutManager.selection.range, in: buffer)
    }

    func markedRange() -> NSRange {
        guard let markedRange = layoutManager.selection.markedRange else {
            return .notFound
        }

        return NSRange(markedRange, in: buffer)
    }

    func hasMarkedText() -> Bool {
        layoutManager.selection.markedRange != nil
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let range = Range(range, in: buffer) else {
            return nil
        }

        let documentRange = buffer.documentRange
        if !range.overlaps(documentRange) {
            return nil
        }

        let clamped = range.clamped(to: documentRange)
        actualRange?.pointee = NSRange(clamped, in: buffer)

        return layoutManager.nsAttributedString(for: clamped)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        // Derived from NSTextView on macOS 13.4. I left out NSTextInsertionUndoable and
        // NSTextInputReplacementRangeAttributeName, which are private.
        return [.font, .underlineStyle, .foregroundColor, .backgroundColor, .underlineColor, .markedClauseSegment, .languageIdentifier, .glyphInfo, .textAlternatives, .attachment]

    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let range = Range(range, in: buffer) else {
            return .zero
        }

        // TODO: We need to deal with affinity if range is empty. It might be asking us for the rect
        // of a caret at the end of a line fragment. Neither firstRect(forRange:) nor
        // enumerateTextSegments(in:type:using:) do anything with affinity at the moment.
        guard let (rect, rectRange) = layoutManager.firstRect(forRange: range) else {
            return .zero
        }

        actualRange?.pointee = NSRange(rectRange, in: buffer)

        // TODO: from the docs:
        //   If the length of aRange is 0 (as it would be if there is nothing
        //   selected at the insertion point), the rectangle coincides with the
        //   insertion point, and its width is 0.
        //
        // We need to verify that rect has a zero width when range.isEmpty. I bet
        // it doesn't.
        let viewRect = convertFromTextContainer(rect)
        let windowRect = convert(viewRect, to: nil)
        let screenRect = window?.convertToScreen(windowRect) ?? .zero

        return screenRect
    }

    func characterIndex(for screenPoint: NSPoint) -> Int {
        guard let window else {
            return NSNotFound
        }

        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = convert(windowPoint, from: nil)
        let point = convertToTextContainer(viewPoint)
        let i = layoutManager.index(for: point)
        return buffer.distance(from: buffer.startIndex, to: i)
    }
}

extension TextView {
    private func getReplacementRange(for proposed: NSRange) -> Range<Buffer.Index>? {
        if proposed != .notFound {
            return Range(proposed, in: buffer)
        }

        return layoutManager.selection.markedRange ?? layoutManager.selection.range
    }

    func discardMarkedText() {
        inputContext?.discardMarkedText()

        // Most of the time when an unexpected event comes in when there's marked text,
        // AppKit will call insert(_:replacementRange:) to replace the marked text with
        // normal text.
        //
        // For mouse events, however, that doesn't seem to happen happen. Ditto for
        // things the text system doesn't know about, like selectAll(_:), etc. So
        // here we manually clear the marked text styles.
        if let markedRange = layoutManager.selection.markedRange {
            buffer.setAttributes(typingAttributes, in: markedRange)
        }
    }

    func replaceSubrange(_ subrange: Range<Buffer.Index>, with s: AttributedRope) {
        buffer.replaceSubrange(subrange, with: s)
        updateStateAfterReplacingSubrange(subrange, withStringOfCount: s.count)
    }

    func replaceSubrange(_ subrange: Range<Buffer.Index>, with s: String) {
        buffer.replaceSubrange(subrange, with: s)
        updateStateAfterReplacingSubrange(subrange, withStringOfCount: s.count)
    }

    func updateStateAfterReplacingSubrange(_ subrange: Range<Buffer.Index>, withStringOfCount count: Int) {
        // TODO: Once we have multiple selections, we have to make sure to put each
        // selection in the correct location.
        let head = buffer.index(buffer.index(fromOldIndex: subrange.lowerBound), offsetBy: count)
        let affinity: Affinity = head == buffer.endIndex ? .upstream : .downstream
        layoutManager.selection = Selection(caretAt: head, affinity: affinity, granularity: .character, xOffset: nil, markedRange: nil)
        
        scrollSelectionToVisible()
    }
}
