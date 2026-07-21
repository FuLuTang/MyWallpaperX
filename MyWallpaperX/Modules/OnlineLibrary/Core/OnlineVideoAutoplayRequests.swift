//
//  OnlineVideoAutoplayRequests.swift
//  MyWallpaperX
//

import Foundation

final class OnlineVideoAutoplayRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingTokens: [Int: ImportedVideoAutoplayGate.Token] = [:]

    @discardableResult
    func request(for itemID: Int) -> ImportedVideoAutoplayGate.Token {
        lock.lock()
        let token = ImportedVideoAutoplayGate.shared.claim()
        pendingTokens[itemID] = token
        lock.unlock()
        return token
    }

    func complete(for itemID: Int) -> ImportedVideoAutoplayGate.Token? {
        lock.lock()
        defer { lock.unlock() }
        return pendingTokens.removeValue(forKey: itemID)
    }

    func cancel(for itemID: Int) {
        lock.lock()
        pendingTokens[itemID] = nil
        lock.unlock()
    }
}
