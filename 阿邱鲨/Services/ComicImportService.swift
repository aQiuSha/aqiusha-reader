//
//  ComicImportService.swift
//  阿邱鲨
//
//  漫画导入服务：处理全格式漫画文件导入
//  支持：CBZ / CBR / PDF / EPUB / 图片 / 图片文件夹
//

import Foundation
import UIKit
import PDFKit

/// 漫画导入服务
final class ComicImportService {

    static let shared = ComicImportService()

    private let fileManager = FileManager.default
    private let archiveService = ArchiveService.shared
    private let rarService = RARArchiveService.shared
    private let epubService = EPUBService.shared

    /// Documents 目录下的漫画存储子目录
    private var comicsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Comics", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// 解压文件存储目录
    private var extractedDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Extracted", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private init() {}

    // MARK: - 公共方法

    /// 导入漫画文件
    /// - Parameter sourceURL: 源文件 URL
    /// - Returns: 导入后的 Comic 模型
    func importComic(from sourceURL: URL) async throws -> Comic {
        let format = detectFormat(for: sourceURL)

        switch format {
        case .cbz:
            return try await importCBZ(from: sourceURL)
        case .cbr:
            return try await importCBR(from: sourceURL)
        case .pdf:
            return try await importPDF(from: sourceURL)
        case .epub:
            return try await importEPUB(from: sourceURL)
        case .folder:
            return try await importFolder(from: sourceURL)
        case .images:
            return try await importImages(from: sourceURL)
        case .unknown:
            throw ComicImportError.unsupportedFormat("不支持的文件格式")
        }
    }

