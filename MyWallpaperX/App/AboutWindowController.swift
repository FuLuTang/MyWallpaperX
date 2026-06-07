//
//  AboutWindowController.swift
//  MyWallpaperX
//

import AppKit

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private static let repositoryURL = URL(string: "https://github.com/songziqiang9512/MyWallpaperX")!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 MyWallpaperX"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = AboutContentView(target: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openGitHub(_ sender: Any?) {
        NSWorkspace.shared.open(Self.repositoryURL)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        AppUpdateController.shared.checkForUpdates(sender)
    }
}

private final class AboutContentView: NSView {
    private let appName = "MyWallpaperX"
    private weak var target: AboutWindowController?

    init(target: AboutWindowController) {
        self.target = target
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildInterface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func buildInterface() {
        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: appName)
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.alignment = .center

        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        let descriptionLabel = wrappingLabel(
            "原生 macOS 壁纸应用，支持本地视频、图片、Web 壁纸和 Steam 创意工坊内容。"
        )
        descriptionLabel.alignment = .center

        let starLabel = wrappingLabel(
            "如果 MyWallpaperX 对你有帮助，欢迎在 GitHub 点一个 Star。"
        )
        starLabel.font = .systemFont(ofSize: 12)
        starLabel.textColor = .secondaryLabelColor
        starLabel.alignment = .center

        let githubButton = NSButton(
            title: "GitHub 项目",
            target: target,
            action: #selector(AboutWindowController.openGitHub(_:))
        )
        githubButton.bezelStyle = .rounded
        githubButton.controlSize = .large
        if let image = NSImage(systemSymbolName: "link", accessibilityDescription: "GitHub 项目") {
            image.isTemplate = true
            githubButton.image = image
            githubButton.imagePosition = .imageLeading
        }

        let updateButton = NSButton(
            title: "检查更新",
            target: target,
            action: #selector(AboutWindowController.checkForUpdates(_:))
        )
        updateButton.bezelStyle = .rounded
        updateButton.controlSize = .large
        if let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "检查更新") {
            image.isTemplate = true
            updateButton.image = image
            updateButton.imagePosition = .imageLeading
        }

        let buttonStack = NSStackView(views: [githubButton, updateButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 10
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [
            iconView,
            titleLabel,
            versionLabel,
            descriptionLabel,
            buttonStack,
            starLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .gravityAreas
        stack.spacing = 10
        stack.setCustomSpacing(16, after: versionLabel)
        stack.setCustomSpacing(18, after: descriptionLabel)
        stack.setCustomSpacing(14, after: buttonStack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -34),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 78),
            iconView.heightAnchor.constraint(equalToConstant: 78),
            buttonStack.widthAnchor.constraint(equalToConstant: 250)
        ])
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "0"
        let buildVersion = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(shortVersion) (\(buildVersion))"
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
