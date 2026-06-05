//
//  InspectorHost.swift
//  MyWallpaperX
//

import AppKit

let inspectorHostAnimationDuration: Double = 0.24

enum InspectorHostUserInfoKey {
    static let module = "module"
    static let cardID = "cardID"
    static let title = "title"
    static let subtitle = "subtitle"
    static let preferredWidth = "preferredWidth"
    static let focusPolicy = "focusPolicy"
    static let chromeStyle = "chromeStyle"
    static let hostedView = "hostedView"
}

enum InspectorHostFocusPolicy: String {
    /// 打开时不主动抢占 first responder，保持浏览上下文原焦点不变。
    case preserveCurrentResponder
    /// 模块可在 inspectorDidPresent 后自行把焦点切到 inspector 内部控件。
    case moduleManaged
}

enum InspectorHostChromeStyle: String {
    case standard
    case infoPanel
}

struct InspectorCardToken: Hashable, Identifiable {
    let module: ModuleIdentifier
    let cardID: String

    var id: String {
        "\(module.rawValue):\(cardID)"
    }
}

struct InspectorHostRequest: Equatable {
    static let defaultPreferredWidth: CGFloat = 360
    static let minimumPreferredWidth: CGFloat = 300
    static let maximumPreferredWidth: CGFloat = 460

    let token: InspectorCardToken
    let title: String
    let subtitle: String?
    let preferredWidth: CGFloat
    let focusPolicy: InspectorHostFocusPolicy
    let chromeStyle: InspectorHostChromeStyle

    init(
        token: InspectorCardToken,
        title: String,
        subtitle: String? = nil,
        preferredWidth: CGFloat = InspectorHostRequest.defaultPreferredWidth,
        focusPolicy: InspectorHostFocusPolicy = .preserveCurrentResponder,
        chromeStyle: InspectorHostChromeStyle = .standard
    ) {
        self.token = token
        self.title = title
        self.subtitle = subtitle
        self.preferredWidth = min(
            max(preferredWidth, Self.minimumPreferredWidth),
            Self.maximumPreferredWidth
        )
        self.focusPolicy = focusPolicy
        self.chromeStyle = chromeStyle
    }

    init?(userInfo: [AnyHashable: Any]?) {
        guard
            let moduleRawValue = userInfo?[InspectorHostUserInfoKey.module] as? String,
            let module = ModuleIdentifier(rawValue: moduleRawValue),
            let cardID = userInfo?[InspectorHostUserInfoKey.cardID] as? String,
            let title = userInfo?[InspectorHostUserInfoKey.title] as? String
        else {
            return nil
        }

        let subtitle = userInfo?[InspectorHostUserInfoKey.subtitle] as? String
        let preferredWidthNumber = userInfo?[InspectorHostUserInfoKey.preferredWidth] as? NSNumber
        let preferredWidth = preferredWidthNumber.map { CGFloat(truncating: $0) } ?? Self.defaultPreferredWidth
        let focusPolicyRawValue = userInfo?[InspectorHostUserInfoKey.focusPolicy] as? String
        let focusPolicy = focusPolicyRawValue.flatMap(InspectorHostFocusPolicy.init(rawValue:))
            ?? .preserveCurrentResponder
        let chromeStyleRawValue = userInfo?[InspectorHostUserInfoKey.chromeStyle] as? String
        let chromeStyle = chromeStyleRawValue.flatMap(InspectorHostChromeStyle.init(rawValue:))
            ?? .standard

        self.init(
            token: InspectorCardToken(module: module, cardID: cardID),
            title: title,
            subtitle: subtitle,
            preferredWidth: preferredWidth,
            focusPolicy: focusPolicy,
            chromeStyle: chromeStyle
        )
    }

    var userInfo: [String: Any] {
        var result: [String: Any] = [
            InspectorHostUserInfoKey.module: token.module.rawValue,
            InspectorHostUserInfoKey.cardID: token.cardID,
            InspectorHostUserInfoKey.title: title,
            InspectorHostUserInfoKey.preferredWidth: preferredWidth,
            InspectorHostUserInfoKey.focusPolicy: focusPolicy.rawValue,
            InspectorHostUserInfoKey.chromeStyle: chromeStyle.rawValue
        ]
        if let subtitle, !subtitle.isEmpty {
            result[InspectorHostUserInfoKey.subtitle] = subtitle
        }
        return result
    }
}

struct InspectorHostDismissRequest {
    let module: ModuleIdentifier?
    let cardID: String?

    init?(userInfo: [AnyHashable: Any]?) {
        guard let userInfo else {
            self.module = nil
            self.cardID = nil
            return
        }

        let moduleRawValue = userInfo[InspectorHostUserInfoKey.module] as? String
        let parsedModule = moduleRawValue.flatMap(ModuleIdentifier.init(rawValue:))
        let parsedCardID = userInfo[InspectorHostUserInfoKey.cardID] as? String
        guard parsedModule != nil || parsedCardID != nil else { return nil }

        module = parsedModule
        cardID = parsedCardID
    }