    /// 检测文件格式
    func detectFormat(for url: URL) -> ComicFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "cbz", "zip":
            return .cbz
        case "cbr", "rar":
            return .cbr
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        default:
            // 检查是否为图片
            let imageExts = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic", "svg"]
            if imageExts.contains(ext) {
                return .images
            }
            // 检查是否为目录
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return .folder
            }
            return .unknown
        }
    }

    /// 获取所有支持的文件类型（用于文件选择器）
    var supportedDocumentTypes: [String] {
        return [
            "comicbook",          // CBZ/CBR
            "comicbook+zip",      // CBZ
            "comicbook+rar",      // CBR
            "pdf",                // PDF
            "epub",               // EPUB
            "zip",                // ZIP
            "rar",                // RAR
            "image",              // 所有图片
            "public.image",
            "public.data",        // 兜底
            "public.content"
        ]
    }

    /// 获取漫画的所有页面
    func pages(for comic: Comic) -> [ComicPage] {
        // PDF 特殊处理
        if comic.format == .pdf {
            return pdfPages(for: comic)
        }

        // 其他格式（CBZ/CBR/EPUB/文件夹/图片）解压后都是图片
        guard let extractedURL = comic.extractedURL else { return [] }

        do {
            let files = try fileManager.contentsOfDirectory(at: extractedURL,
                                                            includingPropertiesForKeys: nil)
            let imageExts: Set<String> = [
                "jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic", "svg"
            ]
            let imageFiles = files.filter {
                imageExts.contains($0.pathExtension.lowercased())
            }.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }

            return imageFiles.enumerated().map { index, url in
                ComicPage(index: index, imageURL: url, fileName: url.lastPathComponent)
            }
        } catch {
            return []
        }
    }

    /// 获取封面图片
    func coverImage(for comic: Comic) -> UIImage? {
        if let extractedURL = comic.extractedURL,
           let coverName = comic.coverFileName {
            let coverURL = extractedURL.appendingPathComponent(coverName)
            return UIImage(contentsOfFile: coverURL.path)
        }

        // 尝试从第一页获取
        let firstPage = pages(for: comic).first
        if let url = firstPage?.imageURL {
            return UIImage(contentsOfFile: url.path)
        }

        return nil
    }

    /// 删除漫画及其解压文件
    func deleteComic(_ comic: Comic) throws {
        // 删除源文件
        let sourceURL = comic.sourceURL
        if fileManager.fileExists(atPath: sourceURL.path) {
            try fileManager.removeItem(at: sourceURL)
        }

        // 删除解压目录
        if let extractedURL = comic.extractedURL,
           fileManager.fileExists(atPath: extractedURL.path) {
            try fileManager.removeItem(at: extractedURL)
        }
    }

    // MARK: - CBZ / ZIP 导入

    private func importCBZ(from sourceURL: URL) async throws -> Comic {
        let fileSize = try fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0

        let fileName = sourceURL.lastPathComponent
        let destURL = comicsDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destURL)

        let comicID = UUID()
        let extractDest = extractedDirectory.appendingPathComponent(comicID.uuidString, isDirectory: true)
        let imageFiles = try archiveService.unzip(archiveURL: destURL, to: extractDest)

        let title = (fileName as NSString).deletingPathExtension
        let coverName = imageFiles.first?.lastPathComponent
        let relativeSource = "Comics/\(fileName)"
        let relativeExtracted = "Extracted/\(comicID.uuidString)"

        return Comic(
            id: comicID,
            title: title,
            sourcePath: relativeSource,
            extractedPath: relativeExtracted,
            format: .cbz,
            pageCount: imageFiles.count,
            coverFileName: coverName,
            fileSize: fileSize
        )
    }

    // MARK: - CBR / RAR 导入

    private func importCBR(from sourceURL: URL) async throws -> Comic {
        // 检查 RAR 支持是否可用
        guard rarService.isRARAvailable else {
            throw ComicImportError.unsupportedFormat("""
            CBR/RAR 格式需要集成 UnrarKit 库。
            请在 Xcode 中添加：File → Add Package Dependencies →
            https://github.com/abbeycode/UnrarKit.git
            """)
        }

        let fileSize = try fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0

        let fileName = sourceURL.lastPathComponent
        let destURL = comicsDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destURL)

        let comicID = UUID()
        let extractDest = extractedDirectory.appendingPathComponent(comicID.uuidString, isDirectory: true)
        let imageFiles = try rarService.unrar(archiveURL: destURL, to: extractDest)

        let title = (fileName as NSString).deletingPathExtension
        let coverName = imageFiles.first?.lastPathComponent
        let relativeSource = "Comics/\(fileName)"
        let relativeExtracted = "Extracted/\(comicID.uuidString)"

        return Comic(
            id: comicID,
            title: title,
            sourcePath: relativeSource,
            extractedPath: relativeExtracted,
            format: .cbr,
            pageCount: imageFiles.count,
            coverFileName: coverName,
            fileSize: fileSize
        )
    }

    // MARK: - EPUB 导入

    private func importEPUB(from sourceURL: URL) async throws -> Comic {
        let fileSize = try fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0

        let fileName = sourceURL.lastPathComponent
        let destURL = comicsDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destURL)

        let comicID = UUID()
        let extractDest = extractedDirectory.appendingPathComponent(comicID.uuidString, isDirectory: true)

        // 解析 EPUB，按阅读顺序提取图片
        let imageFiles = try epubService.extractImages(from: destURL, to: extractDest)

        guard !imageFiles.isEmpty else {
            throw ComicImportError.unsupportedFormat("EPUB 中未找到图片资源，可能不是漫画格式的 EPUB")
        }

        // 尝试从 EPUB 元数据获取书名
        let title = epubService.extractTitle(from: destURL) ??
                    (fileName as NSString).deletingPathExtension

        let coverName = imageFiles.first?.lastPathComponent
        let relativeSource = "Comics/\(fileName)"
        let relativeExtracted = "Extracted/\(comicID.uuidString)"

        return Comic(
            id: comicID,
            title: title,
            sourcePath: relativeSource,
            extractedPath: relativeExtracted,
            format: .epub,
            pageCount: imageFiles.count,
            coverFileName: coverName,
            fileSize: fileSize
        )
    }

    // MARK: - PDF 导入

    private func importPDF(from sourceURL: URL) async throws -> Comic {
        let fileSize = try fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0

        let fileName = sourceURL.lastPathComponent
        let destURL = comicsDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destURL)

        guard let pdfDocument = PDFDocument(url: destURL) else {
            throw ComicImportError.invalidPDF
        }

        let title = (fileName as NSString).deletingPathExtension
        let pageCount = pdfDocument.pageCount

        // 提取第一页作为封面
        var coverName: String? = nil
        let comicID = UUID()

        if let firstPage = pdfDocument.page(at: 0) {
            let pageRect = firstPage.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let coverImage = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: pageRect.size))
                ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                firstPage.draw(with: .mediaBox, to: ctx.cgContext)
            }

            let extractDest = extractedDirectory.appendingPathComponent(comicID.uuidString, isDirectory: true)
            try fileManager.createDirectory(at: extractDest, withIntermediateDirectories: true)

            if let coverData = coverImage.jpegData(compressionQuality: 0.8) {
                let coverURL = extractDest.appendingPathComponent("cover.jpg")
                try coverData.write(to: coverURL)
                coverName = "cover.jpg"
            }

            let relativeSource = "Comics/\(fileName)"
            let relativeExtracted = "Extracted/\(comicID.uuidString)"

            return Comic(
                id: comicID,
                title: title,
                sourcePath: relativeSource,
                extractedPath: relativeExtracted,
                format: .pdf,
                pageCount: pageCount,
                coverFileName: coverName,
                fileSize: fileSize
            )
        }

        let relativeSource = "Comics/\(fileName)"
        return Comic(
            id: comicID,
            title: title,
            sourcePath: relativeSource,
            format: .pdf,
            pageCount: pageCount,
            fileSize: fileSize
        )
    }

    // MARK: - 文件夹导入

    private func importFolder(from sourceURL: URL) async throws -> Comic {
        let comicID = UUID()
        let destURL = comicsDirectory.appendingPathComponent(comicID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)

        let files = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
        let imageExts: Set<String> = [
            "jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic", "svg"
        ]
        let imageFiles = files.filter {
            imageExts.contains($0.pathExtension.lowercased())
        }.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        for file in imageFiles {
            let destFile = destURL.appendingPathComponent(file.lastPathComponent)
            try fileManager.copyItem(at: file, to: destFile)
        }

        var totalSize: Int64 = 0
        for file in imageFiles {
            if let size = try? fileManager.attributesOfItem(atPath: file.path)[.size] as? Int64 {
                totalSize += size
            }
        }

        let title = sourceURL.lastPathComponent
        let coverName = imageFiles.first?.lastPathComponent
        let relativeSource = "Comics/\(comicID.uuidString)"

        return Comic(
            id: comicID,
            title: title,
            sourcePath: relativeSource,
            extractedPath: relativeSource,
            format: .folder,
            pageCount: imageFiles.count,
            coverFileName: coverName,
            fileSize: totalSize
        )
    }

    // MARK: - 单张图片导入

    private func importImages(from sourceURL: URL) async throws -> Comic {
        let comicID = UUID()
        let destURL = comicsDirectory.appendingPathComponent(comicID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)

        let destFile = destURL.appendingPathComponent(sourceURL.lastPathComponent)
        try fileManager.copyItem(at: sourceURL, to: destFile)

        let fileSize = try fileManager.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0
        let title = (sourceURL.lastPathComponent as NSString).deletingPathExtension
        let relativeSource = "Comics/\(comicID.uuidString)"

        return Comic(
            id: comicID,
            title: title,
            sourcePath: relativeSource,
            extractedPath: relativeSource,
            format: .images,
            pageCount: 1,
            coverFileName: sourceURL.lastPathComponent,
            fileSize: fileSize
        )
    }

    // MARK: - PDF 页面

    private func pdfPages(for comic: Comic) -> [ComicPage] {
        guard comic.format == .pdf,
              let pdfDocument = PDFDocument(url: comic.sourceURL) else {
            return []
        }

        var pages: [ComicPage] = []
        for i in 0..<pdfDocument.pageCount {
            pages.append(ComicPage(
                index: i,
                imageURL: comic.sourceURL,
                fileName: "page_\(i + 1)"
            ))
        }
        return pages
    }
}

// MARK: - 错误类型

enum ComicImportError: LocalizedError {
    case unsupportedFormat(String)
    case invalidPDF
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let msg):
            return msg
        case .invalidPDF:
            return "无效的 PDF 文件"
        case .importFailed(let msg):
            return "导入失败：\(msg)"
        }
    }
}
