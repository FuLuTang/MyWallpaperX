//
//  InspectorFooterMetrics.swift
//  MyWallpaperX
//

import CoreGraphics
import AppKit

enum InspectorFooterMetrics {
    static let height: CGFloat = 38
    static let iconWidth: CGFloat = height
    static let textMinWidth: CGFloat = 96
}

enum InspectorFooterButtonKind {
    case primary
    case secondary
    case danger
}

final class InspectorFooterButton: NSButton {
    private let kind: InspectorFooterButtonKind
    private let rawTitle: String
    private let rawImage: NSImage?
    private let contentStack = NSStackView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isVisuallyEnabled = true

    init(
        title: String,
        image: NSImage?,
        kind: InspectorFooterButtonKind = .secondary,
        target: AnyObject?,
        action: Selector
    ) {
        self.kind = kind
        self.rawTitle = title
        self.rawImage = image
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isHighlighted: Bool {
        didSet { updateStyle() }
    }

    override var isEnabled: Bool {
        get { isVisuallyEnabled }
        set {
            isVisuallyEnabled = newValue
            super.isEnabled = true
            updateStyle()
        }
    }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(
            width: rawTitle.isEmpty ? InspectorFooterMetrics.iconWidth : max(base.width, InspectorFooterMetrics.textMinWidth),
            height: InspectorFooterMetrics.height
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyle()
    }

    private func setup() {
        title = ""
        image = nil
        isBordered = false
        bezelStyle = .regularSquare
        controlSize = .large
        focusRingType = .none
        imagePosition = rawTitle.isEmpty ? .imageOnly : .imageLeading
        imageScaling = .scaleProportionallyDown
        imageHugsTitle = true
        font = .systemFont(ofSize: 13, weight: .semibold)
        alignment = .center
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.7
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        setupContentViews()
        updateStyle()
    }

    private func setupContentViews() {
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = rawTitle.isEmpty ? 0 : 7
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = rawImage
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(iconView)

        if rawTitle.isEmpty {
            titleLabel.isHidden = true
        } else {
            titleLabel.stringValue = rawTitle
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.alignment = .center
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            contentStack.addArrangedSubview(titleLabel)
        }

        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: rawTitle.isEmpty ? 0 : 12),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: rawTitle.isEmpty ? 0 : -12),
            iconView.widthAnchor.constraint(equalToConstant: rawTitle.isEmpty ? 18 : 16),
            iconView.heightAnchor.constraint(equalToConstant: rawTitle.isEmpty ? 18 : 16)
        ])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isVisuallyEnabled ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isVisuallyEnabled else { return }
        super.mouseDown(with: event)
    }

    private func updateStyle() {
        let enabledAlpha: CGFloat = isVisuallyEnabled ? 1 : 0.45
        let pressedFactor: CGFloat = isHighlighted ? 0.88 : 1
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill: NSColor
        let text: NSColor
        let border: NSColor

        switch kind {
        case .primary:
            fill = NSColor.systemBlue.withAlphaComponent((isDarkMode ? 0.95 : 0.88) * enabledAlpha * pressedFactor)
            text = .white.withAlphaComponent(enabledAlpha)
            border = NSColor.systemBlue.withAlphaComponent(0.42 * enabledAlpha)
        case .secondary:
            fill = isDarkMode
                ? NSColor.black.withAlphaComponent(0.26 * enabledAlpha * pressedFactor)
                : NSColor.black.withAlphaComponent(0.06 * enabledAlpha * pressedFactor)
            text = NSColor.labelColor.withAlphaComponent(enabledAlpha)
            border = (isDarkMode ? NSColor.white : NSColor.black)
                .withAlphaComponent((isDarkMode ? 0.16 : 0.08) * enabledAlpha)
        case .danger:
            fill = NSColor.systemRed.withAlphaComponent((isDarkMode ? 0.74 : 0.66) * enabledAlpha * pressedFactor)
            text = .white.withAlphaComponent(enabledAlpha)
            border = NSColor.systemRed.withAlphaComponent(0.26 * enabledAlpha)
        }

        contentTintColor = text
        iconView.contentTintColor = text
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: rawTitle.isEmpty ? 17 : 14,
            weight: .semibold
        )
        titleLabel.textColor = text
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = border.cgColor
    }
}
