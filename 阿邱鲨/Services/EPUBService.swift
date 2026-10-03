//
//  EPUBService.swift
//  阿邱鲨
//
//  EPUB 格式解析服务
//  EPUB 本质是 ZIP 压缩包，内含 OPF 清单定义阅读顺序
//

import Foundation

/// EPUB 解析服务
final class EPUBService {

    static let shared = EPUBService()

    private let archiveService = ArchiveService.shared
    private let fileManager = FileManager.default

    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "svg"
    ]

    private init() {}

    /// 判断是否为 EPUB 文件
    func isEPUBFile(_ url: URL) -> Bool {
        return url.pathExtension.lowercased() == "epub"
    }

    // MARK: - 公共方法

    /// 解析 EPUB 文件，提取漫画图片页
    /// - Parameters:
    ///   - epubURL: EPUB 文件 URL
    ///   - destinationURL: 解压目标目录
    /// - Returns: 按阅读顺序排列的图片 URL 列表
    func extractImages(from epubURL: URL, to destinationURL: URL) throws -> [URL] {
        // 1. 解压 EPUB（本质是 ZIP）
        let allFiles = try archiveService.unzip(archiveURL: epubURL, to: destinationURL)

        // 2. 尝试按 OPF spine 顺序解析
        if let orderedImages = try? parseSpineOrder(in: destinationURL) {
            if !orderedImages.isEmpty {
                return orderedImages
            }
        }

        // 3. 回退：按文件名自然排序所有图片
        return allFiles.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// 从 EPUB 提取封面（不全部解压）
    func extractCover(from epubURL: URL) throws -> Data? {
        // 先全部解压到临时目录，取第一张
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let images = try extractImages(from: epubURL, to: tempDir)
        guard let firstImage = images.first else { return nil }
        return try Data(contentsOf: firstImage)
    }

    /// 获取 EPUB 书名（从 OPF 元数据中读取）
    func extractTitle(from epubURL: URL) -> String? {
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        do {
            _ = try archiveService.unzip(archiveURL: epubURL, to: tempDir)
            guard let opfURL = findOPFFile(in: tempDir) else { return nil }
            return parseTitle(fromOPF: opfURL)
        } catch {
            return nil
        }
    }

    // MARK: - OPF 解析

    /// 查找 OPF 文件路径
    private func findOPFFile(in rootURL: URL) -> URL? {
        // 先读 container.xml
        let containerURL = rootURL.appendingPathComponent("META-INF/container.xml")
        if let data = try? Data(contentsOf: containerURL),
           let opfPath = parseContainerXML(data: data) {
            // OPF 路径可能是相对路径
            let opfURL = rootURL.appendingPathComponent(opfPath)
            if fileManager.fileExists(atPath: opfURL.path) {
                return opfURL
            }
        }

        // 回退：递归查找 .opf 文件
        if let enumerator = fileManager.enumerator(at: rootURL,
                                                    includingPropertiesForKeys: nil),
           let files = enumerator.allObjects as? [URL] {
            return files.first { $0.pathExtension.lowercased() == "opf" }
        }
        return nil
    }

    /// 解析 container.xml 获取 OPF 路径
    private func parseContainerXML(data: Data) -> String? {
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }

        // 简单正则提取 rootfile 的 full-path 属性
        let pattern = "full-path=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: xmlString,
                                           range: NSRange(xmlString.startIndex..., in: xmlString)),
              let range = Range(match.range(at: 1), in: xmlString) else {
            return nil
        }
        return String(xmlString[range])
    }

    /// 解析 OPF，按 spine 顺序返回图片 URL 列表
    private func parseSpineOrder(in rootURL: URL) throws -> [URL] {
        guard let opfURL = findOPFFile(in: rootURL) else {
            throw EPUBError.opfNotFound
        }

        let opfData = try Data(contentsOf: opfURL)
        guard let opfString = String(data: opfData, encoding: .utf8) else {
            throw EPUBError.invalidOPF
        }

        // OPF 文件所在目录（用于解析相对路径）
        let opfBaseURL = opfURL.deletingLastPathComponent()

        // 1. 解析 manifest：id -> href 映射
        let manifest = parseManifest(from: opfString)

        // 2. 解析 spine：按顺序的 idref 列表
        let spineOrder = parseSpine(from: opfString)

        // 3. 按 spine 顺序收集图片
        var orderedImages: [URL] = []

        for idref in spineOrder {
            guard let href = manifest[idref] else { continue }

            let itemURL = opfBaseURL.appendingPathComponent(href)
            let ext = itemURL.pathExtension.lowercased()

            if imageExtensions.contains(ext) {
                // 直接是图片
                if fileManager.fileExists(atPath: itemURL.path) {
                    orderedImages.append(itemURL)
                }
            } else if ext == "xhtml" || ext == "html" || ext == "htm" {
                // XHTML 页面，解析其中的图片
                if let images = parseImagesFromXHTML(at: itemURL, baseURL: opfBaseURL) {
                    orderedImages.append(contentsOf: images)
                }
            }
        }

        return orderedImages
    }

    /// 解析 manifest，返回 [id: href]
    private func parseManifest(from xml: String) -> [String: String] {
        var manifest: [String: String] = [:]

        // 匹配 <item id="..." href="..." .../>
        let pattern = "<item[^>]*id=[\"']([^\"']+)[\"'][^>]*href=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return manifest
        }

        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        for match in matches {
            if let idRange = Range(match.range(at: 1), in: xml),
               let hrefRange = Range(match.range(at: 2), in: xml) {
                let id = String(xml[idRange])
                let href = String(xml[hrefRange])
                manifest[id] = href
            }
        }

        return manifest
    }

    /// 解析 spine，返回按顺序的 idref 列表
    private func parseSpine(from xml: String) -> [String] {
        var spine: [String] = []

        // 匹配 <itemref idref="..." />
        let pattern = "<itemref[^>]*idref=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return spine
        }

        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        for match in matches {
            if let range = Range(match.range(at: 1), in: xml) {
                spine.append(String(xml[range]))
            }
        }

        return spine
    }

    /// 从 XHTML 文件中解析图片引用
    private func parseImagesFromXHTML(at xhtmlURL: URL, baseURL: URL) -> [URL]? {
        guard let data = try? Data(contentsOf: xhtmlURL),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        var images: [URL] = []

        // 匹配 <img src="..." /> 和 <image href="..." /> 和 <image xlink:href="..." />
        let patterns = [
            "<img[^>]*src=[\"']([^\"']+)[\"']",
            "<image[^>]*href=[\"']([^\"']+)[\"']",
            "<image[^>]*xlink:href=[\"']([^\"']+)[\"']"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }
            let matches = regex.matches(in: content,
                                        range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    let src = String(content[range])
                    // 处理相对路径
                    let imageURL = (src as NSString).isAbsolutePath ?
                        URL(fileURLWithPath: src) :
                        xhtmlURL.deletingLastPathComponent().appendingPathComponent(src)
                    if fileManager.fileExists(atPath: imageURL.path) {
                        images.append(imageURL)
                    }
                }
            }
        }

        return images.isEmpty ? nil : images
    }

    /// 从 OPF 元数据中解析书名
    private func parseTitle(fromOPF opfURL: URL) -> String? {
        guard let data = try? Data(contentsOf: opfURL),
              let xml = String(data: data, encoding: .utf8) else {
            return nil
        }

        // 匹配 <dc:title>...</dc:title> 或 <title>...</title>
        let patterns = [
            "<dc:title[^>]*>(.*?)</dc:title>",
            "<title[^>]*>(.*?)</title>"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators]
            ) else { continue }

            if let match = regex.firstMatch(in: xml,
                                            range: NSRange(xml.startIndex..., in: xml)),
               let range = Range(match.range(at: 1), in: xml) {
                let title = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    return title
                }
            }
        }
        return nil
    }
}

// MARK: - 错误类型

enum EPUBError: LocalizedError {
    case opfNotFound
    case invalidOPF
    case noImagesFound
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .opfNotFound:
            return "EPUB 文件中未找到 OPF 清单文件"
        case .invalidOPF:
            return "OPF 文件格式无效"
        case .noImagesFound:
            return "EPUB 中未找到图片资源"
        case .extractionFailed(let msg):
            return "EPUB 解析失败：\(msg)"
        }
    }
}
