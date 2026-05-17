import Compression
import Foundation
import Metal

struct SceneTexContainer {
    enum ContainerVersion: String {
        case texb0001 = "TEXB0001"
        case texb0002 = "TEXB0002"
        case texb0003 = "TEXB0003"
        case texb0004 = "TEXB0004"
    }

    struct Mip {
        let width: Int
        let height: Int
        let data: Data
    }

    let format: UInt32
    let flags: UInt32
    let textureWidth: Int
    let textureHeight: Int
    let imageWidth: Int
    let imageHeight: Int
    let imageCount: Int
    let containerVersion: ContainerVersion
    let freeImageFormat: Int32
    let isVideoMp4: Bool
    let mips: [Mip]

    var isAnimated: Bool {
        flags & 4 != 0
    }

    var metalPixelFormat: MTLPixelFormat? {
        switch format {
        case 4:
            return .bc3_rgba
        case 5:
            return .bc5_rgSnorm
        case 7:
            return .bc1_rgba
        default:
            return nil
        }
    }

    var rawMetalPixelFormat: MTLPixelFormat? {
        switch format {
        case 8:
            return .rg8Unorm
        case 9:
            return .r8Unorm
        default:
            return nil
        }
    }

    var rawBytesPerPixel: Int? {
        switch format {
        case 8:
            return 2
        case 9:
            return 1
        default:
            return nil
        }
    }
}

struct SceneTexContainerReader {
    enum ReadError: LocalizedError {
        case invalidHeader
        case invalidMipTable
        case unsupportedCompression(UInt32)
        case decompressionFailed(expectedSize: Int, actualSize: Int)

        var errorDescription: String? {
            switch self {
            case .invalidHeader:
                return "无效的 TEXV0005 纹理头。"
            case .invalidMipTable:
                return "无效的 TEX mip 数据表。"
            case let .unsupportedCompression(code):
                return "不支持的 TEX mip 压缩方式: \(code)。"
            case let .decompressionFailed(expectedSize, actualSize):
                return "LZ4 解压失败，期望 \(expectedSize) 字节，实际得到 \(actualSize) 字节。"
            }
        }
    }

    private static let maximumImageCount = 512
    private static let maximumMipCount = 32
    private static let maximumMipByteCount = 250_000_000

    func read(data: Data) throws -> SceneTexContainer {
        guard data.count >= 55,
              data.starts(with: Data("TEXV0005\0TEXI0001\0".utf8)),
              data[54] == 0,
              let rawContainerVersion = String(data: data[46..<54], encoding: .ascii),
              let declaredContainerVersion = SceneTexContainer.ContainerVersion(rawValue: rawContainerVersion) else {
            throw ReadError.invalidHeader
        }

        let format = data.uint32LE(at: 18)
        let flags = data.uint32LE(at: 22)
        let textureWidth = Int(data.uint32LE(at: 26))
        let textureHeight = Int(data.uint32LE(at: 30))
        let imageWidth = Int(data.uint32LE(at: 34))
        let imageHeight = Int(data.uint32LE(at: 38))

        var offset = 55
        let imageCount = Int(data.uint32LE(at: offset))
        offset += 4
        guard imageCount > 0, imageCount <= Self.maximumImageCount else {
            throw ReadError.invalidMipTable
        }

        var freeImageFormat: Int32 = -1
        var isVideoMp4 = false
        let effectiveContainerVersion: SceneTexContainer.ContainerVersion

        switch declaredContainerVersion {
        case .texb0001, .texb0002:
            effectiveContainerVersion = declaredContainerVersion
        case .texb0003:
            guard offset + 4 <= data.count else {
                throw ReadError.invalidMipTable
            }
            freeImageFormat = data.int32LE(at: offset)
            offset += 4
            effectiveContainerVersion = .texb0003
        case .texb0004:
            guard offset + 8 <= data.count else {
                throw ReadError.invalidMipTable
            }
            freeImageFormat = data.int32LE(at: offset)
            offset += 4
            isVideoMp4 = data.uint32LE(at: offset) == 1
            offset += 4
            effectiveContainerVersion = isVideoMp4 ? .texb0004 : .texb0003
        }

        var firstImageMips: [SceneTexContainer.Mip] = []
        for imageIndex in 0..<imageCount {
            guard offset + 4 <= data.count else {
                throw ReadError.invalidMipTable
            }
            let mipCount = Int(data.uint32LE(at: offset))
            offset += 4
            guard mipCount > 0, mipCount <= Self.maximumMipCount else {
                throw ReadError.invalidMipTable
            }

            var parsedMips: [SceneTexContainer.Mip] = []
            for _ in 0..<mipCount {
                let mip = try readMip(
                    data: data,
                    offset: &offset,
                    containerVersion: effectiveContainerVersion
                )
                if imageIndex == 0 {
                    parsedMips.append(mip)
                }
            }

            if imageIndex == 0 {
                firstImageMips = parsedMips
            }
        }

        guard !firstImageMips.isEmpty else {
            throw ReadError.invalidMipTable
        }

        return SceneTexContainer(
            format: format,
            flags: flags,
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            imageCount: imageCount,
            containerVersion: effectiveContainerVersion,
            freeImageFormat: freeImageFormat,
            isVideoMp4: isVideoMp4,
            mips: firstImageMips
        )
    }