    func matches(_ token: InspectorCardToken) -> Bool {
        if let module, module != token.module {
            return false
        }
        if let cardID, cardID != token.cardID {
            return false
        }
        return true
    }
}

struct InspectorHostMountRequest {
    let token: InspectorCardToken
    let hostedView: NSView

    init?(userInfo: [AnyHashable: Any]?) {
        guard
            let moduleRawValue = userInfo?[InspectorHostUserInfoKey.module] as? String,
            let module = ModuleIdentifier(rawValue: moduleRawValue),
            let cardID = userInfo?[InspectorHostUserInfoKey.cardID] as? String,
            let hostedView = userInfo?[InspectorHostUserInfoKey.hostedView] as? NSView
        else {
            return nil
        }

        token = InspectorCardToken(module: module, cardID: cardID)
        self.hostedView = hostedView
    }
}

@MainActor
final class InspectorHostStore {
    private(set) var currentRequest: InspectorHostRequest?
    private(set) var hostedContentView: NSView?
    var onChange: (() -> Void)?

    var isPresented: Bool {
        currentRequest != nil
    }

    func present(_ request: InspectorHostRequest) {
        if currentRequest?.token != request.token {
            hostedContentView = nil
        }
        currentRequest = request
        onChange?()
    }

    func mountContent(_ request: InspectorHostMountRequest) {
        guard currentRequest?.token == request.token else { return }
        hostedContentView = request.hostedView
        onChange?()
    }

    func unmountContent(for token: InspectorCardToken? = nil) {
        guard token == nil || currentRequest?.token == token else { return }
        hostedContentView = nil
        onChange?()
    }

    func dismiss() {
        hostedContentView = nil
        currentRequest = nil
        onChange?()
    }

    func finalizeDismiss() {
        hostedContentView = nil
        currentRequest = nil
        onChange?()
    }
}

final class InspectorHostViewController: NSViewController {
    private let store: InspectorHostStore
    private let cardView = InspectorHostCardView()
    private var cardWidthConstraint: NSLayoutConstraint?
    private var cardHeightConstraint: NSLayoutConstraint?

    init(store: InspectorHostStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        store.onChange = { [weak self] in
            self?.applyStoreState()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = InspectorHostRootView(cardView: cardView)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        let widthConstraint = cardView.widthAnchor.constraint(
            equalToConstant: InspectorHostRequest.defaultPreferredWidth
        )
        cardWidthConstraint = widthConstraint
        let safeArea = view.safeAreaLayoutGuide
        let heightConstraint = cardView.heightAnchor.constraint(equalTo: safeArea.heightAnchor, constant: -36)
        heightConstraint.priority = .defaultHigh
        cardHeightConstraint = heightConstraint

        let centerYConstraint = cardView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor)
        centerYConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor, constant: -18),
            centerYConstraint,
            heightConstraint,
            widthConstraint
        ])

        applyStoreState()
    }

    private func applyStoreState() {
        guard isViewLoaded else { return }
        guard let request = store.currentRequest else {
            cardView.isHidden = true
            cardView.configure(request: nil, hostedContentView: nil)
            return
        }

        cardWidthConstraint?.constant = request.preferredWidth
        cardHeightConstraint?.constant = -36
        cardView.isHidden = false
        cardView.configure(request: request, hostedContentView: store.hostedContentView)
    }
}

private final class InspectorHostRootView: NSView {
    private weak var cardView: NSView?

    init(cardView: NSView) {
        self.cardView = cardView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        if let cardView {
            let point = convert(event.locationInWindow, from: nil)
            if cardView.frame.contains(point) {
                super.mouseDown(with: event)
                return
            }
        }
        NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
    }
}

private final class InspectorHostCardView: NSView {
    private let glassView = NSGlassEffectView()
    private let panelOverlayView = NSView()
    private let stackView = NSStackView()
    private let headerRow = NSStackView()
    private let titleContainer = NSStackView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let contentContainer = InspectorHostedContentContainerView()
    private let progressIndicator = NSProgressIndicator()
    private var request: InspectorHostRequest?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(request: InspectorHostRequest?, hostedContentView: NSView?) {
        self.request = request
        guard let request else {
            contentContainer.hostedContentView = nil
            progressIndicator.stopAnimation(nil)
            return
        }

        titleLabel.stringValue = request.chromeStyle == .infoPanel ? "详情" : request.title
        subtitleLabel.stringValue = request.chromeStyle == .infoPanel ? "" : (request.subtitle ?? "")
        subtitleLabel.isHidden = subtitleLabel.stringValue.isEmpty
        iconView.isHidden = request.chromeStyle != .infoPanel

        let closeSymbolName = request.chromeStyle == .infoPanel ? "xmark" : "xmark.circle.fill"
        closeButton.image = NSImage(systemSymbolName: closeSymbolName, accessibilityDescription: "关闭详情")
        closeButton.toolTip = "关闭详情"

        contentContainer.hostedContentView = hostedContentView
        progressIndicator.isHidden = hostedContentView != nil
        hostedContentView == nil ? progressIndicator.startAnimation(nil) : progressIndicator.stopAnimation(nil)
        refreshAppearance()
    }

