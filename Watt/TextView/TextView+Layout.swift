//
//  TextView+Layout.swift
//  Watt
//
//  Created by David Albert on 4/29/23.
//

import Cocoa

extension TextView: CALayerDelegate, NSViewLayerContentScaleDelegate {
    override func layout() {
        // If we need to call setNeedsLayout on our subviews, do it here,
        // before calling super.layout()

        super.layout()

        guard let layer else {
            return
        }

        if selectionLayer.superlayer == nil {
            selectionLayer.bounds = layer.bounds
            layer.addSublayer(selectionLayer)
        }

        if textLayer.superlayer == nil {
            textLayer.bounds = layer.bounds
            layer.addSublayer(textLayer)
        }

        if insertionPointLayer.superlayer == nil {
            insertionPointLayer.bounds = layer.bounds
            layer.addSublayer(insertionPointLayer)
        }
    }

    func layer(_ layer: CALayer, shouldInheritContentsScale newScale: CGFloat, from window: NSWindow) -> Bool {
        true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextContainerSizeIfNeeded()
    }

    func updateTextContainerSizeIfNeeded() {
        let inset = computedTextContainerInset
        let width = max(0, frame.width - inset.left - inset.right)

        if layoutManager.textContainer.size.width != width {
            layoutManager.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)

            layoutTextLayer()
            layoutSelectionLayer()
            layoutInsertionPointLayer()
        }
    }

    func updateFrameHeightIfNeeded() {
        guard let scrollView else {
            return
        }

        let currentHeight = frame.height
        let clipviewHeight = scrollView.contentSize.height
        let inset = computedTextContainerInset
        let newHeight = round(max(clipviewHeight, layoutManager.contentHeight + inset.top + inset.bottom))

        if abs(currentHeight - newHeight) > 1e-10 {
            setFrameSize(CGSize(width: frame.width, height: newHeight))
        }
    }

    // Takes the user specified textContainerInset and combines
    // it with the line number view's dimensions.
    func updateComputedTextContainerInset() {
        let userInset = textContainerInset

        if lineNumberView.superview != nil {
            computedTextContainerInset = NSEdgeInsets(
                top: userInset.top,
                left: userInset.left + lineNumberView.frame.width,
                bottom: userInset.bottom,
                right: userInset.right
            )
        } else {
            computedTextContainerInset = userInset
        }
    }

    func convertFromTextContainer(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + computedTextContainerInset.left, y: point.y + computedTextContainerInset.top)
    }

    func convertToTextContainer(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - computedTextContainerInset.left, y: point.y - computedTextContainerInset.top)
    }

    func convertFromTextContainer(_ rect: CGRect) -> CGRect {
        CGRect(origin: convertFromTextContainer(rect.origin), size: rect.size)
    }

    func convertToTextContainer(_ rect: CGRect) -> CGRect {
        CGRect(origin: convertToTextContainer(rect.origin), size: rect.size)
    }

    // Returns a rectangle in the view's coordinate system, but with any porition
    // of the rectangle that overlaps the text container inset removed.
    func clampToTextContainer(_ rect: CGRect) -> CGRect {
        let textContainerFrame = convertFromTextContainer(textContainer.bounds)

        // Don't use CGRect.intersection because we never want to return a null rect.
        // With intersection, we will get a null rect if rect is completely outside
        // of textContainerFrame.
        let x = rect.minX.clamped(to: textContainerFrame.minX...textContainerFrame.maxX)
        let y = rect.minY.clamped(to: textContainerFrame.minY...textContainerFrame.maxY)
        let maxX = rect.maxX.clamped(to: textContainerFrame.minX...textContainerFrame.maxX)
        let maxY = rect.maxY.clamped(to: textContainerFrame.minY...textContainerFrame.maxY)

        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    var textContainerVisibleRect: CGRect {
        convertToTextContainer(clampToTextContainer(visibleRect))
    }
}

extension TextView: LayoutManagerDelegate {
    func viewportBounds(for layoutManager: LayoutManager) -> CGRect {
        textContainerVisibleRect
    }

