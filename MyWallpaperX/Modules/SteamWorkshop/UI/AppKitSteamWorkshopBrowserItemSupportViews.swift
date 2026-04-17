import AppKit
import QuartzCore

final class SteamWorkshopOverlayIconButton: NSButton {
    var normalBackgroundColor: NSColor = .clear {
        didSet { updateAppearance() }
    }
    var hoverBackgroundColor: NSColor = NSColor.white.withAlphaComponent(0.12) {
        didSet { updateAppearance() }
    }
    var pressedBackgroundColor: NSColor = NSColor.white.withAlphaComponent(0.18) {
        didSet { updateAppearance() }
    }
    var iconTintColor: NSColor = .labelColor {
        didSet { contentTintColor = iconTintColor }
    }
    var cornerRadius: CGFloat = 12 {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var borderColor: NSColor = .clear {
        didSet { layer?.borderColor = borderColor.cgColor }
    }
    var borderWidth: CGFloat = 0 {
        didSet { layer?.borderWidth = borderWidth }
    }

    private var isHovering = false {
        didSet { updateAppearance() }
    }
    private var isPressing = false {
        didSet { updateAppearance() }
    }
    private var trackingAreaRef: NSTrackingArea?

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        isPressing = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }
        isPressing = true
        super.mouseDown(with: event)
        isPressing = false
    }

    private func commonInit() {
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        layer?.borderColor = borderColor.cgColor
        layer?.borderWidth = borderWidth
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = iconTintColor
        updateAppearance()
    }

    private func updateAppearance() {
        let background: NSColor
        if !isEnabled {
            background = .clear
        } else if isPressing {
            background = pressedBackgroundColor
        } else if isHovering {
            background = hoverBackgroundColor
        } else {
            background = normalBackgroundColor
        }
        layer?.backgroundColor = background.cgColor
        contentTintColor = isEnabled ? iconTintColor : .disabledControlTextColor
        alphaValue = isEnabled ? 1 : 0.45
    }
}

