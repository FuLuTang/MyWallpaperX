import AppKit
import CoreGraphics
import ImageIO

enum SteamWorkshopPreviewImageCache {
    static let shared = ThumbnailCache(
        label: "com.songziqiang.MyWallpaperX.steamworkshop.preview.decode",
        countLimit: 320
    )
}

func steamWorkshopPreviewCacheKey(for url: URL) -> String {
    let host = (url.host ?? "").lowercased()
    let normalizedPath: String = {
        let path = url.path.isEmpty ? "/" : url.path
        if path.count > 1, path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }()

    if host.hasSuffix("steamusercontent.com"),
       normalizedPath.contains("/ugc/") {
        return "steam-preview:\(host)\(normalizedPath)"
    }

    return "steam-preview:\(url.absoluteString)"
}

func steamWorkshopPreviewImageLooksSuspicious(_ image: NSImage) -> Bool {
    guard image.size.width > 0, image.size.height > 0 else { return true }
    if image.size.width <= 4 || image.size.height <= 4 {
        return true
    }
    if steamWorkshopPreviewImageIsAnimated(image) {
        return false
    }
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return false
    }

    let sampleWidth = 8
    let sampleHeight = 8
    var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
    guard let context = CGContext(
        data: &pixels,
        width: sampleWidth,
        height: sampleHeight,
        bitsPerComponent: 8,
        bytesPerRow: sampleWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return false
    }

    context.interpolationQuality = .low
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

    var luminances: [CGFloat] = []
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = CGFloat(pixels[index + 3]) / 255.0
        guard alpha > 0.05 else { continue }
        let red = CGFloat(pixels[index]) / 255.0
        let green = CGFloat(pixels[index + 1]) / 255.0
        let blue = CGFloat(pixels[index + 2]) / 255.0
        luminances.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
    }

    guard !luminances.isEmpty else { return true }
    let minLuma = luminances.min() ?? 0
    let maxLuma = luminances.max() ?? 0
    let meanLuma = luminances.reduce(0, +) / CGFloat(luminances.count)
    return meanLuma < 0.03 && (maxLuma - minLuma) < 0.025
}

func steamWorkshopPreviewImage(from data: Data) -> NSImage? {
    guard !steamWorkshopPreviewImageDataIsAnimated(data) else {
        return NSImage(data: data)
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [
              kCGImageSourceShouldCache: true,
              kCGImageSourceShouldCacheImmediately: true
          ] as CFDictionary) else {
        return NSImage(data: data)
    }
    return steamWorkshopPreviewImage(from: cgImage)
}

func steamWorkshopPreviewImage(from url: URL) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return NSImage(contentsOf: url)
    }
    if steamWorkshopPreviewImageSourceIsAnimated(source) {
        return NSImage(contentsOf: url)
    }
    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [
        kCGImageSourceShouldCache: true,
        kCGImageSourceShouldCacheImmediately: true
    ] as CFDictionary) else {
        return NSImage(contentsOf: url)
    }
    return steamWorkshopPreviewImage(from: cgImage)
}

func steamWorkshopPreviewImage(from cgImage: CGImage) -> NSImage? {
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
}

private func steamWorkshopPreviewImageIsAnimated(_ image: NSImage) -> Bool {
    image.representations.contains { representation in
        guard let bitmap = representation as? NSBitmapImageRep else { return false }
        let frameCount = bitmap.value(forProperty: .frameCount) as? Int ?? 1
        return frameCount > 1
    }
}

private func steamWorkshopPreviewImageDataIsAnimated(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
    return steamWorkshopPreviewImageSourceIsAnimated(source)
}

private func steamWorkshopPreviewImageSourceIsAnimated(_ source: CGImageSource) -> Bool {
    CGImageSourceGetCount(source) > 1
}
