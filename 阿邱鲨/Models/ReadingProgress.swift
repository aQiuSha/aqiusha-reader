//
//  ReadingProgress.swift
//  阿邱鲨
//
//  阅读进度模型
//

import Foundation

/// 阅读进度
struct ReadingProgress: Codable, Hashable {
    /// 关联的漫画 ID
    let comicID: UUID
    /// 当前页码（从 0 开始）
    var currentPage: Int
    /// 总页数
    var totalPages: Int
    /// 最后阅读时间
    var lastReadDate: Date
    /// 是否读完
    var isFinished: Bool

    init(comicID: UUID,
         currentPage: Int = 0,
         totalPages: Int = 0,
         lastReadDate: Date = Date(),
         isFinished: Bool = false) {
        self.comicID = comicID
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.lastReadDate = lastReadDate
        self.isFinished = isFinished
    }

    /// 阅读进度百分比（0.0 - 1.0）
    var progress: Double {
        guard totalPages > 0 else { return 0 }
        return Double(currentPage + 1) / Double(totalPages)
    }

    /// 进度百分比文本
    var progressText: String {
        String(format: "%.0f%%", progress * 100)
    }

    /// 剩余页数
    var remainingPages: Int {
        max(0, totalPages - currentPage - 1)
    }
}

/// 阅读方向
enum ReadingDirection: String, Codable, CaseIterable {
    case leftToRight   // 从左到右（日漫常见）
    case rightToLeft   // 从右到左（国漫/美漫常见）
    case topToBottom   // 从上到下（条漫）

    var displayName: String {
        switch self {
        case .leftToRight: return "从左到右"
        case .rightToLeft: return "从右到左"
        case .topToBottom: return "从上到下"
        }
    }
}

/// 阅读模式
enum ReadingMode: String, Codable, CaseIterable {
    case singlePage    // 单页模式
    case doublePage    // 双页模式
    case longStrip     // 长条滚动模式

    var displayName: String {
        switch self {
        case .singlePage: return "单页"
        case .doublePage: return "双页"
        case .longStrip: return "条漫"
        }
    }
}