final class SteamWorkshopMarqueeTextView: NSView {
    private let clippingView = NSView()
    private let containerLayer = CALayer()
    private let leadingTextLayer = CATextLayer()
    private let trailingTextLayer = CATextLayer()
    private let fadeMaskLayer = CAGradientLayer()
    private var displayText = ""
    private var marqueeSegmentWidth: CGFloat = 0
    private var isActive = false
    private var isPerformingLayout = false
    private let repeatedGap = "     "

    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            updateDisplayedText()
        }
    }

    var font: NSFont = .systemFont(ofSize: 13, weight: .semibold) {
        didSet {
            updateTextLayerAppearance()
            updateDisplayedText()
        }
    }

    var textColor: NSColor = .labelColor {
        didSet {
            updateTextLayerAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func layout() {
        super.layout()
        isPerformingLayout = true
        defer { isPerformingLayout = false }
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            clippingView.frame = .zero
            containerLayer.frame = .zero
            containerLayer.removeAnimation(forKey: "steam.marquee")
            return
        }
        clippingView.frame = bounds
        updateFadeMask()
        layoutTextLayers()
        updateAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    func setActive(_ active: Bool) {
        if isActive == active {
            if active {
                updateAnimation()
            }
            return
        }
        isActive = active
        updateAnimation()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.mask = fadeMaskLayer

        clippingView.wantsLayer = true
        clippingView.layer?.backgroundColor = NSColor.clear.cgColor
        clippingView.layer?.masksToBounds = true
        addSubview(clippingView)

        clippingView.layer?.addSublayer(containerLayer)
        [leadingTextLayer, trailingTextLayer].forEach { layer in
            layer.alignmentMode = .left
            layer.isWrapped = false
            layer.truncationMode = .none
            layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            containerLayer.addSublayer(layer)
        }
        updateTextLayerAppearance()
    }

    private func updateDisplayedText() {
        displayText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        marqueeSegmentWidth = 0
        leadingTextLayer.string = displayText
        trailingTextLayer.string = displayText
        if !isPerformingLayout {
            needsLayout = true
        }
    }

    private func updateTextLayerAppearance() {
        let cgColor = textColor.cgColor
        let fontRef = font as CTFont
        [leadingTextLayer, trailingTextLayer].forEach { layer in
            layer.font = fontRef
            layer.fontSize = font.pointSize
            layer.foregroundColor = cgColor
        }
    }

    private func layoutTextLayers() {
        let height = max(0, bounds.height.isFinite ? bounds.height : 0)
        let textHeight = ceil(font.pointSize + 4)
        let y = floor((height - textHeight) * 0.5)
        let baseWidth = measuredWidth(for: displayText)
        if shouldScroll(baseWidth: baseWidth) {
            marqueeSegmentWidth = baseWidth + measuredWidth(for: repeatedGap)
            containerLayer.frame = CGRect(x: 0, y: y.isFinite ? y : 0, width: max(0, marqueeSegmentWidth + baseWidth), height: textHeight)
            leadingTextLayer.isHidden = false
            trailingTextLayer.isHidden = false
            leadingTextLayer.frame = CGRect(x: 0, y: 0, width: max(0, baseWidth), height: textHeight)
            trailingTextLayer.frame = CGRect(x: marqueeSegmentWidth, y: 0, width: max(0, baseWidth), height: textHeight)
        } else {
            marqueeSegmentWidth = 0
            let centeredX = floor((bounds.width - baseWidth) * 0.5)
            containerLayer.frame = CGRect(x: centeredX.isFinite ? centeredX : 0, y: y.isFinite ? y : 0, width: max(0, baseWidth), height: textHeight)
            leadingTextLayer.isHidden = false
            trailingTextLayer.isHidden = true
            leadingTextLayer.frame = CGRect(x: 0, y: 0, width: max(0, baseWidth), height: textHeight)
            trailingTextLayer.frame = .zero
        }
    }

    private func updateFadeMask() {
        fadeMaskLayer.frame = bounds
        fadeMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMaskLayer.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fadeMaskLayer.locations = [0, 0.09, 0.91, 1]
    }

    private func updateAnimation() {
        containerLayer.removeAnimation(forKey: "steam.marquee")
        guard !displayText.isEmpty else { return }
        guard bounds.width.isFinite, bounds.height.isFinite else { return }

        let baseWidth = measuredWidth(for: displayText)
        guard shouldScroll(baseWidth: baseWidth), isActive else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            containerLayer.transform = CATransform3DIdentity
            CATransaction.commit()
            return
        }

        let travel = marqueeSegmentWidth > 0 ? marqueeSegmentWidth : (baseWidth + measuredWidth(for: repeatedGap))
        guard travel.isFinite, travel > 8 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.transform = CATransform3DIdentity
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -travel
        animation.duration = max(7, Double(travel / 22))
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        containerLayer.add(animation, forKey: "steam.marquee")
    }

    private func shouldScroll(baseWidth: CGFloat) -> Bool {
        guard baseWidth.isFinite, bounds.width.isFinite else { return false }
        return baseWidth > max(24, bounds.width - 8)
    }

    private func measuredWidth(for text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        guard measured.isFinite else { return 0 }
        return ceil(measured)
    }
}

final class SteamWorkshopGlassBarView: NSGlassEffectView {
    enum AccentStyle {
        case neutral
        case downloading
        case queued
        case ready
    }

