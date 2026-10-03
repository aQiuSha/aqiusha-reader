//
//  ArchiveService.swift
//  阿邱鲨
//
//  压缩包解压服务，支持 CBZ(ZIP) 格式
//  基于系统 Compression 框架实现，无需第三方依赖
//

import Foundation
import Compression

/// 压缩包解压服务
final class ArchiveService {

    static let shared = ArchiveService()

    private init() {}

    // MARK: - ZIP 结构常量

    private let localFileHeaderSignature: UInt32 = 0x04034b50
    private let centralDirectorySignature: UInt32 = 0x02014b50
    private let dataDescriptorSignature: UInt32 = 0x08074b50

    /// 支持的图片扩展名
    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic"]

    // MARK: - 公共方法

    /// 解压 CBZ/ZIP 文件到指定目录
    /// - Parameters:
    ///   - archiveURL: 压缩包文件 URL
    ///   - destinationURL: 目标目录 URL
    /// - Returns: 解压出的图片文件 URL 列表（按文件名自然排序）
    func unzip(archiveURL: URL, to destinationURL: URL) throws -> [URL] {
        let data = try Data(contentsOf: archiveURL)
        try FileManager.default.createDirectory(at: destinationURL,
                                                withIntermediateDirectories: true)

        var extractedFiles: [URL] = []
        var offset = 0

        while offset < data.count - 4 {
            guard let signature = data.readUInt32(at: offset) else { break }

            if signature == localFileHeaderSignature {
                let result = try extractLocalFile(data: data,
                                                   offset: offset,
                                                   destinationURL: destinationURL)
                if let fileURL = result.fileURL {
                    extractedFiles.append(fileURL)
                }
                offset = result.nextOffset
            } else if signature == centralDirectorySignature {
                break
            } else {
                offset += 1
            }
        }

        // 只保留图片文件并按自然排序
        let imageFiles = extractedFiles.filter {
            imageExtensions.contains($0.pathExtension.lowercased())
        }
        return imageFiles.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// 从压缩包中提取第一张图片作为封面（不全部解压）
    func extractCover(from archiveURL: URL) throws -> Data? {
        let data = try Data(contentsOf: archiveURL)
        var offset = 0

        while offset < data.count - 4 {
            guard let signature = data.readUInt32(at: offset) else { break }

            if signature == localFileHeaderSignature {
                let result = try extractFileData(data: data, offset: offset)
                if let fileData = result.data,
                   let fileName = result.fileName,
                   imageExtensions.contains((fileName as NSString).pathExtension.lowercased()) {
                    return fileData
                }
                offset = result.nextOffset
            } else {
                break
            }
        }
        return nil
    }

    /// 判断文件是否为支持的压缩包格式
    func isSupportedArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "cbz" || ext == "zip"
    }

    // MARK: - 私有方法

    private struct LocalFileResult {
        let fileURL: URL?
        let nextOffset: Int
    }

    private func extractLocalFile(data: Data,
                                   offset: Int,
                                   destinationURL: URL) throws -> LocalFileResult {
        guard let compressionMethod = data.readUInt16(at: offset + 8),
              let compressedSize = data.readUInt32(at: offset + 18),
              let uncompressedSize = data.readUInt32(at: offset + 22),
              let fileNameLength = data.readUInt16(at: offset + 26),
              let extraFieldLength = data.readUInt16(at: offset + 28) else {
            throw ArchiveError.invalidArchive
        }

        let fileNameStart = offset + 30
        let fileNameEnd = fileNameStart + Int(fileNameLength)
        guard fileNameEnd <= data.count else { throw ArchiveError.invalidArchive }

        let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
        guard let fileName = String(data: fileNameData, encoding: .utf8) ??
                            String(data: fileNameData, encoding: .shiftJIS) else {
            throw ArchiveError.invalidArchive
        }

        // 跳过目录条目
        if fileName.hasSuffix("/") {
            let dataOffset = fileNameEnd + Int(extraFieldLength)
            return LocalFileResult(fileURL: nil, nextOffset: dataOffset + Int(compressedSize))
        }

        let dataOffset = fileNameEnd + Int(extraFieldLength)
        let dataEnd = dataOffset + Int(compressedSize)
        guard dataEnd <= data.count else { throw ArchiveError.invalidArchive }

        let compressedData = data.subdata(in: dataOffset..<dataEnd)

        // 解压数据
        let fileData: Data
        if compressionMethod == 0 {
            fileData = compressedData
        } else if compressionMethod == 8 {
            fileData = try decompressRawDeflate(data: compressedData,
                                                 expectedSize: Int(uncompressedSize))
        } else {
            throw ArchiveError.unsupportedCompression(method: compressionMethod)
        }

        // 安全处理文件名，防止路径遍历攻击
        let safeFileName = (fileName as NSString).lastPathComponent
        let fileURL = destinationURL.appendingPathComponent(safeFileName)
        try fileData.write(to: fileURL)

        return LocalFileResult(fileURL: fileURL, nextOffset: dataEnd)
    }

