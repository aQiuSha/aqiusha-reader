//
//  Bookmark.swift
//  阿邱鲨
//
//  书签模型
//

import Foundation
import UIKit

/// 书签
struct Bookmark: Identifiable, Codable, Hashable {
    let id: UUID
    /// 关联的漫画 ID
    let comicID: UUID
    /// 页码（从 0 开始）
    let pageIndex: Int
    /// 书签名称/备注
    var name: String
    /// 创建时间
    let createdAt: Date
    /// 缩略图（可选，保存为 PNG 数据）
    var thumbnailData: Data?

    init(id: UUID = UUID(),
         comicID: UUID,
         pageIndex: Int,
         name: String? = nil,
         createdAt: Date = Date(),
         thumbnailData: Data? = nil) {
        self.id = id
        self.comicID = comicID
        self.pageIndex = pageIndex
        self.name = name ?? "第 \(pageIndex + 1) 页"
        self.createdAt = createdAt
        self.thumbnailData = thumbnailData
    }

    /// 缩略图
    var thumbnail: UIImage? {
        guard let data = thumbnailData else { return nil }
        return UIImage(data: data)
    }
}
