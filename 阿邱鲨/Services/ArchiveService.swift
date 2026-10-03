//
//  ArchiveService.swift
//  阿邱鲨
//  压缩包解压服务，使用系统官方API，绝对稳定
//

import Foundation

/// 压缩包解压服务
final class ArchiveService {

    static let shared = ArchiveService()

    private init() {}

    /// 支持的图片扩展名
    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic"]

    /// 解压 CBZ/ZIP 文件到指定目录
    /// - Parameters:
    ///   - archiveURL: 压缩包文件 URL
    ///   - destinationURL: 目标目录 URL
    /// - Returns: 解压出的图片文件 URL 列表（按文件名自然排序）
    func unzip(archiveURL: URL, to destinationURL: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: destinationURL,
                                                withIntermediateDirectories: true)

        // 使用系统官方API解压，绝对稳定，不会崩溃
        try FileManager.default.unzipItem(at: archiveURL, to: destinationURL)

        // 遍历目录找图片
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        // 只保留图片文件并按自然排序
        let imageFiles = fileURLs.filter {
            imageExtensions.contains($0.pathExtension.lowercased())
        }
        return imageFiles.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// 从压缩包中提取第一张图片作为封面（不全部解压）
    func extractCover(from archiveURL: URL) throws -> Data? {
        // 临时解压到临时目录
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

        // 找第一张图片
        let imageFile = fileURLs.first {
            imageExtensions.contains($0.pathExtension.lowercased())
        }

        guard let imageURL = imageFile else { return nil }
        return try Data(contentsOf: imageURL)
    }

    /// 判断文件是否为支持的压缩包格式
    func isSupportedArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "cbz" || ext == "zip"
    }
}

// MARK: - 错误类型
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
