//
//  InspectorFadingScrollView.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

class InspectorFadingScrollView: NSScrollView {
    private let fadeMask = CAGradientLayer()
    private let fadeRatio: CGFloat
    private var boundsObserver: NSObjectProtocol?

    init(fadeRatio: CGFloat = 0.025) {
        self.fadeRatio = fadeRatio
        super.init(frame: .zero)
        setupFadeMask()
    }

    override init(frame frameRect: NSRect) {
        self.fadeRatio = 0.025
        super.init(frame: frameRect)
        setupFadeMask()
    }

    required init?(coder: NSCoder) {
        self.fadeRatio = 0.025
        super.init(coder: coder)
        setupFadeMask()
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override var documentView: NSView? {
        didSet {
            updateFadeMask()
        }
    }

    override func layout() {
        super.layout()
        fadeMask.frame = bounds
        updateFadeMask()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateFadeMask()
    }

    private func setupFadeMask() {
        wantsLayer = true
        contentView.wantsLayer = true
        contentView.postsBoundsChangedNotifications = true
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.mask = fadeMask
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateFadeMask()
        }
        updateFadeMask()
    }

    private func updateFadeMask() {
        let shouldFadeTop = canScrollTowardTop()
        let shouldFadeBottom = canScrollTowardBottom()
        let lowerOpaqueLocation: NSNumber = shouldFadeBottom ? NSNumber(value: Double(fadeRatio)) : 0
        let upperOpaqueLocation: NSNumber = shouldFadeTop ? NSNumber(value: Double(1 - fadeRatio)) : 1
        fadeMask.colors = [
            (shouldFadeBottom ? NSColor.clear : NSColor.black).cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            (shouldFadeTop ? NSColor.clear : NSColor.black).cgColor
        ]
        fadeMask.locations = [0, lowerOpaqueLocation, upperOpaqueLocation, 1]
    }

    private func canScrollTowardTop() -> Bool {
        guard let documentView else { return false }
        let visible = contentView.bounds
        let documentBounds = documentView.bounds
        guard documentBounds.height > visible.height + 1 else { return false }
        if documentView.isFlipped {
            return visible.minY > documentBounds.minY + 1
        }
        return visible.maxY < documentBounds.maxY - 1
    }

    private func canScrollTowardBottom() -> Bool {
        guard let documentView else { return false }
        let visible = contentView.bounds
        let documentBounds = documentView.bounds
        guard documentBounds.height > visible.height + 1 else { return false }
        if documentView.isFlipped {
            return visible.maxY < documentBounds.maxY - 1
        }
        return visible.minY > documentBounds.minY + 1
    }
}
