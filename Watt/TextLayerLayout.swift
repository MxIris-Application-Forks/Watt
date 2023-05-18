//
//  TextLayerLayout.swift
//  Watt
//
//  Created by David Albert on 5/17/23.
//

import Cocoa

class TextLayerLayout<ContentManager>: NSObject, CALayerDelegate, NSViewLayerContentScaleDelegate where ContentManager: TextContentManager {
    typealias LayoutFragment = LayoutManager<ContentManager>.LayoutFragment

    var renderer: LayoutFragmentRenderer<ContentManager> = LayoutFragmentRenderer()
    var layerCache: WeakDictionary<LayoutFragment.ID, CALayer> = WeakDictionary()

    weak var delegate: (any TextLayerLayoutDelegate<ContentManager>)?
    var layoutManager: LayoutManager<ContentManager>

    init(layoutManager: LayoutManager<ContentManager>) {
        self.layoutManager = layoutManager
    }

    // The layer being laid out
    var layer: CALayer?

    func layoutSublayers(of layer: CALayer) {
        self.layer = layer
        layoutManager.layoutViewport()
        self.layer = nil
    }

    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        NSNull()
    }

    func layer(_ layer: CALayer, shouldInheritContentsScale newScale: CGFloat, from window: NSWindow) -> Bool {
        true
    }
}

extension TextLayerLayout: LayoutManagerDelegate {
    func viewportBounds(for layoutManager: LayoutManager<ContentManager>) -> CGRect {
        guard let delegate else {
            return .zero
        }

        return delegate.viewportBounds(for: self)
    }

    func layoutManagerWillLayout(_ layoutManager: LayoutManager<ContentManager>) {
        guard let layer else {
            return
        }

        layer.sublayers = nil
        delegate?.textLayerLayoutWillLayout(self)
    }

    func layoutManager(_ layoutManager: LayoutManager<ContentManager>, configureRenderingSurfaceFor layoutFragment: LayoutManager<ContentManager>.LayoutFragment) {
        guard let layer else {
            return
        }

        let l = layerCache[layoutFragment.id] ?? makeLayer(for: layoutFragment)
        let inset = delegate?.textLayerLayout(self, insetFor: layoutFragment) ?? .zero
        l.anchorPoint = .zero
        l.bounds = layoutFragment.typographicBounds
        l.position = CGPoint(x: layoutFragment.position.x + inset.width, y: layoutFragment.position.y + inset.height)

        layerCache[layoutFragment.id] = l

        layer.addSublayer(l)

        delegate?.textLayerLayout(self, didLayout: layoutFragment)
    }

    func layoutManagerDidLayout(_ layoutManager: LayoutManager<ContentManager>) {
        delegate?.textLayerLayoutDidFinishLayout(self)
    }

    func makeLayer(for layoutFragment: LayoutFragment) -> CALayer {
        let l = CALayer()
        l.needsDisplayOnBoundsChange = true
        l.contentsScale = delegate?.backingScaleFactor(for: self) ?? 1.0
        l.delegate = renderer
        l.setValue(layoutFragment, forKey: CALayer.layoutFragmentKey)

        return l
    }
}