    func didInvalidateLayout(for layoutManager: LayoutManager) {
        layoutTextLayer()

        updateInsertionPointTimer()
        inputContext?.invalidateCharacterCoordinates()
        updateFrameHeightIfNeeded()
    }

    func defaultAttributes(for layoutManager: LayoutManager) -> AttributedRope.Attributes {
        defaultAttributes
    }

    func selections(for layoutManager: LayoutManager) -> [Selection] {
        [selection]
    }

    func layoutManager(_ layoutManager: LayoutManager, attributedSubropeFor attrSubrope: consuming AttributedSubrope) -> AttributedSubrope {
        attrSubrope.mergeAttributes(defaultAttributes, mergePolicy: .keepCurrent)

        attrSubrope.transformAttributes(\.token) { attr in
            var attributes = theme[attr.value!.type] ?? AttributedRope.Attributes()

            if attributes.font != nil {
                attributes.symbolicTraits = nil
                attributes.fontWeight = nil
            } else {
                // I don't know if making familyName fall back to font.fontName is
                // correct, but it seems like it could be reasonable.
                var d = font
                    .fontDescriptor
                    .withFamily(font.familyName ?? font.fontName)
                    .addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: attributes.fontWeight ?? .regular]])

                if let symbolicTraits = attributes.symbolicTraits {
                    d = d.withSymbolicTraits(symbolicTraits)
                }

                attributes.font = NSFont(descriptor: d, size: font.pointSize) ?? font
            }

            return attr.replace(with: attributes)
        }

        return attrSubrope
    }

    func layoutManager(_ layoutManager: LayoutManager, bufferDidReload buffer: Buffer) {
        lineNumberView.lineCount = buffer.lines.count
        selection = Selection(atStartOf: buffer)
    }

    // TODO: once we're showing the same Buffer in more than one TextView, editing the text in one TextView
    // will cause the selection indexes in the other TextViews to become invalid, and trigger a precondition
    // failure on the next render.
    //
    // Really what we want to do is update all selections here in a reasonable way (e.g. delete them if the
    // selected text has been deleted), and then in the TextView that caused the edit, reset the selections
    // again to be what they should be after the edit.
    //
    // KeyBindingResponder should probably be responsible for this.
    func layoutManager(_ layoutManager: LayoutManager, buffer: Buffer, contentsDidChangeFrom old: Rope, to new: Rope, withDelta delta: BTreeDelta<Rope>) {
        lineNumberView.lineCount = new.lines.count
    }

    func layoutManager(_ layoutManager: LayoutManager, createLayerForLine line: Line) -> LineLayer {
        let l = LineLayer(line: line)
        l.anchorPoint = .zero
        // Bounds origin is always (0, 0), so setNeedsDisplay() will only be called when the
        // layer's size changes due window resize.
        l.needsDisplayOnBoundsChange = true
        l.delegate = self // LineLayerDelegate + NSViewLayerContentScaleDelegate
        l.contentsScale = window?.backingScaleFactor ?? 1.0
        return l
    }

    func layoutManager(_ layoutManager: LayoutManager, positionLineLayer layer: LineLayer) {
        layer.bounds = layer.line.renderingSurfaceBounds
        layer.position = convertFromTextContainer(layer.line.origin)
    }
}

// MARK: - Text layout

