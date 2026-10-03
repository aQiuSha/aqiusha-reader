//
//  LibraryViewModel.swift
//  阿邱鲨
//
//  书架视图模型
//

import Foundation
import UIKit
import Combine

/// 书架筛选类型
enum LibraryFilter: String, CaseIterable {
    case all = "全部"
    case unread = "未读"
    case reading = "在读"
    case finished = "已读"
    case favorite = "收藏"
}

/// 书架排序方式
enum LibrarySort: String, CaseIterable {
    case byImportDate = "导入时间"
    case byTitle = "标题"
    case byProgress = "阅读进度"
    case byLastOpened = "最近阅读"
    case byFileSize = "文件大小"
    case byRating = "评分"
}

/// 书架视图模型
@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var comics: [Comic] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var sortOption: LibrarySort = .byImportDate
    @Published var filterOption: LibraryFilter = .all
    @Published var selectedComic: Comic?
    @Published var showAsList = false  // false=网格, true=列表
    @Published var importProgress: Double = 0
    @Published var importStatusText: String?
    @Published var duplicateComics: [Comic] = []
    @Published var showDuplicateConfirmation = false
    private var pendingImportURLs: [URL] = []

    private let importService = ComicImportService.shared
    private let progressService = ProgressService.shared
    private let userDefaults = UserDefaults.standard
    private let comicsKey = "com.aqiusha.comics"

    init() {
        loadComics()
    }

    // MARK: - 数据加载

    /// 加载漫画列表
    func loadComics() {
        guard let data = userDefaults.data(forKey: comicsKey),
              let comics = try? JSONDecoder().decode([Comic].self, from: data) else {
            self.comics = []
            return
        }
        self.comics = comics
    }

    /// 保存漫画列表
    private func saveComics() {
        if let data = try? JSONEncoder().encode(comics) {
            userDefaults.set(data, forKey: comicsKey)
        }
    }

    // MARK: - 导入

    /// 导入漫画文件
    func importComic(from url: URL) async {
        isLoading = true
        errorMessage = nil
        importProgress = 0
        importStatusText = "正在检测文件..."
        defer {
            isLoading = false
            importProgress = 0
            importStatusText = nil
        }

        do {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            // 重复导入检测
            if isDuplicate(url: url) {
                errorMessage = "该漫画已在书架中"
                return
            }

            importStatusText = "正在导入漫画..."
            var comic = try await importService.importComic(from: url)

            // 自动整理合集：如果文件名包含卷/话等信息，尝试提取合集名
            comic.collectionName = autoDetectCollection(from: comic.title)

            comics.insert(comic, at: 0)
            saveComics()
            importProgress = 1.0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 批量导入
    func importComics(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        importProgress = 0
        var importedCount = 0
        var skippedCount = 0
        defer {
            isLoading = false
            importProgress = 0
            importStatusText = nil
        }

        for (index, url) in urls.enumerated() {
            importStatusText = "正在导入 \(index + 1)/\(urls.count)..."
            do {
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                // 重复导入检测
                if isDuplicate(url: url) {
                    skippedCount += 1
                    importProgress = Double(index + 1) / Double(urls.count)
                    continue
                }

                var comic = try await importService.importComic(from: url)
                comic.collectionName = autoDetectCollection(from: comic.title)
                comics.insert(comic, at: 0)
                importedCount += 1
                importProgress = Double(index + 1) / Double(urls.count)
            } catch {
                // 单个文件导入失败不影响其他文件
                continue
            }
        }

        saveComics()

        if skippedCount > 0 {
            errorMessage = "成功导入 \(importedCount) 本，跳过 \(skippedCount) 本重复文件"
        }
    }

    /// 检测是否为重复导入（基于文件名+大小）
    private func isDuplicate(url: URL) -> Bool {
        let fileName = url.lastPathComponent
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let fileNameWithoutExt = url.deletingPathExtension().lastPathComponent
        return comics.contains { comic in
            comic.sourcePath == fileName ||
            (comic.fileSize == Int64(fileSize) && comic.title == fileNameWithoutExt)
        }
    }

    /// 自动检测合集名称
    private func autoDetectCollection(from title: String) -> String? {
        // 常见的合集命名模式：xxx 第01卷、xxx Vol.01、xxx 第01话
        let patterns = [
            "\\s*[第卷话集部]\\s*\\d+.*$",
            "\\s*[Vv][Oo][Ll]\\.?\\s*\\d+.*$",
            "\\s*[Cc]h\\.?\\s*\\d+.*$",
            "\\s*\\d{2,4}(-\\d{2,4})?\\s*$"
        ]
        for pattern in patterns {
            if let range = title.range(of: pattern, options: .regularExpression) {
                let collection = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !collection.isEmpty {
                    return collection
                }
            }
        }
        return nil
    }

    // MARK: - 删除

    /// 删除漫画
    func deleteComic(_ comic: Comic) {
        do {
            try importService.deleteComic(comic)
            progressService.deleteProgress(for: comic.id)
            progressService.deleteBookmarks(for: comic.id)
            comics.removeAll { $0.id == comic.id }
            saveComics()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 收藏

    /// 切换收藏状态
    func toggleFavorite(_ comic: Comic) {
        if let index = comics.firstIndex(where: { $0.id == comic.id }) {
            comics[index].isFavorite.toggle()
            saveComics()
        }
    }

    // MARK: - 合集

    /// 获取所有合集名称
    var allCollections: [String] {
        let names = Set(comics.compactMap { $0.collectionName })
        return Array(names).sorted()
    }

    /// 获取指定合集的漫画
    func comics(in collection: String) -> [Comic] {
        return comics.filter { $0.collectionName == collection }
    }

    /// 设置漫画的合集
    func setCollection(_ collection: String?, for comic: Comic) {
        if let index = comics.firstIndex(where: { $0.id == comic.id }) {
            comics[index].collectionName = collection
            saveComics()
        }
    }

    // MARK: - 打开记录

    /// 标记漫画已打开
    func markOpened(_ comic: Comic) {
        if let index = comics.firstIndex(where: { $0.id == comic.id }) {
            comics[index].lastOpenedDate = Date()
            saveComics()
        }
    }

    // MARK: - 查询

    /// 过滤和排序后的漫画列表
    var filteredComics: [Comic] {
        var result = comics

        // 筛选
        switch filterOption {
        case .all:
            break
        case .unread:
            result = result.filter {
                guard let p = progressService.getProgress(for: $0.id) else { return true }
                return p.currentPage == 0
            }
        case .reading:
            result = result.filter {
                guard let p = progressService.getProgress(for: $0.id) else { return false }
                return !p.isFinished && p.currentPage > 0
            }
        case .finished:
            result = result.filter {
                progressService.getProgress(for: $0.id)?.isFinished ?? false
            }
        case .favorite:
            result = result.filter { $0.isFavorite }
        }

        // 搜索过滤
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.author ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        // 排序
        switch sortOption {
        case .byImportDate:
            result.sort { $0.importDate > $1.importDate }
        case .byTitle:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .byProgress:
            result.sort {
                let p1 = progressService.getProgress(for: $0.id)?.progress ?? 0
                let p2 = progressService.getProgress(for: $1.id)?.progress ?? 0
                return p1 > p2
            }
        case .byLastOpened:
            result.sort {
                let d1 = $0.lastOpenedDate ?? $0.importDate
                let d2 = $1.lastOpenedDate ?? $1.importDate
                return d1 > d2
            }
        case .byFileSize:
            result.sort { $0.fileSize > $1.fileSize }
        case .byRating:
            result.sort { $0.rating > $1.rating }
        }

        return result
    }

    /// 最近阅读的漫画
    var recentComics: [Comic] {
        let recentProgress = progressService.getRecentComics(limit: 6)
        return recentProgress.compactMap { progress in
            comics.first { $0.id == progress.comicID }
        }
    }

    /// 获取漫画的阅读进度
    func progress(for comic: Comic) -> ReadingProgress? {
        return progressService.getProgress(for: comic.id)
    }

    /// 获取封面图片
    func coverImage(for comic: Comic) -> UIImage? {
        return importService.coverImage(for: comic)
    }

    /// 获取书签
    func bookmarks(for comic: Comic) -> [Bookmark] {
        return progressService.getBookmarks(for: comic.id)
    }

    // MARK: - 更新漫画元数据

    /// 更新漫画元数据
    func updateComic(_ comic: Comic, title: String? = nil, author: String? = nil,
                     tags: [String]? = nil, collectionName: String? = nil) {
        guard let index = comics.firstIndex(where: { $0.id == comic.id }) else { return }
        var updated = comics[index]
        if let title = title, !title.isEmpty { updated.title = title }
        if let author = author { updated.author = author.isEmpty ? nil : author }
        if let tags = tags { updated.tags = tags }
        if let collectionName = collectionName {
            updated.collectionName = collectionName.isEmpty ? nil : collectionName
        }
        comics[index] = updated
        saveComics()
    }

    /// 更新漫画评分
    func updateRating(_ comic: Comic, rating: Int) {
        guard let index = comics.firstIndex(where: { $0.id == comic.id }) else { return }
        comics[index].rating = max(0, min(5, rating))
        saveComics()
    }

    /// 更新自定义封面
    func updateCustomCover(comic: Comic, path: String) {
        guard let index = comics.firstIndex(where: { $0.id == comic.id }) else { return }
        comics[index].customCoverPath = path
        saveComics()
    }

    // MARK: - 批量操作

    /// 批量删除
    func deleteComics(_ ids: [UUID]) {
        for id in ids {
            if let comic = comics.first(where: { $0.id == id }) {
                try? importService.deleteComic(comic)
                progressService.deleteProgress(for: id)
                progressService.deleteBookmarks(for: id)
            }
        }
        comics.removeAll { ids.contains($0.id) }
        saveComics()
    }

    /// 批量收藏/取消收藏
    func setFavorite(_ favorite: Bool, for ids: [UUID]) {
        for id in ids {
            if let index = comics.firstIndex(where: { $0.id == id }) {
                comics[index].isFavorite = favorite
            }
        }
        saveComics()
    }

    /// 批量移动到合集
    func setCollection(_ collection: String?, for ids: [UUID]) {
        for id in ids {
            if let index = comics.firstIndex(where: { $0.id == id }) {
                comics[index].collectionName = collection
            }
        }
        saveComics()
    }

    // MARK: - 拖拽排序

    /// 移动漫画位置（用于拖拽排序）
    func moveComic(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < comics.count,
              destinationIndex >= 0, destinationIndex < comics.count else { return }

        let comic = comics.remove(at: sourceIndex)
        comics.insert(comic, at: destinationIndex)

        // 更新所有漫画的 sortIndex
        for (index, _) in comics.enumerated() {
            comics[index].sortIndex = index
        }
        saveComics()
    }

    // MARK: - 自定义分类

    /// 所有自定义分类
    var allCategories: [String] {
        let categories = Set(comics.flatMap { $0.categories })
        return Array(categories).sorted()
    }

    /// 获取指定分类的漫画
    func comics(inCategory category: String) -> [Comic] {
        return comics.filter { $0.categories.contains(category) }
    }

    /// 添加漫画到分类
    func addComic(_ comic: Comic, to category: String) {
        guard let index = comics.firstIndex(where: { $0.id == comic.id }),
              !comics[index].categories.contains(category) else { return }
        comics[index].categories.append(category)
        saveComics()
    }

    /// 从分类移除漫画
    func removeComic(_ comic: Comic, from category: String) {
        guard let index = comics.firstIndex(where: { $0.id == comic.id }) else { return }
        comics[index].categories.removeAll { $0 == category }
        saveComics()
    }

    /// 删除分类（从所有漫画中移除）
    func deleteCategory(_ category: String) {
        for index in comics.indices {
            comics[index].categories.removeAll { $0 == category }
        }
        saveComics()
    }

    /// 重命名分类
    func renameCategory(_ oldName: String, to newName: String) {
        guard !newName.isEmpty, oldName != newName else { return }
        for index in comics.indices {
            if let catIndex = comics[index].categories.firstIndex(of: oldName) {
                comics[index].categories[catIndex] = newName
            }
        }
        saveComics()
    }

    // MARK: - 统计

    /// 总漫画数
    var totalComics: Int { comics.count }

    /// 已读完的漫画数
    var finishedComics: Int {
        comics.filter {
            progressService.getProgress(for: $0.id)?.isFinished ?? false
        }.count
    }

    /// 正在阅读的漫画数
    var readingComics: Int {
        comics.filter {
            guard let p = progressService.getProgress(for: $0.id) else { return false }
            return !p.isFinished && p.currentPage > 0
        }.count
    }

    /// 收藏数
    var favoriteComics: Int {
        comics.filter { $0.isFavorite }.count
    }

    /// 总文件大小
    var totalFileSize: Int64 {
        comics.reduce(0) { $0 + $1.fileSize }
    }

    var totalFileSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalFileSize, countStyle: .file)
    }
}

