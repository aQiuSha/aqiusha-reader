//
//  ArchiveService.swift
//  阿邱鲨
//  压缩包解压服务，使用 ZIPFoundation 成熟库，绝对稳定
//

import Foundation
import ZIPFoundation

/// 压缩包解压服务
final class ArchiveService {

    static let shared = ArchiveService()

    private init() {}

    /// 支持的图片扩展名
    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic"]

    /// 解压 CBZ/ZIP 文件到指定目录
    func unzip(archiveURL: URL, to destinationURL: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // 使用 ZIPFoundation 成熟库解压
        try FileManager.default.unzipItem(at: archiveURL, to: destinationURL)

        // 遍历目录找图片
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let imageFiles = fileURLs.filter {
            imageExtensions.contains($0.pathExtension.lowercased())
        }
        return imageFiles.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// 从压缩包中提取第一张图片作为封面
    func extractCover(from archiveURL: URL) throws -> Data? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: archiveURL, to: tempDir)

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let imageFile = fileURLs.first {
            imageExtensions.contains($0.pathExtension.lowercased())
        }

        guard let imageURL = imageFile else { return nil }
        return try Data(contentsOf: imageURL)
    }

    func isSupportedArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "cbz" || ext == "zip"
    }
}

enum ArchiveError: LocalizedError {
    case invalidArchive
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "无效的压缩包文件"
        case .decompressionFailed:
            return "解压失败，文件可能已损坏"
        }
    }
}