extension TextView {
    func layoutTextLayer() {
        if window == nil {
            return
        }

        var scrollAdjustment: CGFloat = 0
        let updateLineNumbers = lineNumberView.superview != nil
        if updateLineNumbers {
            lineNumberView.beginUpdates()
        }

        var lineno: Int?

        var layers: [CALayer] = []
        layoutManager.layoutText { layer, prevAlignmentFrame in
            layers.append(layer)

            let oldHeight = prevAlignmentFrame.height
            let newHeight = layer.line.alignmentFrame.height
            let delta = newHeight - oldHeight
            let oldMaxY = layer.line.origin.y + oldHeight

            // TODO: I don't know why I have to use the previous frame's
            // visible rect here. My best guess is that it has something
            // to do with the fact that I'm doing deferred layout of my
            // sublayers (e.g. textLayer.setNeedsLayout(), etc.). I tried
            // changing the deferred layout calls in prepareContent(in:)
            // to immediate layout calls, but it didn't seem to fix the
            // problem. On the other hand, I'm not sure if I've totally
            // gotten scroll correction right here anyways (there are
            // sometimes things that look like jumps during scrolling).
            // I'll come back to this later.
            if oldMaxY <= previousVisibleRect.minY && delta != 0 {
                scrollAdjustment += delta
            }

            if updateLineNumbers {
                let n = lineno ?? buffer.lines.distance(from: buffer.startIndex, to: layer.line.range.lowerBound)
                let inset = computedTextContainerInset
                let origin = CGPoint(
                    x: layer.line.alignmentFrame.minX + inset.left - lineNumberView.frame.width,
                    y: layer.line.alignmentFrame.minY + inset.top
                )
                lineNumberView.addLineNumber(n+1, withAlignmentFrame: CGRect(origin: origin, size: layer.line.alignmentFrame.size))
                lineno = n+1
            }
        }

        textLayer.setSublayers(to: layers)

        if updateLineNumbers {
            lineNumberView.endUpdates()
        }

        previousVisibleRect = visibleRect

        // Adjust scroll offset.
        // TODO: is it possible to move this into prepareContent(in:) directly?
        // That way it would only happen when we scroll. It's also possible
        // that would let us get rid of previousVisibleRect, but according to
        // the comment below, I tried that, so I'm doubtful.
        if scrollAdjustment != 0 {
            let current = scrollOffset
            scroll(CGPoint(x: current.x, y: current.y + scrollAdjustment))
        }

        updateFrameHeightIfNeeded()
    }
}

extension TextView: LineLayerDelegate {
    func effectiveAppearance(for lineLayer: LineLayer) -> NSAppearance {
        effectiveAppearance
    }
}


// MARK: - Selection layout

extension TextView {
    func layoutSelectionLayer() {
        if window == nil {
            return
        }

        selectionLayer.sublayers = nil

        layoutManager.layoutSelections { rect in
            let l = selectionLayerCache[rect] ?? makeLayer(forSelectionRect: rect)
            selectionLayerCache[rect] = l

            selectionLayer.addSublayer(l)
        }
    }

    func makeLayer(forSelectionRect rect: CGRect) -> CALayer {
        let l = SelectionLayer()
        l.anchorPoint = .zero
        l.delegate = self // SelectionLayerDelegate +  NSViewLayerContentScaleDelegate
        l.needsDisplayOnBoundsChange = true
        l.contentsScale = window?.backingScaleFactor ?? 1.0
        l.isOpaque = true
        l.bounds = CGRect(origin: .zero, size: rect.size)
        l.position = convertFromTextContainer(rect.origin)

        return l
    }
}

// MARK: - Insertion point layout

extension TextView {
    func layoutInsertionPointLayer() {
        if window == nil {
            return
        }

        insertionPointLayer.sublayers = nil

        layoutManager.layoutInsertionPoints { rect in
            let l = insertionPointLayerCache[rect] ?? makeLayer(forInsertionPointRect: rect)
            selectionLayerCache[rect] = l

            insertionPointLayer.addSublayer(l)
        }
    }

    func makeLayer(forInsertionPointRect rect: CGRect) -> CALayer {
        let l = InsertionPointLayer()
        l.anchorPoint = .zero
        l.delegate = self // InsertionPointLayerDelegate + NSViewLayerContentScaleDelegate
        l.needsDisplayOnBoundsChange = true
        l.contentsScale = window?.backingScaleFactor ?? 1.0
        l.isOpaque = true
        l.bounds = CGRect(origin: .zero, size: rect.size)
        l.position = convertFromTextContainer(rect.origin)

        return l
    }
}
