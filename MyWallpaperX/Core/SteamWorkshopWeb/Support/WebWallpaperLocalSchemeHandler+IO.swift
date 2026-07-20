import Foundation
import UniformTypeIdentifiers

extension WebWallpaperLocalSchemeHandler {
    func existingFileURL(for candidateURL: URL) -> URL? {
        let standardizedCandidateURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        if FileManager.default.fileExists(atPath: standardizedCandidateURL.path) {
            return standardizedCandidateURL
        }

        let pathComponents = standardizedCandidateURL.pathComponents.filter { $0 != "/" }
        guard !pathComponents.isEmpty else {
            return nil
        }

        var resolvedURL = URL(fileURLWithPath: "/", isDirectory: true)
        for component in pathComponents {
            let exactURL = resolvedURL.appendingPathComponent(component, isDirectory: false)
            if FileManager.default.fileExists(atPath: exactURL.path) {
                resolvedURL = exactURL
                continue
            }

            guard let directoryContents = try? FileManager.default.contentsOfDirectory(
                at: resolvedURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            guard let matchedURL = directoryContents.first(where: {
                $0.lastPathComponent.compare(component, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else {
                return nil
            }
            resolvedURL = matchedURL
        }

        let standardizedResolvedURL = resolvedURL.resolvingSymlinksInPath().standardizedFileURL
        return FileManager.default.fileExists(atPath: standardizedResolvedURL.path) ? standardizedResolvedURL : nil
    }

    static func fileSize(for fileURL: URL) throws -> Int64 {
        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = resourceValues.fileSize else {
            throw LocalSchemeError.unreadableFileSize
        }
        return Int64(fileSize)
    }

    static func byteRange(for request: URLRequest, totalSize: Int64) throws -> ClosedRange<Int64>? {
        guard totalSize > 0 else { return nil }
        guard let headerValue = request.value(forHTTPHeaderField: "Range")?.trimmingCharacters(in: .whitespacesAndNewlines),
              headerValue.isEmpty == false else {
            return nil
        }
        guard headerValue.hasPrefix("bytes=") else {
            throw LocalSchemeError.invalidRangeHeader
        }
        let rawRange = String(headerValue.dropFirst("bytes=".count))
        guard rawRange.contains(",") == false else {
            throw LocalSchemeError.unsupportedMultipartRange
        }
        let components = rawRange.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 2 else {
            throw LocalSchemeError.invalidRangeHeader
        }

        let lowerText = String(components[0])
        let upperText = String(components[1])

        if lowerText.isEmpty {
            guard let suffixLength = Int64(upperText), suffixLength > 0 else {
                throw LocalSchemeError.invalidRangeHeader
            }
            let clampedLength = min(suffixLength, totalSize)
            let start = max(0, totalSize - clampedLength)
            return start...(totalSize - 1)
        }

        guard let start = Int64(lowerText), start >= 0, start < totalSize else {
            throw LocalSchemeError.rangeNotSatisfiable(totalSize: totalSize)
        }

        let end: Int64
        if upperText.isEmpty {
            end = totalSize - 1
        } else {
            guard let requestedEnd = Int64(upperText), requestedEnd >= start else {
                throw LocalSchemeError.invalidRangeHeader
            }
            end = min(requestedEnd, totalSize - 1)
        }
        return start...end
    }

    static func readFileData(from fileURL: URL, range: ClosedRange<Int64>?) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }
        if let range {
            try fileHandle.seek(toOffset: UInt64(range.lowerBound))
            let length = Int(range.upperBound - range.lowerBound + 1)
            return try fileHandle.read(upToCount: length) ?? Data()
        }
        return try fileHandle.readToEnd() ?? Data()
    }

    static func readResponseData(from fileURL: URL, range: ClosedRange<Int64>?) throws -> Data {
        let data = try readFileData(from: fileURL, range: range)
        guard range == nil else { return data }
        return WebWallpaperResponseTransformer.transform(data, fileURL: fileURL)
    }

    static func makeResponse(
        for requestURL: URL,
        mimeType: String,
        totalSize: Int64,
        range: ClosedRange<Int64>?,
        deliveredLength: Int,
        acceptsRanges: Bool = true
    ) throws -> HTTPURLResponse {
        var headers: [String: String] = [
            "Content-Type": mimeType,
            "Cache-Control": "no-cache"
        ]
        if acceptsRanges {
            headers["Accept-Ranges"] = "bytes"
        }
        let statusCode: Int
        if let range {
            statusCode = 206
            headers["Content-Length"] = String(deliveredLength)
            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound)/\(totalSize)"
        } else {
            statusCode = 200
            headers["Content-Length"] = String(totalSize)
        }
        guard let response = HTTPURLResponse(
            url: requestURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            throw LocalSchemeError.invalidResponse
        }
        return response
    }

    static func mimeType(for fileURL: URL) -> String {
        if let type = UTType(filenameExtension: fileURL.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        switch fileURL.pathExtension.lowercased() {
        case "skel":
            return "application/octet-stream"
        case "atlas", "txt":
            return "text/plain"
        case "js":
            return "text/javascript"
        case "css":
            return "text/css"
        case "html", "htm":
            return "text/html"
        case "json":
            return "application/json"
        case "svg":
            return "image/svg+xml"
        case "wasm", "unityweb":
            return "application/wasm"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "webm":
            return "video/webm"
        case "mp4", "m4v":
            return "video/mp4"
        case "mp3":
            return "audio/mpeg"
        case "ogg":
            return "audio/ogg"
        case "wav":
            return "audio/wav"
        case "m4a", "aac":
            return "audio/mp4"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ttf":
            return "font/ttf"
        case "otf":
            return "font/otf"
        default:
            return "application/octet-stream"
        }
    }

    enum LocalSchemeError: LocalizedError {
        case invalidURL
        case unreadableFileSize
        case invalidRangeHeader
        case unsupportedMultipartRange
        case rangeNotSatisfiable(totalSize: Int64)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "invalid_local_scheme_url"
            case .unreadableFileSize:
                return "local_scheme_unreadable_file_size"
            case .invalidRangeHeader:
                return "local_scheme_invalid_range_header"
            case .unsupportedMultipartRange:
                return "local_scheme_unsupported_multipart_range"
            case let .rangeNotSatisfiable(totalSize):
                return "local_scheme_range_not_satisfiable_\(totalSize)"
            case .invalidResponse:
                return "local_scheme_invalid_response"
            }
        }
    }
}
