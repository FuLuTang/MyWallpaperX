import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension SteamWorkshopWebPropertyControlRow {
    static func formattedNumber(_ value: Double, allowsFractional: Bool, precision: Int?) -> String {
        if !allowsFractional {
            return String(Int(value.rounded()))
        }
        let digits = max(precision ?? 2, 0)
        return String(format: "%.\(digits)f", value)
    }

    static func color(from raw: String) -> Color {
        guard let components = SteamWorkshopService.parseWebColorComponents(from: raw) else {
            return .black
        }
        return Color(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }

    static func colorString(from color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        return String(
            format: "%.6f %.6f %.6f",
            nsColor.redComponent,
            nsColor.greenComponent,
            nsColor.blueComponent
        )
    }

    func presentPathPicker(selectsDirectories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !selectsDirectories
        panel.canChooseDirectories = selectsDirectories
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.canCreateDirectories = selectsDirectories
        panel.prompt = selectsDirectories ? "选择目录" : "选择文件"
        if !selectsDirectories {
            panel.allowedContentTypes = allowedContentTypes(for: definition.fileType)
        }

        if panel.runModal() == .OK, let url = panel.url {
            filePickerError = nil
            onChange(.string(url.path))
        } else if panel.urls.isEmpty == false {
            filePickerError = selectsDirectories ? "目录选择失败" : "文件选择失败"
        }
    }

    func allowedContentTypes(for fileType: String?) -> [UTType] {
        guard let normalized = fileType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              normalized.isEmpty == false else {
            return []
        }

        switch normalized {
        case "image":
            return [.image]
        case "video":
            return [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        case "audio", "music":
            return [.audio, .mp3, .mpeg4Audio]
        default:
            return []
        }
    }
}
