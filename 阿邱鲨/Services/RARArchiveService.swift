//
//  RARArchiveService.swift
//  阿邱鲨
//
//  RAR/CBR 解压服务
//  基于 UnrarKit（可选依赖），条件编译：未集成时给出明确提示
//

import Foundation

#if canImport(UnrarKit)
import UnrarKit
#endif

/// RAR 压缩包解压服务
final class RARArchiveService {

    static let shared = RARArchiveService()

    private init() {}

    /// 支持的图片扩展名
    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic"
    ]

    /// 当前是否支持 RAR 解压（即是否集成了 UnrarKit）
    var isRARAvailable: Bool {
        #if canImport(UnrarKit)
        return true
        #else
        return false
        #endif
    }

    /// 判断是否为 RAR 文件
    func isRARFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "cbr" || ext == "rar"
    }

    // MARK: - 解压

    /// 解压 RAR/CBR 文件到指定目录
    /// - Parameters:
    ///   - archiveURL: RAR 文件 URL
    ///   - destinationURL: 目标目录
    /// - Returns: 解压出的图片文件 URL 列表（按文件名自然排序）
    func unrar(archiveURL: URL, to destinationURL: URL) throws -> [URL] {
        #if canImport(UnrarKit)
        return try unrarWithUnrarKit(archiveURL: archiveURL, destinationURL: destinationURL)
        #else
        throw RARError.unrarKitNotIntegrated
        #endif
    }

    /// 从 RAR 中提取第一张图片作为封面
    func extractCover(from archiveURL: URL) throws -> Data? {
        #if canImport(UnrarKit)
        return try extractCoverWithUnrarKit(from: archiveURL)
        #else
        throw RARError.unrarKitNotIntegrated
        #endif
    }

    // MARK: - UnrarKit 实现

    #if canImport(UnrarKit)

    private func unrarWithUnrarKit(archiveURL: URL,
                                    destinationURL: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: destinationURL,
                                                withIntermediateDirectories: true)

        let archive = try URKArchive(path: archiveURL.path)
        var extractedFiles: [URL] = []

        try archive.iterateFiles { entry, error in
            guard let entry = entry else { return }

            // 跳过目录
            if entry.isDirectory || entry.filename.hasSuffix("/") {
                return
            }

            // 只处理图片
            let ext = (entry.filename as NSString).pathExtension.lowercased()
            guard self.imageExtensions.contains(ext) else { return }

            do {
                let data = try archive.extractData(from: entry)
                let safeFileName = (entry.filename as NSString).lastPathComponent
                let fileURL = destinationURL.appendingPathComponent(safeFileName)
                try data.write(to: fileURL)
                extractedFiles.append(fileURL)
            } catch {
                // 跳过单个文件解压失败
            }
        }

        return extractedFiles.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func extractCoverWithUnrarKit(from archiveURL: URL) throws -> Data? {
        let archive = try URKArchive(path: archiveURL.path)
        var coverData: Data?

        try archive.iterateFiles { entry, error in
            guard coverData == nil, let entry = entry else { return }
            if entry.isDirectory { return }

            let ext = (entry.filename as NSString).pathExtension.lowercased()
            guard self.imageExtensions.contains(ext) else { return }

            coverData = try? archive.extractData(from: entry)
        }

        return coverData
    }

    #endif
}

// MARK: - 错误类型

enum RARError: LocalizedError {
    case unrarKitNotIntegrated
    case invalidRAR
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unrarKitNotIntegrated:
            return """
            CBR/RAR 格式需要集成 UnrarKit 库。
            请在 Xcode 中添加 Swift Package：
            File → Add Package Dependencies → 输入 https://github.com/abbeycode/UnrarKit.git
            集成后即可支持 CBR/RAR 格式。
            """
        case .invalidRAR:
            return "无效的 RAR 文件"
        case .extractionFailed(let msg):
            return "RAR 解压失败：\(msg)"
        }
    }
}
