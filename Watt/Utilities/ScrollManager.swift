//
//  ScrollManager.swift
//  Watt
//
//  Created by David Albert on 3/20/24.
//

import Cocoa
import Motion

protocol ScrollManagerDelegate: AnyObject {
    // Called once for every call to documentRect(_:didResizeTo:) that queues up a scroll correction.
    func scrollManager(_ scrollManager: ScrollManager, willCorrectScrollBy delta: CGVector)

    // Called once per run loop tick directly before scroll correction is performed – i.e. before
    // NSView.scroll(_:) is called on the documentView. This method is called regardless of whether
    // NSView.scroll(_:) is actually called, and can correspond to multiple calls to
    // scrollManager(_:willCorrectScrollBy:).
    func scrollManagerWillCommitScrollCorrection(_ scrollManager: ScrollManager)

    // Same semantics as scrollManagerWillCommitScrollCorrection(_:), but called after a possible call
    // to NSView.scroll(_:) rather than before.
    func scrollManagerDidCommitScrollCorrection(_ scrollManager: ScrollManager)
}

extension ScrollManagerDelegate {
    func scrollManager(_ scrollManager: ScrollManager, willCorrectScrollBy delta: CGVector) {}
    func scrollManagerWillCommitScrollCorrection(_ scrollManager: ScrollManager) {}
    func scrollManagerDidCommitScrollCorrection(_ scrollManager: ScrollManager) {}
}

@MainActor
class ScrollManager {
    // A unit point for determining the part of the viewport anchored for an animated scroll
    struct Anchor {
        let x: CGFloat
        let y: CGFloat

        static let topLeading = Anchor(x: 0, y: 0)
        static let top = Anchor(x: 0.5, y: 0)
        static let topTrailing = Anchor(x: 1, y: 0)

        static let leading = Anchor(x: 0, y: 0.5)
        static let center = Anchor(x: 0.5, y: 0.5)
        static let trailing = Anchor(x: 1, y: 0.5)

        static let bottomLeading = Anchor(x: 0, y: 1)
        static let bottom = Anchor(x: 0.5, y: 1)
        static let bottomTrailing = Anchor(x: 1, y: 1)
    }

    struct Animation {
        var spring: SpringAnimation<CGPoint>
        var anchor: Anchor

        var velocity: CGPoint {
            spring.velocity
        }

        func scrollDestination(in viewport: CGRect) -> CGPoint {
            CGPoint(
                x: spring.toValue.x - (viewport.width * anchor.x),
                y: spring.toValue.y - (viewport.height * anchor.y)
            )
        }

        func stop() {
            spring.stop()
        }
    }

    private(set) weak var view: NSView?
    private(set) var isDraggingScroller: Bool

    private(set) var scrollOffset: CGPoint
    private var prevScrollOffset: CGPoint
    private var prevLiveScrollOffset: CGPoint?
    private var delta: CGVector

    private var needsScrollCorrection: Bool

    var isLiveScrolling: Bool
    var didLiveScroll: Bool

    private var animation: Animation?

    var isAnimating: Bool {
        animation != nil
    }

    weak var delegate: ScrollManagerDelegate?

    // We use a run loop observer, rather than DispatchQueue.main.async because we want to be able to wait
    // until after layout has been performed to do scroll correction. While this is possible to do with
    // DispatchQueue – we'd just have to reschedule performScrollCorrectionIfNecessary() if layout hasn't
    // been performed yet – it's a bit clearer if we just check every tick of the run loop.
    private var observer: CFRunLoopObserver?

    init(_ view: NSView) {
        self.view = view
        self.isDraggingScroller = false
        self.scrollOffset = .zero
        self.prevScrollOffset = .zero
        self.delta = .zero
        self.needsScrollCorrection = false

        self.isLiveScrolling = false
        self.didLiveScroll = false

        var context = CFRunLoopObserverContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)

        // .beforeSources is after .beforeTimers, and layout is run on .beforeTimers, so we use .beforeSources so that we
        // can run as early as possible after layout occurs.
        let observer = CFRunLoopObserverCreate(kCFAllocatorDefault, CFRunLoopActivity.beforeSources.rawValue, true, 0, { observer, activity, info in
            let scrollManager = Unmanaged<ScrollManager>.fromOpaque(info!).takeUnretainedValue()
            scrollManager.observe()
        }, &context)

        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer

