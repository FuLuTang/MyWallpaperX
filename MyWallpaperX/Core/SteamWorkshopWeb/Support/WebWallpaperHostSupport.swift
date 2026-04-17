//
//  WebWallpaperHostSupport.swift
//  MyWallpaperX
//

import Foundation

enum WebWallpaperHostSupport {
    static let localScheme = "mwx-local"

    static func makeLocalSchemeEntryURL(entryURL: URL, rootURL: URL) -> URL {
        let normalizedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let normalizedEntry = entryURL.resolvingSymlinksInPath().standardizedFileURL
        let relativePath: String
        if normalizedEntry.path == normalizedRoot.path {
            relativePath = ""
        } else if normalizedEntry.path.hasPrefix(normalizedRoot.path + "/") {
            relativePath = String(normalizedEntry.path.dropFirst(normalizedRoot.path.count + 1))
        } else {
            relativePath = normalizedEntry.lastPathComponent
        }
        var components = URLComponents()
        components.scheme = localScheme
        components.host = "wallpaper"
        components.percentEncodedPath = "/" + relativePath.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        return components.url ?? normalizedEntry
    }

    static func javaScriptQuotedString(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "\"\(escaped)\""
    }

    static func javaScriptArrayLiteral(from strings: [String]) -> String {
        let quoted = strings.map { javaScriptQuotedString($0) }
        return "[\(quoted.joined(separator: ","))]"
    }
}
