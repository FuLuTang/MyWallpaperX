import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import WebKit
import Darwin
import UniformTypeIdentifiers

final class CommandReader {
    var buffer = Data()
    let decoder = JSONDecoder()
    let daemon: WallpaperDaemon

    init(daemon: WallpaperDaemon) {
        self.daemon = daemon
    }

    func start() {
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                DispatchQueue.main.async {
                    self.daemon.shutdown()
                }
                return
            }

            self.buffer.append(data)
            self.consumeBuffer()
        }
    }

    func consumeBuffer() {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)

            guard !line.isEmpty else { continue }
            do {
                let command = try decoder.decode(DaemonCommand.self, from: Data(line))
                DispatchQueue.main.async {
                    self.daemon.handle(command)
                }
            } catch {
                daemonLog("failed to decode command \(error.localizedDescription)")
            }
        }
    }
}
