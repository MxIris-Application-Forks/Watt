//
//  TextView+Scrolling.swift
//  Watt
//
//  Created by David Albert on 3/17/24.
//

import Cocoa

extension TextView {
    override class var isCompatibleWithResponsiveScrolling: Bool {
        true
    }

    class func scrollableTextView() -> NSScrollView {
        let textView = Self()

        let clipView = ClipView()
        clipView.delegate = textView

        let scrollView = NSScrollView()
        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView

        textView.autoresizingMask = [.width, .height]

        return scrollView
    }

    var scrollView: NSScrollView? {
        if let enclosingScrollView, enclosingScrollView.documentView == self {
            return enclosingScrollView
        }

        return nil
    }

    var scrollOffset: CGPoint {
        guard let scrollView else {
            return .zero
        }

        return scrollView.contentView.bounds.origin
    }

    var textContainerScrollOffset: CGPoint {
        convertToTextContainer(scrollOffset)
    }

    func scrollIndexToVisible(_ index: Buffer.Index) {
        guard let rect = layoutManager.caretRect(for: index, affinity: index == buffer.endIndex ? .upstream : .downstream) else {
            return
        }

        let viewRect = convertFromTextContainer(rect)
        scrollToVisible(viewRect)
    }

    func scrollIndexToCenter(_ index: Buffer.Index) {
        guard let rect = layoutManager.caretRect(for: index, affinity: index == buffer.endIndex ? .upstream : .downstream) else {
            return
        }

        let viewRect = convertFromTextContainer(rect)
        scrollToCenter(viewRect)
    }

    func scrollToCenter(_ rect: NSRect) {
        let dx = rect.midX - visibleRect.midX
        let dy = rect.midY - visibleRect.midY
        scroll(CGPoint(x: scrollOffset.x + dx, y: scrollOffset.y + dy))
    }

    @objc func clipViewDidScroll(_ notification: Notification) {
        transaction {
            schedule(.textLayout)
            schedule(.selectionLayout)
            schedule(.insertionPointLayout)
        }
    }

    @objc func willStartLiveScroll(_ notification: Notification) {
        guard let scrollView = notification.object as? NSScrollView else {
            return
        }

        isDraggingScroller = scrollView.verticalScroller?.hitPart == .knob
    }

    @objc func didEndLiveScroll(_ notification: Notification) {
        isDraggingScroller = false
    }
}