    private let glossLayer = CAGradientLayer()
    private let accentLayer = CAGradientLayer()
    private let scanLayer = CAGradientLayer()
    private var accentStyle: AccentStyle = .neutral
    private var showsScanAnimation = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.clear.cgColor
        accentLayer.startPoint = CGPoint(x: 0, y: 0.5)
        accentLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(accentLayer)
        glossLayer.colors = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.white.withAlphaComponent(0.04).cgColor,
            NSColor.clear.cgColor
        ]
        glossLayer.locations = [0.0, 0.12, 0.46]
        glossLayer.startPoint = CGPoint(x: 0.18, y: 0.98)
        glossLayer.endPoint = CGPoint(x: 0.82, y: 0.08)
        layer?.addSublayer(glossLayer)
        scanLayer.startPoint = CGPoint(x: 0, y: 0.5)
        scanLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(scanLayer)
        updateMaterial()
    }

    override func layout() {
        super.layout()
        accentLayer.frame = bounds
        glossLayer.frame = bounds
        scanLayer.frame = CGRect(x: -bounds.width * 0.62, y: 0, width: bounds.width * 0.62, height: bounds.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
    }

    private func updateMaterial() {
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accentBaseColor: NSColor = {
            switch accentStyle {
            case .neutral:
                return isDarkMode ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.10)
            case .downloading:
                return NSColor.systemGreen
            case .queued:
                return NSColor.systemBlue
            case .ready:
                return isDarkMode ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.10)
            }
        }()
        let usesSolidStatusFill = accentStyle == .downloading || accentStyle == .queued

        style = usesSolidStatusFill ? .regular : .regular
        tintColor = {
            if usesSolidStatusFill {
                return accentBaseColor.withAlphaComponent(0.80)
            }
            return isDarkMode
                ? NSColor(calibratedWhite: 0.10, alpha: accentStyle == .neutral ? 0.82 : 0.66)
                : NSColor(calibratedWhite: 1.0, alpha: accentStyle == .neutral ? 0.72 : 0.58)
        }()

        layer?.backgroundColor = (usesSolidStatusFill
            ? accentBaseColor.withAlphaComponent(0.80)
            : NSColor.clear
        ).cgColor
        layer?.borderColor = (usesSolidStatusFill
            ? NSColor.white.withAlphaComponent(isDarkMode ? 0.18 : 0.14)
            : accentBaseColor.withAlphaComponent(isDarkMode ? 0.34 : 0.22)
        ).cgColor

        accentLayer.colors = usesSolidStatusFill
            ? [
                accentBaseColor.withAlphaComponent(0.84).cgColor,
                accentBaseColor.withAlphaComponent(0.80).cgColor,
                accentBaseColor.withAlphaComponent(0.84).cgColor
            ]
            : [
                accentBaseColor.withAlphaComponent(isDarkMode ? 0.34 : 0.22).cgColor,
                accentBaseColor.withAlphaComponent(isDarkMode ? 0.18 : 0.10).cgColor,
                NSColor.clear.cgColor
            ]
        accentLayer.locations = usesSolidStatusFill ? [0, 0.5, 1] : [0, 0.55, 1]

        glossLayer.isHidden = usesSolidStatusFill
        scanLayer.colors = usesSolidStatusFill
            ? [
                NSColor.clear.cgColor,
                NSColor.white.withAlphaComponent(isDarkMode ? 0.08 : 0.10).cgColor,
                NSColor.white.withAlphaComponent(isDarkMode ? 0.34 : 0.30).cgColor,
                NSColor.white.withAlphaComponent(isDarkMode ? 0.08 : 0.10).cgColor,
                NSColor.clear.cgColor
            ]
            : [
                NSColor.clear.cgColor,
                accentBaseColor.withAlphaComponent(isDarkMode ? 0.20 : 0.16).cgColor,
                NSColor.white.withAlphaComponent(isDarkMode ? 0.18 : 0.16).cgColor,
                accentBaseColor.withAlphaComponent(isDarkMode ? 0.16 : 0.12).cgColor,
                NSColor.clear.cgColor
            ]
        scanLayer.locations = [0, 0.22, 0.5, 0.78, 1]
        updateScanAnimation()
    }

    func applyAccentStyle(_ style: AccentStyle, animated: Bool) {
        accentStyle = style
        updateMaterial()
    }

    func setScanAnimationEnabled(_ enabled: Bool) {
        showsScanAnimation = enabled
        updateScanAnimation()
    }

    private func updateScanAnimation() {
        scanLayer.removeAnimation(forKey: "steam.bar.scan")
        scanLayer.isHidden = !showsScanAnimation
        guard showsScanAnimation, bounds.width > 0 else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -bounds.width * 1.18
        animation.toValue = bounds.width * 2.18
        animation.duration = 1.75
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        scanLayer.add(animation, forKey: "steam.bar.scan")
    }
}
