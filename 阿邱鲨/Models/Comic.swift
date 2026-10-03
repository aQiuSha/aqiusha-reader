//
//  Comic.swift
//  阿邱鲨
//
//  漫画数据模型
//

import Foundation
import UIKit

/// 漫画格式枚举
enum ComicFormat: String, Codable, CaseIterable {
    case cbz      // ZIP 压缩包
    case cbr      // RAR 压缩包
    case pdf      // PDF 文档
    case epub     // EPUB 电子书
    case folder   // 图片文件夹
    case images   // 零散图片
    case unknown  // 未知格式

    var displayName: String {
        switch self {
        case .cbz: return "CBZ"
        case .cbr: return "CBR"
        case .pdf: return "PDF"
        case .epub: return "EPUB"
        case .folder: return "文件夹"
        case .images: return "图片"
        case .unknown: return "未知"
        }
    }
}

/// 漫画模型
struct Comic: Identifiable, Codable, Hashable {
    let id: UUID
    /// 漫画标题
    var title: String
    /// 原始文件路径（相对于 Documents 目录）
    let sourcePath: String
    /// 解压后的图片目录路径（相对于 Documents 目录）
    var extractedPath: String?
    /// 漫画格式
    let format: ComicFormat
    /// 总页数
    var pageCount: Int
    /// 封面图片文件名（相对于 extractedPath 或 sourcePath）
    var coverFileName: String?
    /// 添加日期
    let importDate: Date
    /// 文件大小（字节）
    let fileSize: Int64
    /// 作者/来源（可选）
    var author: String?
    /// 标签
    var tags: [String]
    /// 是否收藏
    var isFavorite: Bool
    /// 所属合集/文件夹名称（nil 表示未分类）
    var collectionName: String?
    /// 最后打开时间
    var lastOpenedDate: Date?
    /// 评分（0-5，0表示未评分）
    var rating: Int
    /// 手动排序索引
    var sortIndex: Int
    /// 自定义分类
    var categories: [String]
    /// 自定义封面图路径（用户手动更换的封面）
    var customCoverPath: String?

    init(id: UUID = UUID(),
         title: String,
         sourcePath: String,
         extractedPath: String? = nil,
         format: ComicFormat,
         pageCount: Int = 0,
         coverFileName: String? = nil,
         importDate: Date = Date(),
         fileSize: Int64 = 0,
         author: String? = nil,
         tags: [String] = [],
         isFavorite: Bool = false,
         collectionName: String? = nil,
         lastOpenedDate: Date? = nil,
         rating: Int = 0,
         sortIndex: Int = 0,
         categories: [String] = [],
         customCoverPath: String? = nil) {
        self.id = id
        self.title = title
        self.sourcePath = sourcePath
        self.extractedPath = extractedPath
        self.format = format
        self.pageCount = pageCount
        self.coverFileName = coverFileName
        self.importDate = importDate
        self.fileSize = fileSize
        self.author = author
        self.tags = tags
        self.isFavorite = isFavorite
        self.collectionName = collectionName
        self.lastOpenedDate = lastOpenedDate
        self.rating = rating
        self.sortIndex = sortIndex
        self.categories = categories
        self.customCoverPath = customCoverPath
    }

    /// 完整的源文件 URL
    var sourceURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(sourcePath)
    }

    /// 解压目录的完整 URL
    var extractedURL: URL? {
        guard let path = extractedPath else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(path)
    }

    /// 文件大小显示文本
    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

/// 单页漫画
struct ComicPage: Identifiable, Hashable {
    let id: UUID
    /// 页码（从 0 开始）
    let index: Int
    /// 图片文件 URL
    let imageURL: URL
    /// 文件名
    let fileName: String

    init(index: Int, imageURL: URL, fileName: String) {
        self.id = UUID()
        self.index = index
        self.imageURL = imageURL
        self.fileName = fileName
    }
}