    func refreshAppearance() {
        guard isViewLoadedInWindow || window != nil || superview != nil else { return }
        let isDark = InspectorGlassPalette.isDarkMode(for: self)

        glassView.cornerRadius = 22
        glassView.style = .regular
        glassView.tintColor = InspectorGlassPalette.baseTint(isDark: isDark)
        glassView.layer?.backgroundColor = InspectorGlassPalette.innerFill(isDark: isDark).cgColor

        panelOverlayView.layer?.cornerRadius = 22
        panelOverlayView.layer?.masksToBounds = true
        panelOverlayView.layer?.backgroundColor = InspectorGlassPalette.panelFill(isDark: isDark).cgColor
        panelOverlayView.layer?.borderColor = InspectorGlassPalette.panelStroke(isDark: isDark).cgColor
        panelOverlayView.layer?.borderWidth = 1

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isDark ? 0.40 : 0.12
        layer?.shadowRadius = 25
        layer?.shadowOffset = CGSize(width: 0, height: -16)

        titleLabel.textColor = .labelColor
        subtitleLabel.textColor = .secondaryLabelColor
        iconView.contentTintColor = .labelColor

        let infoPanel = request?.chromeStyle == .infoPanel
        closeButton.contentTintColor = .labelColor
        closeButton.layer?.backgroundColor = infoPanel
            ? (isDark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.05)).cgColor
            : NSColor.clear.cgColor
        closeButton.layer?.borderColor = infoPanel
            ? (isDark ? NSColor.white.withAlphaComponent(0.20) : NSColor.black.withAlphaComponent(0.07)).cgColor
            : NSColor.clear.cgColor
        closeButton.layer?.borderWidth = infoPanel ? 0.5 : 0
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private var isViewLoadedInWindow: Bool {
        window != nil
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.masksToBounds = false

        setupGlass()
        setupPanelOverlay()
        setupHeader()
        setupContent()
        refreshAppearance()
    }

    private func setupGlass() {
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.wantsLayer = true
        addSubview(glassView)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupPanelOverlay() {
        panelOverlayView.translatesAutoresizingMaskIntoConstraints = false
        panelOverlayView.wantsLayer = true
        addSubview(panelOverlayView)

        NSLayoutConstraint.activate([
            panelOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            panelOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            panelOverlayView.topAnchor.constraint(equalTo: topAnchor),
            panelOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupHeader() {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14
        stackView.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 12
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "详情")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.lineBreakMode = .byTruncatingTail

        titleContainer.orientation = .vertical
        titleContainer.alignment = .leading
        titleContainer.spacing = 4
        titleContainer.addArrangedSubview(titleLabel)
        titleContainer.addArrangedSubview(subtitleLabel)

        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.target = self
        closeButton.action = #selector(closeInspector)
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 10
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        headerRow.addArrangedSubview(iconView)
        headerRow.addArrangedSubview(titleContainer)
        headerRow.addArrangedSubview(spacer)
        headerRow.addArrangedSubview(closeButton)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stackView.addArrangedSubview(headerRow)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            headerRow.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -36)
        ])
    }

    private func setupContent() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        let contentHost = NSView()
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(contentContainer)
        contentHost.addSubview(progressIndicator)
        stackView.addArrangedSubview(contentHost)

        NSLayoutConstraint.activate([
            contentHost.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -36),
            contentContainer.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: contentHost.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            progressIndicator.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: contentHost.topAnchor, constant: 4),
            contentHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
    }

    @objc private func closeInspector() {
        guard let request else { return }
        InspectorHostActions.postClose(module: request.token.module, cardID: request.token.cardID)
    }
}

private enum InspectorGlassPalette {
    static func isDarkMode(for view: NSView) -> Bool {
        return view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func baseTint(isDark: Bool) -> NSColor {
        if isDark {
            return .windowBackgroundColor.withAlphaComponent(0.18)
        }
        return .controlBackgroundColor.withAlphaComponent(0.15)
    }

    static func innerFill(isDark: Bool) -> NSColor {
        if isDark {
            return .textBackgroundColor.withAlphaComponent(0.06)
        }
        return .windowBackgroundColor.withAlphaComponent(0.05)
    }

    static func panelFill(isDark: Bool) -> NSColor {
        if isDark {
            return .black.withAlphaComponent(0.10)
        }
        return .white.withAlphaComponent(0.82)
    }

    static func panelStroke(isDark: Bool) -> NSColor {
        if isDark {
            return .white.withAlphaComponent(0.30)
        }
        return .white.withAlphaComponent(0.74)
    }
}

private final class InspectorHostedContentContainerView: NSView {
    var hostedContentView: NSView? {
        didSet {
            guard hostedContentView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            guard let hostedContentView else { return }
            hostedContentView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hostedContentView)
            NSLayoutConstraint.activate([
                hostedContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostedContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostedContentView.topAnchor.constraint(equalTo: topAnchor),
                hostedContentView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
}
