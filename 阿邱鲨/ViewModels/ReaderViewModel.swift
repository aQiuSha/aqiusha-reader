//
//  ReaderViewModel.swift
//  阿邱鲨
//
//  阅读器视图模型：预加载、画质增强、裁剪白边、连续阅读
//

import Foundation
import UIKit
import PDFKit
import Combine

/// 阅读器视图模型
@MainActor
final class ReaderViewModel: ObservableObject {

    @Published var pages: [ComicPage] = []
    @Published var currentPageIndex: Int = 0
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var showCatalog = false
    @Published var showBookmarks = false
    @Published var isDarkMode: Bool
    @Published var brightness: Double
    @Published var readingDirection: ReadingDirection
    @Published var readingMode: ReadingMode
    @Published var isCurrentPageBookmarked = false
    @Published var autoFlipEnabled = false
    @Published var autoFlipInterval: Double = 5.0
    @Published var pageTurnEffect: ProgressService.PageTurnEffect
    @Published var readingWidth: Double
    @Published var doublePageMode: Bool
    @Published var coverSinglePage: Bool
    @Published var avoidNotch: Bool
    @Published var showThumbnailStrip: Bool
    @Published var cropWhiteBorder: Bool
    @Published var enhanceLevel: Int
    @Published var readingBackground: ProgressService.ReadingBackground
    @Published var immersiveMode: Bool
    @Published var showPageNumber: Bool
    @Published var isLongStripComic = false  // 自动检测为条漫
    @Published var rotation: Double = 0  // 图片旋转角度（0/90/180/270）
    @Published var panelModeEnabled = false  // 分镜模式
    @Published var currentPanelIndex: Int = 0  // 当前分镜索引
    @Published var detectedPanels: [ImageEnhancer.ComicPanel] = []  // 当前页检测到的分镜

    let comic: Comic
    private let importService = ComicImportService.shared
    private let progressService = ProgressService.shared
    private let imageEnhancer = ImageEnhancer.shared
    private var pdfDocument: PDFDocument?
    private var autoFlipTimer: Timer?

    // 图片缓存
    private var imageCache = NSCache<NSNumber, UIImage>()
    private var preloadTask: Task<Void, Never>?
    private var memoryWarningObserver: NSObjectProtocol?

