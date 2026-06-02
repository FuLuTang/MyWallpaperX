//
//  WebWallpaperLoopbackServer.swift
//  MyWallpaperX
//

import Foundation
import Network

final class WebWallpaperLoopbackServer {
    private let queue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.web-loopback", qos: .userInitiated)
    private let schemeHandler: WebWallpaperLocalSchemeHandler
    private var listener: NWListener?
    private(set) var port: UInt16?

    init(schemeHandler: WebWallpaperLocalSchemeHandler) {
        self.schemeHandler = schemeHandler
    }

    func start() throws -> URL {
        if let port,
           let url = URL(string: "http://127.0.0.1:\(port)/") {
            return url
        }

        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener

        guard let nwPort = listener.port,
              let url = URL(string: "http://127.0.0.1:\(nwPort.rawValue)/") else {
            throw NSError(domain: "WebWallpaperLoopbackServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "loopback_port_unavailable"])
        }
        port = nwPort.rawValue
        return url
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }
            if let error {
                self.sendError(500, message: error.localizedDescription, on: connection)
                return
            }
            if nextBuffer.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                self.respond(to: nextBuffer, on: connection)
                return
            }
            self.receiveRequest(on: connection, buffer: nextBuffer)
        }
    }

    private func respond(to requestData: Data, on connection: NWConnection) {
        guard let requestText = String(data: requestData, encoding: .utf8),
              let firstLine = requestText.components(separatedBy: "\r\n").first else {
            sendError(400, message: "bad_request", on: connection)
            return
        }

        let lineParts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard lineParts.count >= 2 else {
            sendError(400, message: "bad_request", on: connection)
            return
        }
        let method = lineParts[0].uppercased()
        guard method == "GET" || method == "HEAD" else {
            sendError(405, message: "method_not_allowed", on: connection)
            return
        }

        let rawPath = lineParts[1]
        guard let requestURL = URL(string: "mwx-local://wallpaper\(rawPath)") else {
            sendError(400, message: "bad_url", on: connection)
            return
        }

        do {
            let fileURL = try schemeHandler.resolvedFileURL(for: requestURL, allowsDirectoryIndexFallback: true)
            let fileSize = try WebWallpaperLocalSchemeHandler.fileSize(for: fileURL)
            let rangeHeader = headerValue(named: "Range", in: requestText)
            var urlRequest = URLRequest(url: requestURL)
            if let rangeHeader {
                urlRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
            }
            let range = try WebWallpaperLocalSchemeHandler.byteRange(for: urlRequest, totalSize: fileSize)
            let data = method == "HEAD" ? Data() : try WebWallpaperLocalSchemeHandler.readFileData(from: fileURL, range: range)
            let mimeType = WebWallpaperLocalSchemeHandler.mimeType(for: fileURL)
            sendHTTPResponse(
                statusCode: range == nil ? 200 : 206,
                mimeType: mimeType,
                totalSize: fileSize,
                range: range,
                body: data,
                on: connection
            )
        } catch {
            sendError(404, message: error.localizedDescription, on: connection)
        }
    }

    private func sendHTTPResponse(
        statusCode: Int,
        mimeType: String,
        totalSize: Int64,
        range: ClosedRange<Int64>?,
        body: Data,
        on connection: NWConnection
    ) {
        var headers = [
            "HTTP/1.1 \(statusCode) \(statusText(statusCode))",
            "Content-Type: \(mimeType)",
            "Content-Length: \(body.count)",
            "Accept-Ranges: bytes",
            "Cache-Control: no-cache",
            "Access-Control-Allow-Origin: *",
            "Connection: close"
        ]
        if let range {
            headers.append("Content-Range: bytes \(range.lowerBound)-\(range.upperBound)/\(totalSize)")
        }
        send(Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body, on: connection)
    }

    private func sendError(_ statusCode: Int, message: String, on connection: NWConnection) {
        let body = Data(message.utf8)
        let headers = [
            "HTTP/1.1 \(statusCode) \(statusText(statusCode))",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Length: \(body.count)",
            "Connection: close"
        ]
        send(Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body, on: connection)
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func headerValue(named name: String, in requestText: String) -> String? {
        let prefix = "\(name):"
        for line in requestText.components(separatedBy: "\r\n") {
            if line.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func statusText(_ statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 206: "Partial Content"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
    }
}