        if view.superview != nil {
            viewDidMoveToSuperview()
        }
    }

    deinit {
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    // If you're changing your view's frame directly in one of the below notifications, make sure to call
    // ScrollManager.viewDidMoveToSuperview() before attaching your own observers. ScrollManager needs its
    // observers to be called first so that its state can be correctly set up for any calls
    // to documentRect(_:didResizeTo:)
    func viewDidMoveToSuperview() {
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSScrollView.willStartLiveScrollNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSScrollView.didLiveScrollNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSScrollView.didEndLiveScrollNotification, object: nil)

        animation?.stop()
        animation = nil

        isDraggingScroller = false
        needsScrollCorrection = false

        isLiveScrolling = false
        didLiveScroll = false

        let offset = view?.enclosingScrollView?.contentView.bounds.origin ?? .zero
        scrollOffset = offset
        prevScrollOffset = offset
        prevLiveScrollOffset = nil
        delta = .zero

        if let scrollView = view?.enclosingScrollView {
            NotificationCenter.default.addObserver(self, selector: #selector(viewDidScroll(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(willStartLiveScroll(_:)), name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
            NotificationCenter.default.addObserver(self, selector: #selector(didLiveScroll(_:)), name: NSScrollView.didLiveScrollNotification, object: scrollView)
            NotificationCenter.default.addObserver(self, selector: #selector(didEndLiveScroll(_:)), name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        }
    }

    func animateScroll(to point: NSPoint, viewportAnchor anchor: Anchor) {
        guard let scrollView = view?.enclosingScrollView else {
            return
        }

        let velocity = animation?.velocity ?? .zero
        animation?.stop()

        assert(scrollOffset == scrollView.contentView.bounds.origin)
        let spring = SpringAnimation(
            initialValue: scrollOffset,
            response: 0.2,
            dampingRatio: 1.0,
            environment: scrollView
        )

        let viewport = scrollView.contentView.bounds

        spring.toValue = CGPoint(
            x: point.x + (viewport.width * anchor.x),
            y: point.y + (viewport.height * anchor.y)
        )
        spring.velocity = velocity
        spring.resolvingEpsilon = 0.000001

        spring.onValueChanged() { [weak self] value in
            guard let scrollView = self?.view?.enclosingScrollView else {
                return
            }
            let viewport = scrollView.contentView.bounds
            let offset = CGPoint(
                x: value.x - (viewport.width * anchor.x),
                y: value.y - (viewport.height * anchor.y)
            )
            scrollView.documentView?.scroll(offset)
        }

        spring.completion = { [weak self] in
            self?.animation = nil
        }

        spring.start()
        animation = Animation(spring: spring, anchor: anchor)
    }

    // Assumes the new rect has the same origin. In other words, rect always grows down and right.
    func documentRect(_ rect: NSRect, didResizeTo newSize: NSSize) {
        guard let scrollView = view?.enclosingScrollView else {
            return
        }

        assert(scrollOffset == scrollView.contentView.bounds.origin)
        // If we're dragging the scroller, we're requesting an absolute percent through the document.
        // If layout changed at all while dragging, we're going to be in the wrong place, and need
        // to correct.
        if isDraggingScroller {
            needsScrollCorrection = true
            return
        }

        let cutoff: CGPoint
        if let animation {
            let viewport = scrollView.contentView.bounds
            let destination = animation.scrollDestination(in: viewport)
            cutoff = CGPoint(
                x: destination.x + delta.dx,
                y: destination.y + delta.dy
            )
        } else {
            // If we're scrolling, the goal is to have no jump between the previous frame and this frame.
            // If we're scrolling up (which is the case where this generally matters), rects that will
            // cause a jump are those that are fully above the viewport. But if we're forcing layout because
            // we're scrolling up, all rects that are being laid out are by definition in the viewport this
            // frame. So we have to look at the previous frame to see if we should apply the correction.
            //
            // If we're not scrolling and the document changed size, e.g. because of an edit, just use the
            // current frame.
            //
            // I'm less sure about using prevLiveScrollOffset when we're scrolling down. In general, scrolling
            // down will only cause layout below the viewport, and that shouldn't cause a scroll correction
            // while we're not animating. So this means when scrolling down, the only corrections we should get
            // are from edits in the document. When we're scrolling down, prevLiveScrollOffset.y will be
            // less than scrollOffset.y, which means we're being more restrictive in when we'll do a scroll
            // correction than we otherwise would be if we weren't scrolling. Not sure whether this will
            // cause any issues.

            // TODO: get rid of prevLiveScrollOffset and do scrollOffset + delta?
            cutoff = prevLiveScrollOffset ?? scrollOffset
        }


        let dx = rect.maxX <= cutoff.x ? newSize.width - rect.width : 0
        let dy = rect.maxY <= cutoff.y ? newSize.height - rect.height : 0

        if dx == 0 && dy == 0 {
            return
        }

        needsScrollCorrection = true
        delta += CGVector(dx: dx, dy: dy)
        delegate?.scrollManager(self, willCorrectScrollBy: CGVector(dx: dx, dy: dy))
    }

    @objc func viewDidScroll(_ notification: Notification) {
        guard let scrollView = view?.enclosingScrollView else {
            return
        }

        assert(scrollView.contentView == (notification.object as? NSView))

        prevLiveScrollOffset = nil
        prevScrollOffset = scrollOffset
        scrollOffset = scrollView.contentView.bounds.origin
    }

    @objc func willStartLiveScroll(_ notification: Notification) {
        // If the user interrupts the scroll for any reason, stop the animation.
        animation?.stop()
        animation = nil

        guard let scrollView = notification.object as? NSScrollView else {
            return
        }

        isLiveScrolling = true

        isDraggingScroller = scrollView.horizontalScroller?.hitPart == .knob || scrollView.verticalScroller?.hitPart == .knob
    }

    @objc func didLiveScroll(_ notification: Notification) {
        // From the didLiveScrollNotification docs: "Some user-initiated scrolls (for example, scrolling
        // using legacy mice) are not bracketed by a "willStart/didEnd” notification pair."
        animation?.stop()
        animation = nil

        guard let scrollView = notification.object as? NSScrollView else {
            return
        }

        didLiveScroll = true
        prevLiveScrollOffset = prevScrollOffset

        assert(scrollView == view?.enclosingScrollView)

        if isDraggingScroller {
            needsScrollCorrection = true
        }
    }

    @objc func didEndLiveScroll(_ notification: Notification) {

        isLiveScrolling = false
        didLiveScroll = false
        isDraggingScroller = false

        prevLiveScrollOffset = nil
    }

    private func observe() {
        // We always want scroll correction to run after layout so that we can take into account any resizing
        // that happens during layout. Layout happens in a .beforeTimers observer, and we run in a .beforeSources
        // observer, which happens later. But there may be any number of iterations through run loop between when
        // needsScrollCorrection is set and layout is run. So if layout hasn't happened yet, bail early.
        if let view, view.needsLayout {
            return
        }

        performScrollCorrectionIfNecessary()

        // We used a scroll wheel and didn't get willBeginLiveScroll. Reset scrolling here.
        if didLiveScroll && !isLiveScrolling {
            didLiveScroll = false
            prevLiveScrollOffset = nil
            assert(!isDraggingScroller)
        }
    }

    private func performScrollCorrectionIfNecessary() {
        if !needsScrollCorrection {
            return
        }

        needsScrollCorrection = false

        guard let scrollView = view?.enclosingScrollView else {
            return
        }

        // Dragging a scroller is equivalent to telling the scroll view "please set your offset to this
        // fixed percentage through the document." In this case, scroll correction just consists of
        // reading the percentage out of the scrollers and setting the new origin if the document size
        // has changed.
        if isDraggingScroller {
            assert(!isAnimating)

            // Ignore delta because we're scrolling to an absolute position.
            delta = .zero

            delegate?.scrollManagerWillCommitScrollCorrection(self)
            defer { delegate?.scrollManagerDidCommitScrollCorrection(self) }

            assert(scrollView.documentView != nil)
            guard let documentSize = scrollView.documentView?.frame.size else {
                return
            }

            let viewport = scrollView.contentView.bounds
            let offset = NSPoint(
                x: CGFloat(scrollView.horizontalScroller?.floatValue ?? 0) * (documentSize.width - viewport.width),
                y: CGFloat(scrollView.verticalScroller?.floatValue ?? 0) * (documentSize.height - viewport.height)
            )

            if viewport.origin != offset {
                scrollView.documentView?.scroll(offset)
            }
            return
        }


        delegate?.scrollManagerWillCommitScrollCorrection(self)

        // documentView?.scroll(_:) can cause additional calls to documentRect(_:didResizeTo), which can request
        // further scroll correction and increment delta. If we do `delta = .zero` after calling scroll(_:), we'd
        // throw out those extra deltas.
        let d = delta
        delta = .zero

        if d != .zero {
            scrollView.documentView?.scroll(scrollOffset + d)
            if let animation {
                let viewport = scrollView.contentView.bounds
                animateScroll(to: animation.scrollDestination(in: viewport) + d, anchor: animation.anchor)
            }
        }

        delegate?.scrollManagerDidCommitScrollCorrection(self)
    }
}
