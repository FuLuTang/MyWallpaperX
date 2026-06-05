//
//  InspectorFadingScrollView.swift
//  MyWallpaperX
//

import AppKit
import QuartzCore

class InspectorFadingScrollView: NSScrollView {
    private let fadeMask = CAGradientLayer()
    private let fadeRatio: CGFloat

    init(fadeRatio: CGFloat = 0.035) {
        self.fadeRatio = fadeRatio
        super.init(frame: .zero)
        setupFadeMask()
    }

    override init(frame frameRect: NSRect) {
        self.fadeRatio = 0.035
        super.init(frame: frameRect)
        setupFadeMask()
    }

    required init?(coder: NSCoder) {
        self.fadeRatio = 0.035
        super.init(coder: coder)
        setupFadeMask()
    }

    override var documentView: NSView? {
        didSet {
            updateFadeMaskOnMain()
        }
    }

    override func layout() {
        super.layout()
        fadeMask.frame = bounds
        updateFadeMaskOnMain()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateFadeMaskOnMain()
    }

    private func setupFadeMask() {
        wantsLayer = true
        contentView.wantsLayer = true
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        fadeMask.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor
        ]
        layer?.mask = fadeMask
        updateFadeMaskOnMain()
    }

    private func updateFadeMaskOnMain() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateFadeMask()
            }
            return
        }
        updateFadeMask()
    }

    private func updateFadeMask() {
        fadeMask.locations = [
            0,
            NSNumber(value: Double(fadeRatio)),
            NSNumber(value: Double(1 - fadeRatio)),
            1
        ]
    }
}
