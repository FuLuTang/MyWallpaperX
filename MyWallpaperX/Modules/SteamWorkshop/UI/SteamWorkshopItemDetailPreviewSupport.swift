import SwiftUI
import AppKit

struct SteamWorkshopPreviewSurface: View {
    let itemID: String
    let previewImageURL: URL?
    let fallbackVideoURL: URL?
    let previewAssetKind: SteamWorkshopPreviewAssetKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color(red: 0.84, green: 0.91, blue: 1.0).opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let previewImageURL {
                SteamWorkshopCachedPreviewImage(
                    itemID: itemID,
                    url: previewImageURL,
                    fallbackVideoURL: fallbackVideoURL,
                    refreshToken: SteamWorkshopService.shared.previewReloadToken
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if let fallbackVideoURL {
                SteamWorkshopCachedPreviewImage(
                    itemID: itemID,
                    url: fallbackVideoURL,
                    fallbackVideoURL: fallbackVideoURL,
                    refreshToken: SteamWorkshopService.shared.previewReloadToken
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            LinearGradient(
                colors: [.clear, .white.opacity(0.02)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .clipped()
    }
}

private struct SteamWorkshopCachedPreviewImage: NSViewRepresentable {
    let itemID: String
    let url: URL
    let fallbackVideoURL: URL?
    let refreshToken: Int

    func makeNSView(context: Context) -> SteamWorkshopPreviewImageContainerView {
        SteamWorkshopPreviewImageContainerView()
    }

    func updateNSView(_ nsView: SteamWorkshopPreviewImageContainerView, context: Context) {
        guard context.coordinator.currentURL != url || context.coordinator.refreshToken != refreshToken else { return }
        context.coordinator.currentURL = url
        context.coordinator.refreshToken = refreshToken

        if url.isFileURL {
            if FileManager.default.fileExists(atPath: url.path),
               let image = NSImage(contentsOf: url),
               !steamWorkshopPreviewImageLooksSuspicious(image) {
                nsView.setImage(image)
                return
            }

            if let fallbackVideoURL {
                nsView.setLoadingState(.loading)
                SteamWorkshopDownloadThumbnailPipeline.shared.generateThumbnail(for: fallbackVideoURL) { image in
                    guard context.coordinator.currentURL == url else { return }
                    if let image {
                        nsView.setImage(image)
                    } else {
                        nsView.setLoadingState(.unavailable)
                    }
                }
                return
            }

            nsView.setLoadingState(.unavailable)
            return
        }

        let cacheKey = steamWorkshopPreviewCacheKey(for: url)
        if let cached = SteamWorkshopPreviewImageCache.shared.cachedOrDiskImage(forKey: cacheKey) {
            nsView.setImage(cached)
            return
        }

        nsView.setLoadingState(.loading)
        SteamWorkshopPreviewImageCache.shared.loadImageDataAsync(forKey: cacheKey, loader: {
            await SteamWorkshopPreviewRequestCoordinator.shared.loadData(
                from: url,
                priority: .userInitiated
            )
        }) { image in
            guard context.coordinator.currentURL == url else { return }
            if let image, !steamWorkshopPreviewImageLooksSuspicious(image) {
                nsView.setImage(image)
            } else {
                if image != nil {
                    SteamWorkshopPreviewRequestCoordinator.shared.markCachedImageSuspicious(forKey: cacheKey)
                }
                nsView.setLoadingState(.unavailable)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var currentURL: URL?
        var refreshToken: Int = -1
    }
}

private final class SteamWorkshopPreviewImageContainerView: NSView {
    private let imageView = NSImageView()
    private let placeholderView = SteamWorkshopPreviewPlaceholderView()

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
        layer?.backgroundColor = NSColor.clear.cgColor
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)
        addSubview(placeholderView)
    }

    override func layout() {
        super.layout()
        updateImageFrame()
    }

    func setImage(_ image: NSImage?) {
        imageView.image = image
        placeholderView.setState(image == nil ? .unavailable : .hidden)
        updateImageFrame()
    }

    func setLoadingState(_ state: SteamWorkshopPreviewPlaceholderView.State) {
        placeholderView.setState(state)
    }

    private func updateImageFrame() {
        let containerBounds = bounds
        guard containerBounds.width > 0, containerBounds.height > 0 else {
            imageView.frame = .zero
            placeholderView.frame = .zero
            return
        }
        placeholderView.frame = containerBounds
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else {
            imageView.frame = containerBounds
            return
        }

        let widthScale = containerBounds.width / image.size.width
        let heightScale = containerBounds.height / image.size.height
        let scale = max(widthScale, heightScale)
        let fittedWidth = image.size.width * scale
        let fittedHeight = image.size.height * scale
        imageView.frame = CGRect(
            x: floor((containerBounds.width - fittedWidth) * 0.5),
            y: floor((containerBounds.height - fittedHeight) * 0.5),
            width: ceil(fittedWidth),
            height: ceil(fittedHeight)
        )
    }
}