    private func readMip(
        data: Data,
        offset: inout Int,
        containerVersion: SceneTexContainer.ContainerVersion
    ) throws -> SceneTexContainer.Mip {
        if containerVersion == .texb0004 {
            guard offset + 8 <= data.count else {
                throw ReadError.invalidMipTable
            }
            offset += 8
            try data.skipNullTerminatedString(at: &offset)
            guard offset + 4 <= data.count else {
                throw ReadError.invalidMipTable
            }
            offset += 4
        }

        guard offset + 8 <= data.count else {
            throw ReadError.invalidMipTable
        }
        let width = Int(data.uint32LE(at: offset))
        offset += 4
        let height = Int(data.uint32LE(at: offset))
        offset += 4
        guard width > 0, height > 0 else {
            throw ReadError.invalidMipTable
        }

        var compressionCode: UInt32 = 0
        var decodedByteCount = 0
        if containerVersion != .texb0001 {
            guard offset + 8 <= data.count else {
                throw ReadError.invalidMipTable
            }
            compressionCode = data.uint32LE(at: offset)
            offset += 4
            decodedByteCount = Int(data.int32LE(at: offset))
            offset += 4
        }

        guard offset + 4 <= data.count else {
            throw ReadError.invalidMipTable
        }
        let storedByteCount = Int(data.int32LE(at: offset))
        offset += 4
        guard storedByteCount >= 0,
              storedByteCount <= Self.maximumMipByteCount,
              offset + storedByteCount <= data.count else {
            throw ReadError.invalidMipTable
        }

        let storedBytes = data.subdata(in: offset..<(offset + storedByteCount))
        offset += storedByteCount

        let mipData: Data
        switch compressionCode {
        case 0:
            mipData = storedBytes
        case 1:
            guard decodedByteCount > 0, decodedByteCount <= Self.maximumMipByteCount else {
                throw ReadError.invalidMipTable
            }
            mipData = try decompressLZ4Raw(storedBytes, expectedSize: decodedByteCount)
        default:
            throw ReadError.unsupportedCompression(compressionCode)
        }

        return .init(width: width, height: height, data: mipData)
    }

    private func decompressLZ4Raw(_ compressed: Data, expectedSize: Int) throws -> Data {
        var decoded = Data(count: expectedSize)
        let actualSize = decoded.withUnsafeMutableBytes { destinationBuffer in
            compressed.withUnsafeBytes { sourceBuffer in
                compression_decode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    compressed.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }

        guard actualSize == expectedSize else {
            throw ReadError.decompressionFailed(expectedSize: expectedSize, actualSize: actualSize)
        }
        return decoded
    }
}

private extension Data {
    func uint32LE(at offset: Int) -> UInt32 {
        self.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    func int32LE(at offset: Int) -> Int32 {
        self.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: Int32.self).littleEndian
        }
    }

    func skipNullTerminatedString(at offset: inout Int) throws {
        guard let terminator = self[offset...].firstIndex(of: 0) else {
            throw SceneTexContainerReader.ReadError.invalidMipTable
        }
        offset = terminator + 1
    }
}