    private struct FileDataResult {
        let data: Data?
        let fileName: String?
        let nextOffset: Int
    }

    private func extractFileData(data: Data, offset: Int) throws -> FileDataResult {
        guard let compressionMethod = data.readUInt16(at: offset + 8),
              let compressedSize = data.readUInt32(at: offset + 18),
              let uncompressedSize = data.readUInt32(at: offset + 22),
              let fileNameLength = data.readUInt16(at: offset + 26),
              let extraFieldLength = data.readUInt16(at: offset + 28) else {
            throw ArchiveError.invalidArchive
        }

        let fileNameStart = offset + 30
        let fileNameEnd = fileNameStart + Int(fileNameLength)
        guard fileNameEnd <= data.count else { throw ArchiveError.invalidArchive }

        let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
        let fileName = String(data: fileNameData, encoding: .utf8) ??
                       String(data: fileNameData, encoding: .shiftJIS)

        let dataOffset = fileNameEnd + Int(extraFieldLength)
        let dataEnd = dataOffset + Int(compressedSize)
        guard dataEnd <= data.count else { throw ArchiveError.invalidArchive }

        let compressedData = data.subdata(in: dataOffset..<dataEnd)

        let fileData: Data
        if compressionMethod == 0 {
            fileData = compressedData
        } else if compressionMethod == 8 {
            fileData = (try? decompressRawDeflate(data: compressedData,
                                                   expectedSize: Int(uncompressedSize))) ?? compressedData
        } else {
            return FileDataResult(data: nil, fileName: fileName, nextOffset: dataEnd)
        }

        return FileDataResult(data: fileData, fileName: fileName, nextOffset: dataEnd)
    }

    /// 解压 raw deflate 数据（ZIP 使用的格式，无 zlib header）
    /// 通过手动包装 zlib header + adler32 后用系统 COMPRESSION_ZLIB 解压
    private func decompressRawDeflate(data: Data, expectedSize: Int) throws -> Data {
        guard !data.isEmpty else { return Data() }

        // 构造 zlib 包装：[0x78, 0x9c] + raw deflate + adler32(4字节)
        // 注意：adler32 校验和可能不正确，但 compression_decode_buffer 通常不验证
        var zlibData = Data([0x78, 0x9c])
        zlibData.append(data)
        zlibData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // 占位 adler32

        let dstSize = max(expectedSize, data.count * 4, 64 * 1024)
        var dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: dstSize)
        defer { dstBuffer.deallocate() }

        let decodedSize = zlibData.withUnsafeBytes { srcBytes -> Int in
            guard let srcPtr = srcBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_decode_buffer(
                dstBuffer,
                dstSize,
                srcPtr,
                zlibData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decodedSize > 0 else {
            // 备用方案：尝试不带包装直接解压
            let fallbackSize = data.withUnsafeBytes { srcBytes -> Int in
                guard let srcPtr = srcBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return compression_decode_buffer(
                    dstBuffer,
                    dstSize,
                    srcPtr,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
            guard fallbackSize > 0 else {
                throw ArchiveError.decompressionFailed
            }
            return Data(bytes: dstBuffer, count: fallbackSize)
        }

        return Data(bytes: dstBuffer, count: decodedSize)
    }
}

// MARK: - 错误类型

enum ArchiveError: LocalizedError {
    case invalidArchive
    case unsupportedCompression(method: UInt16)
    case decompressionFailed
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "无效的压缩包文件"
        case .unsupportedCompression(let method):
            return "不支持的压缩方式（代码 \(method)）"
        case .decompressionFailed:
            return "解压失败，文件可能已损坏"
        case .fileWriteFailed:
            return "文件写入失败"
        }
    }
}

// MARK: - Data 扩展

private extension Data {
    func readUInt16(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else { return nil }
        return UInt16(littleEndian: self.withUnsafeBytes {
            $0.load(fromByteOffset: offset, as: UInt16.self)
        })
    }

    func readUInt32(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        return UInt32(littleEndian: self.withUnsafeBytes {
            $0.load(fromByteOffset: offset, as: UInt32.self)
        })
    }
}