    init(comic: Comic) {
        self.comic = comic
        let settings = ProgressService.shared.getSettings()
        self.isDarkMode = settings.isDarkMode
        self.brightness = settings.brightness
        self.readingDirection = settings.readingDirection
        self.readingMode = settings.readingMode
        self.pageTurnEffect = settings.pageTurnEffect
        self.readingWidth = settings.readingWidth
        self.doublePageMode = settings.doublePageMode
        self.coverSinglePage = settings.coverSinglePage
        self.avoidNotch = settings.avoidNotch
        self.showThumbnailStrip = settings.showThumbnailStrip
        self.autoFlipEnabled = settings.autoFlipEnabled
        self.autoFlipInterval = settings.autoFlipInterval
        self.cropWhiteBorder = false
        self.enhanceLevel = 0
        self.readingBackground = settings.readingBackground
        self.immersiveMode = settings.immersiveMode
        self.showPageNumber = settings.showPageNumber

        // 配置缓存限制
        imageCache.countLimit = 50
        imageCache.totalCostLimit = 100 * 1024 * 1024  // 100MB

        // 监听内存警告
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    /// 处理内存警告
    private func handleMemoryWarning() {
        imageCache.removeAllObjects()
        preloadTask?.cancel()
        pdfDocument = nil
    }

    // MARK: - 页面加载

    /// 加载漫画页面
    func loadPages() {
        isLoading = true
        errorMessage = nil

        // 直接在主线程加载，避免并发崩溃
        let loadedPages = self.importService.pages(for: self.comic)
        self.pages = loadedPages

        if let progress = self.progressService.getProgress(for: self.comic.id) {
            self.currentPageIndex = min(progress.currentPage, max(loadedPages.count - 1, 0))
        }

        // 自动检测条漫
        self.detectLongStrip()

        self.updateBookmarkState()
        self.isLoading = false

        // 预加载当前页附近的图片
        self.preloadImages(around: self.currentPageIndex)

        // 记录上次阅读
        self.progressService.saveLastReadComicID(self.comic.id)
    }

    /// 自动检测是否为条漫
    private func detectLongStrip() {
        // PDF格式不需要检测条漫，直接跳过，避免内存暴涨闪退
        guard comic.format != .pdf else {
            isLongStripComic = false
            return
        }

        // 采样前几页检测
        let sampleCount = min(3, pages.count)
        var longCount = 0
        for i in 0..<sampleCount {
            if let image = rawImageForPage(at: i) {
                if image.size.height / max(image.size.width, 1) > 1.5 {
                    longCount += 1
                }
            }
        }
        isLongStripComic = sampleCount > 0 && Double(longCount) / Double(sampleCount) > 0.6
    }

    // MARK: - 图片获取（含增强和裁剪）

    /// 获取处理后的图片（裁剪白边 + 画质增强）
    func imageForPage(at index: Int) -> UIImage? {
        guard index >= 0 && index < pages.count else { return nil }

        // 先查缓存
        if let cached = imageCache.object(forKey: NSNumber(value: index)) {
            return cached
        }

        guard let rawImage = rawImageForPage(at: index) else { return nil }

        var result = rawImage
        let cacheKey = "\(comic.id.uuidString)_\(index)"

        // 裁剪白边
        if cropWhiteBorder {
            result = imageEnhancer.cropWhiteBorder(result, cacheKey: "crop_\(cacheKey)")
        }

        // 画质增强
        if let level = ImageEnhancer.EnhanceLevel(rawValue: enhanceLevel), level != .off {
            result = imageEnhancer.enhance(result, level: level, cacheKey: "enhance_\(cacheKey)")
        }

        // 存入缓存
        imageCache.setObject(result, forKey: NSNumber(value: index))
        return result
    }

    /// 获取原始图片（不处理）
    private func rawImageForPage(at index: Int) -> UIImage? {
        guard index >= 0 && index < pages.count else { return nil }
        let page = pages[index]

        if comic.format == .pdf {
            return pdfPageImage(at: index)
        }

        guard let image = UIImage(contentsOfFile: page.imageURL.path) else { return nil }
        return downsampleIfNeeded(image)
    }

    /// 大图 downsampling，超过 4096 像素的图片缩放到合适大小
    private func downsampleIfNeeded(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 4096
        let width = image.size.width
        let height = image.size.height

        guard width > maxDimension || height > maxDimension else {
            return image
        }

        let scale = min(maxDimension / width, maxDimension / height)
        let newSize = CGSize(width: width * scale, height: height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 获取缩略图
    func thumbnailForPage(at index: Int) -> UIImage? {
        guard let fullImage = rawImageForPage(at: index) else { return nil }
        let targetSize = CGSize(width: 80, height: 120)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            fullImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    // MARK: - 预加载

    /// 预加载当前页附近的图片
    func preloadImages(around index: Int) {
        preloadTask?.cancel()

        let settings = progressService.getSettings()
        let preloadCount = 0

        preloadTask = Task {
            // 预加载前后各 preloadCount 页
            var indicesToLoad: [Int] = []
            for offset in 1...preloadCount {
                if index + offset < pages.count {
                    indicesToLoad.append(index + offset)
                }
                if index - offset >= 0 {
                    indicesToLoad.append(index - offset)
                }
            }

            for idx in indicesToLoad {
                if Task.isCancelled { break }
                _ = imageForPage(at: idx)
            }
        }
    }

    // MARK: - PDF 渲染

    private func pdfPageImage(at index: Int) -> UIImage? {
        if pdfDocument == nil {
            pdfDocument = PDFDocument(url: comic.sourceURL)
        }

        guard let document = pdfDocument,
              let page = document.page(at: index) else {
            return nil
        }

        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        ))

        return renderer.image { ctx in
            ctx.cgContext.scaleBy(x: scale, y: scale)
            UIColor.white.setFill()
            ctx.fill(pageRect)
            ctx.cgContext.translateBy(x: 0, y: pageRect.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    // MARK: - 翻页

    /// 下一页
    func nextPage() {
        let targetIndex: Int
        switch readingDirection {
        case .rightToLeft:
            targetIndex = currentPageIndex - 1
        case .leftToRight, .topToBottom:
            targetIndex = currentPageIndex + 1
        }

        if targetIndex >= 0 && targetIndex < pages.count {
            currentPageIndex = targetIndex
            updateBookmarkState()
            saveProgress()
            preloadImages(around: targetIndex)
        } else {
            stopAutoFlip()
        }
    }

    /// 上一页
    func previousPage() {
        let targetIndex: Int
        switch readingDirection {
        case .rightToLeft:
            targetIndex = currentPageIndex + 1
        case .leftToRight, .topToBottom:
            targetIndex = currentPageIndex - 1
        }

        if targetIndex >= 0 && targetIndex < pages.count {
            currentPageIndex = targetIndex
            updateBookmarkState()
            saveProgress()
            preloadImages(around: targetIndex)
        }
    }

    /// 跳转到指定页
    func goToPage(_ index: Int) {
        guard index >= 0 && index < pages.count else { return }
        currentPageIndex = index
        updateBookmarkState()
        saveProgress()
        preloadImages(around: index)
    }

    func goToFirstPage() {
        currentPageIndex = readingDirection == .rightToLeft ? pages.count - 1 : 0
        updateBookmarkState()
        saveProgress()
        preloadImages(around: currentPageIndex)
    }

    func goToLastPage() {
        currentPageIndex = readingDirection == .rightToLeft ? 0 : pages.count - 1
        updateBookmarkState()
        saveProgress()
        preloadImages(around: currentPageIndex)
    }

    // MARK: - 自动翻页

    func startAutoFlip() {
        stopAutoFlip()
        autoFlipEnabled = true
        let interval = progressService.getSettings().autoFlipInterval
        autoFlipTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.nextPage()
            }
        }
    }

    func stopAutoFlip() {
        autoFlipTimer?.invalidate()
        autoFlipTimer = nil
        autoFlipEnabled = false
    }

    func toggleAutoFlip() {
        if autoFlipEnabled {
            stopAutoFlip()
        } else {
            startAutoFlip()
        }
    }

    // MARK: - 书签

    var bookmarks: [Bookmark] {
        progressService.getBookmarks(for: comic.id)
    }

    private func updateBookmarkState() {
        isCurrentPageBookmarked = progressService.isBookmarked(
            comicID: comic.id,
            pageIndex: currentPageIndex
        )
    }

    func toggleCurrentPageBookmark() {
        if isCurrentPageBookmarked {
            if let bookmark = bookmarks.first(where: { $0.pageIndex == currentPageIndex }) {
                progressService.deleteBookmark(bookmark)
            }
        } else {
            let thumbnail = thumbnailForPage(at: currentPageIndex)
            let bookmark = Bookmark(
                comicID: comic.id,
                pageIndex: currentPageIndex,
                name: "第 \(currentPageIndex + 1) 页",
                thumbnailData: thumbnail?.pngData()
            )
            progressService.addBookmark(bookmark)
        }
        updateBookmarkState()
    }

    func goToBookmark(_ bookmark: Bookmark) {
        goToPage(bookmark.pageIndex)
        showBookmarks = false
    }

    // MARK: - 进度保存

    func saveProgress() {
        let progress = ReadingProgress(
            comicID: comic.id,
            currentPage: currentPageIndex,
            totalPages: pages.count,
            lastReadDate: Date(),
            isFinished: currentPageIndex >= pages.count - 1
        )
        progressService.saveProgress(progress)
        progressService.saveLastReadComicID(comic.id)
    }

    // MARK: - 设置

    func saveSettings() {
        let current = progressService.getSettings()
        let settings = ProgressService.ReaderSettings(
            readingDirection: readingDirection,
            readingMode: readingMode,
            brightness: brightness,
            isDarkMode: isDarkMode,
            pageTurnAnimation: current.pageTurnAnimation,
            keepScreenAwake: current.keepScreenAwake,
            backgroundStyle: isDarkMode ? .black : .white,
            pageTurnEffect: pageTurnEffect,
            readingWidth: readingWidth,
            doublePageMode: doublePageMode,
            coverSinglePage: coverSinglePage,
            avoidNotch: avoidNotch,
            autoFlipEnabled: autoFlipEnabled,
            autoFlipInterval: autoFlipInterval,
            showThumbnailStrip: showThumbnailStrip,
            cropWhiteBorder: cropWhiteBorder,
            enhanceLevel: enhanceLevel,
            readingBackground: readingBackground,
            immersiveMode: immersiveMode,
            showPageNumber: showPageNumber,
            preloadCount: current.preloadCount,
            uiFontSize: current.uiFontSize
        )
        progressService.saveSettings(settings)

        // 清除图片缓存（设置变化后需要重新处理）
        imageCache.removeAllObjects()
    }

    func toggleReadingDirection() {
        switch readingDirection {
        case .rightToLeft:
            readingDirection = .leftToRight
        case .leftToRight:
            readingDirection = .rightToLeft
        case .topToBottom:
            readingDirection = .rightToLeft
        }
        saveSettings()
    }

    /// 旋转图片90度（顺时针）
    func rotateImage() {
        rotation = (rotation + 90).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - 分镜模式

    /// 检测当前页的分镜
    func detectPanelsForCurrentPage() {
        guard let image = imageForPage(at: currentPageIndex) else {
            detectedPanels = []
            return
        }
        detectedPanels = imageEnhancer.detectPanels(image)
        currentPanelIndex = 0
    }

    /// 切换到下一个分镜
    func nextPanel() {
        guard panelModeEnabled, !detectedPanels.isEmpty else { return }
        if currentPanelIndex < detectedPanels.count - 1 {
            currentPanelIndex += 1
        } else {
            // 最后一个分镜，翻到下一页
            nextPage()
            detectPanelsForCurrentPage()
        }
    }

    /// 切换到上一个分镜
    func previousPanel() {
        guard panelModeEnabled, !detectedPanels.isEmpty else { return }
        if currentPanelIndex > 0 {
            currentPanelIndex -= 1
        } else {
            // 第一个分镜，翻到上一页
            previousPage()
            detectPanelsForCurrentPage()
            if !detectedPanels.isEmpty {
                currentPanelIndex = detectedPanels.count - 1
            }
        }
    }

    /// 切换分镜模式
    func togglePanelMode() {
        panelModeEnabled.toggle()
        if panelModeEnabled {
            detectPanelsForCurrentPage()
        }
    }

    /// 获取当前分镜的裁剪图片
    func currentPanelImage() -> UIImage? {
        guard panelModeEnabled,
              !detectedPanels.isEmpty,
              currentPanelIndex < detectedPanels.count,
              let fullImage = imageForPage(at: currentPageIndex) else {
            return nil
        }

        let panel = detectedPanels[currentPanelIndex]
        let imageSize = fullImage.size
        let cropRect = CGRect(
            x: panel.rect.minX * imageSize.width,
            y: panel.rect.minY * imageSize.height,
            width: panel.rect.width * imageSize.width,
            height: panel.rect.height * imageSize.height
        )

        guard let cgImage = fullImage.cgImage?.cropping(to: cropRect) else {
            return fullImage
        }
        return UIImage(cgImage: cgImage, scale: fullImage.scale, orientation: fullImage.imageOrientation)
    }

    // MARK: - 计算属性

    var currentPageNumber: Int { currentPageIndex + 1 }
    var totalPages: Int { pages.count }

    var progressPercentage: String {
        guard pages.count > 0 else { return "0%" }
        let displayIndex = readingDirection == .rightToLeft ?
            (pages.count - 1 - currentPageIndex) : currentPageIndex
        return String(format: "%.0f%%", Double(displayIndex + 1) / Double(pages.count) * 100)
    }

    var isFirstPage: Bool {
        switch readingDirection {
        case .rightToLeft:
            return currentPageIndex == pages.count - 1
        case .leftToRight, .topToBottom:
            return currentPageIndex == 0
        }
    }

    var isLastPage: Bool {
        switch readingDirection {
        case .rightToLeft:
            return currentPageIndex == 0
        case .leftToRight, .topToBottom:
            return currentPageIndex == pages.count - 1
        }
    }

    var backgroundColor: UIColor {
        switch readingBackground {
        case .white: return .white
        case .sepia: return UIColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1.0)
        case .black: return .black
        case .gray: return UIColor(white: 0.9, alpha: 1.0)
        case .wood: return UIColor(red: 0.76, green: 0.63, blue: 0.48, alpha: 1.0)
        case .paper: return UIColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1.0)
        }
    }

    /// 双页模式下当前显示的左页索引（nil 表示当前页单独显示）
    var leftPageIndex: Int? {
        guard doublePageMode else { return nil }
        // 封面单独一页：第一页单独显示
        if coverSinglePage && currentPageIndex == 0 {
            return nil
        }
        // 右到左阅读：当前页是右页，左页是下一页
        if readingDirection == .rightToLeft {
            let left = currentPageIndex + 1
            return left < pages.count ? left : nil
        }
        // 左到右：当前页是左页
        return currentPageIndex
    }

    /// 双页模式下当前显示的右页索引
    var rightPageIndex: Int? {
        guard doublePageMode else { return nil }
        if coverSinglePage && currentPageIndex == 0 {
            return nil
        }
        if readingDirection == .rightToLeft {
            return currentPageIndex
        }
        let right = currentPageIndex + 1
        return right < pages.count ? right : nil
    }

    deinit {
        autoFlipTimer?.invalidate()
        preloadTask?.cancel()
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
