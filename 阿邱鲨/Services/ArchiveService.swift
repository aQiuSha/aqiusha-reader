//
//  ArchiveService.swift
//  阿邱鲨
//  压缩包解压服务，支持 CBZ(ZIP) 格式
//

import Foundation
import Compression

/// 压缩包解压服务
final class ArchiveService {

    static let shared = ArchiveService()

    private init() {}

    // MARK: - ZIP 结构常量
    private let localFileHeaderSignature: UInt32 = 0x04034b50

    /// 支持的图片扩展名
    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic"]

    // MARK: - 公共方法

    /// 解压 CBZ/ZIP 文件到指定目录
    func unzip(archiveURL: URL, to destinationURL: URL) throws -> [URL] {
        let data = try Data(contentsOf: archiveURL)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        var extractedFiles: [URL] = []
        var offset = 0

        while offset < data.count - 4 {
            guard let signature = data.readUInt32(at: offset) else { break }

            if signature == localFileHeaderSignature {
                do {
                    let result = try extractLocalFile(data: data, offset: offset, destinationURL: destinationURL)
                    if let fileURL = result.fileURL {
                        extractedFiles.append(fileURL)
                    }
                    offset = result.nextOffset
                } catch {
                    offset += 1
                    continue
                }
            } else {
                offset += 1
            }
        }

        let imageFiles = extractedFiles.filter {
            imageExtensions.contains($0.pathExtension.lowercased())
        }
        return imageFiles.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// 从压缩包中提取第一张图片作为封面
    func extractCover(from archiveURL: URL) throws -> Data? {
        let data = try Data(contentsOf: archiveURL)
        var offset = 0

        while offset < data.count - 4 {
            guard let signature = data.readUInt32(at: offset) else { break }

            if signature == localFileHeaderSignature {
                do {
                    let result = try extractFileData(data: data, offset: offset)
                    if let fileData = result.data,
                       let fileName = result.fileName,
                       imageExtensions.contains((fileName as NSString).pathExtension.lowercased()) {
                        return fileData
                    }
                    offset = result.nextOffset
                } catch {
                    offset += 1
                    continue
                }
            } else {
                offset += 1
            }
        }
        return nil
    }

    func isSupportedArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "cbz" || ext == "zip"
    }

    // MARK: - 私有方法
    private struct LocalFileResult {
        let fileURL: URL?
        let nextOffset: Int
    }

    private func extractLocalFile(data: Data, offset: Int, destinationURL: URL) throws -> LocalFileResult {
        guard let compressionMethod = data.readUInt16(at: offset + 8),
              let compressedSize = data.readUInt32(at: offset + 18),
              let fileNameLength = data.readUInt16(at: offset + 26),
              let extraFieldLength = data.readUInt16(at: offset + 28) else {
            throw ArchiveError.invalidArchive
        }

        let fileNameStart = offset + 30
        let fileNameEnd = fileNameStart + Int(fileNameLength)
        guard fileNameEnd <= data.count else { throw ArchiveError.invalidArchive }

        let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
        guard let fileName = String(data: fileNameData, encoding: .utf8) else {
            throw ArchiveError.invalidArchive
        }

        if fileName.hasSuffix("/") {
            let dataOffset = fileNameEnd + Int(extraFieldLength)
            return LocalFileResult(fileURL: nil, nextOffset: dataOffset + Int(compressedSize))
        }

        let dataOffset = fileNameEnd + Int(extraFieldLength)
        let dataEnd = dataOffset + Int(compressedSize)
        guard dataEnd <= data.count else { throw ArchiveError.invalidArchive }

        let compressedData = data.subdata(in: dataOffset..<dataEnd)
        let fileData: Data

        if compressionMethod == 0 {
            fileData = compressedData
        } else {
            // 不支持的压缩方式，直接跳过
            return LocalFileResult(fileURL: nil, nextOffset: dataEnd)
        }

        let safeFileName = (fileName as NSString).lastPathComponent
        let fileURL = destinationURL.appendingPathComponent(safeFileName)
        try? fileData.write(to: fileURL)

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
              let fileNameLength = data.readUInt16(at: offset + 26),
              let extraFieldLength = data.readUInt16(at: offset + 28) else {
            throw ArchiveError.invalidArchive
        }

        let fileNameStart = offset + 30
        let fileNameEnd = fileNameStart + Int(fileNameLength)
        guard fileNameEnd <= data.count else { throw ArchiveError.invalidArchive }

        let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
        let fileName = String(data: fileNameData, encoding: .utf8) ?? "cover.jpg"

        let dataOffset = fileNameEnd + Int(extraFieldLength)
        let dataEnd = dataOffset + Int(compressedSize)
        guard dataEnd <= data.count else { throw ArchiveError.invalidArchive }

        let compressedData = data.subdata(in: dataOffset..<dataEnd)
        let fileData: Data

        if compressionMethod == 0 {
            fileData = compressedData
        } else {
            return FileDataResult(data: nil, fileName: fileName, nextOffset: dataEnd)
        }

        return FileDataResult(data: fileData, fileName: fileName, nextOffset: dataEnd)
    }
}

enum ArchiveError: LocalizedError {
    case invalidArchive

    var errorDescription: String? {
        return "无效的压缩包文件"
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else { return nil }
        let b0 = self[startIndex + offset]
        let b1 = self[startIndex + offset + 1]
        return UInt16(b0) | (UInt16(b1) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        let b0 = self[startIndex + offset]
        let b1 = self[startIndex + offset + 1]
        let b2 = self[startIndex + offset + 2]
        let b3 = self[startIndex + offset + 3]
        return UInt32(b0) | (UInt32(b1) << 8) | (UInt32(b2) << 16) | (UInt32(b3) << 24)
    }
}
