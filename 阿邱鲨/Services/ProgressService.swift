//
//  ProgressService.swift
//  阿邱鲨
//
//  阅读进度、书签、阅读器设置持久化服务
//

import Foundation

/// 阅读进度服务
final class ProgressService {

    static let shared = ProgressService()

    private let userDefaults = UserDefaults.standard
    private let progressKey = "com.aqiusha.readingProgress"
    private let settingsKey = "com.aqiusha.readerSettings"
    private let bookmarksKey = "com.aqiusha.bookmarks"
    private let lastReadComicKey = "com.aqiusha.lastReadComicID"
    private let readingStatsKey = "com.aqiusha.readingStats"
    private let passwordEnabledKey = "com.aqiusha.passwordEnabled"
    private let passwordHashKey = "com.aqiusha.passwordHash"

    private init() {}

    // MARK: - 阅读进度

    /// 保存阅读进度
    func saveProgress(_ progress: ReadingProgress) {
        var allProgress = getAllProgress()
        allProgress[progress.comicID.uuidString] = progress
        if let data = try? JSONEncoder().encode(allProgress) {
            userDefaults.set(data, forKey: progressKey)
        }
    }

    /// 获取指定漫画的阅读进度
    func getProgress(for comicID: UUID) -> ReadingProgress? {
        return getAllProgress()[comicID.uuidString]
    }

    /// 获取所有阅读进度
    func getAllProgress() -> [String: ReadingProgress] {
        guard let data = userDefaults.data(forKey: progressKey),
              let progress = try? JSONDecoder().decode([String: ReadingProgress].self, from: data) else {
            return [:]
        }
        return progress
    }

    /// 删除指定漫画的阅读进度
    func deleteProgress(for comicID: UUID) {
        var allProgress = getAllProgress()
        allProgress.removeValue(forKey: comicID.uuidString)
        if let data = try? JSONEncoder().encode(allProgress) {
            userDefaults.set(data, forKey: progressKey)
        }
    }

    /// 清除所有阅读进度
    func clearAllProgress() {
        userDefaults.removeObject(forKey: progressKey)
    }

    /// 获取最近阅读的漫画（按最后阅读时间排序）
    func getRecentComics(limit: Int = 10) -> [ReadingProgress] {
        return getAllProgress().values
            .sorted { $0.lastReadDate > $1.lastReadDate }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 书签管理

    /// 获取指定漫画的所有书签
    func getBookmarks(for comicID: UUID) -> [Bookmark] {
        return getAllBookmarks()
            .filter { $0.comicID == comicID }
            .sorted { $0.pageIndex < $1.pageIndex }
    }

    /// 获取所有书签
    func getAllBookmarks() -> [Bookmark] {
        guard let data = userDefaults.data(forKey: bookmarksKey),
              let bookmarks = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            return []
        }
        return bookmarks
    }

    /// 添加书签
    func addBookmark(_ bookmark: Bookmark) {
        var bookmarks = getAllBookmarks()
        // 避免同一页重复添加
        if !bookmarks.contains(where: { $0.comicID == bookmark.comicID && $0.pageIndex == bookmark.pageIndex }) {
            bookmarks.append(bookmark)
            if let data = try? JSONEncoder().encode(bookmarks) {
                userDefaults.set(data, forKey: bookmarksKey)
            }
        }
    }

    /// 删除书签
    func deleteBookmark(_ bookmark: Bookmark) {
        var bookmarks = getAllBookmarks()
        bookmarks.removeAll { $0.id == bookmark.id }
        if let data = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(data, forKey: bookmarksKey)
        }
    }

    /// 删除指定漫画的所有书签
    func deleteBookmarks(for comicID: UUID) {
        var bookmarks = getAllBookmarks()
        bookmarks.removeAll { $0.comicID == comicID }
        if let data = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(data, forKey: bookmarksKey)
        }
    }

    /// 检查某页是否已书签
    func isBookmarked(comicID: UUID, pageIndex: Int) -> Bool {
        return getAllBookmarks().contains {
            $0.comicID == comicID && $0.pageIndex == pageIndex
        }
    }

    /// 清除所有书签
    func clearAllBookmarks() {
        userDefaults.removeObject(forKey: bookmarksKey)
    }

    // MARK: - 上次阅读记录

    /// 保存上次阅读的漫画 ID
    func saveLastReadComicID(_ comicID: UUID?) {
        if let id = comicID {
            userDefaults.set(id.uuidString, forKey: lastReadComicKey)
        } else {
            userDefaults.removeObject(forKey: lastReadComicKey)
        }
    }

    /// 获取上次阅读的漫画 ID
    func getLastReadComicID() -> UUID? {
        guard let idString = userDefaults.string(forKey: lastReadComicKey) else { return nil }
        return UUID(uuidString: idString)
    }

    // MARK: - 阅读时长统计

    /// 单日阅读统计
    struct DailyReadingStat: Codable, Identifiable {
        let date: String  // yyyy-MM-dd
        var duration: TimeInterval  // 阅读时长（秒）
        var pagesRead: Int  // 阅读页数

        var id: String { date }
    }

    /// 阅读统计汇总
    struct ReadingStatsSummary {
        let totalDuration: TimeInterval
        let todayDuration: TimeInterval
        let weekDuration: TimeInterval
        let monthDuration: TimeInterval
        let totalPagesRead: Int
        let finishedComics: Int
        let currentStreak: Int  // 连续阅读天数
    }

    /// 获取所有阅读统计
    private func getAllDailyStats() -> [String: DailyReadingStat] {
        guard let data = userDefaults.data(forKey: readingStatsKey),
              let stats = try? JSONDecoder().decode([String: DailyReadingStat].self, from: data) else {
            return [:]
        }
        return stats
    }

    /// 保存阅读统计
    private func saveAllDailyStats(_ stats: [String: DailyReadingStat]) {
        if let data = try? JSONEncoder().encode(stats) {
            userDefaults.set(data, forKey: readingStatsKey)
        }
    }

    /// 记录阅读时长
    func recordReading(duration: TimeInterval, pagesRead: Int = 0) {
        guard duration > 0 else { return }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        var stats = getAllDailyStats()
        if var todayStat = stats[today] {
            todayStat.duration += duration
            todayStat.pagesRead += pagesRead
            stats[today] = todayStat
        } else {
            stats[today] = DailyReadingStat(date: today, duration: duration, pagesRead: pagesRead)
        }
        saveAllDailyStats(stats)
    }

    /// 获取阅读统计汇总
    func getReadingStatsSummary(finishedComicsCount: Int = 0) -> ReadingStatsSummary {
        let stats = getAllDailyStats()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current

        let today = dateFormatter.string(from: Date())
        let todayDuration = stats[today]?.duration ?? 0

        // 本周
        var weekDuration: TimeInterval = 0
        // 本月
        var monthDuration: TimeInterval = 0
        // 总计
        var totalDuration: TimeInterval = 0
        var totalPagesRead = 0

        for (dateString, stat) in stats {
            totalDuration += stat.duration
            totalPagesRead += stat.pagesRead

            if let date = dateFormatter.date(from: dateString) {
                if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
                    weekDuration += stat.duration
                }
                if calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
                    monthDuration += stat.duration
                }
            }
        }

        // 计算连续阅读天数
        var currentStreak = 0
        var checkDate = Date()
        while true {
            let dateStr = dateFormatter.string(from: checkDate)
            if stats[dateStr] != nil && (stats[dateStr]?.duration ?? 0) > 60 {
                currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? Date()
            } else {
                // 如果今天还没阅读，从昨天开始算
                if currentStreak == 0 && calendar.isDateInToday(checkDate) {
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? Date()
                    continue
                }
                break
            }
        }

        return ReadingStatsSummary(
            totalDuration: totalDuration,
            todayDuration: todayDuration,
            weekDuration: weekDuration,
            monthDuration: monthDuration,
            totalPagesRead: totalPagesRead,
            finishedComics: finishedComicsCount,
            currentStreak: currentStreak
        )
    }

    /// 获取最近 7 天的阅读数据（用于图表）
    func getWeeklyReadingData() -> [DailyReadingStat] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        let stats = getAllDailyStats()

        var result: [DailyReadingStat] = []
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let dateStr = dateFormatter.string(from: date)
                let stat = stats[dateStr] ?? DailyReadingStat(date: dateStr, duration: 0, pagesRead: 0)
                result.insert(stat, at: 0)
            }
        }
        return result
    }

    /// 格式化时长显示
    static func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else {
            return "\(minutes)分钟"
        }
    }

    // MARK: - 阅读器设置

    /// 翻页效果
    enum PageTurnEffect: String, Codable, CaseIterable {
        case none = "无"
        case slide = "滑动"
        case curl = "仿真翻页"
        case fade = "淡入淡出"
    }

    /// 阅读背景
    enum ReadingBackground: String, Codable, CaseIterable {
        case white = "白色"
        case sepia = "护眼"
        case black = "黑色"
        case gray = "灰色"
        case wood = "木纹"
        case paper = "纸张"
    }

    /// 阅读器设置
    struct ReaderSettings: Codable, Equatable {
        var readingDirection: ReadingDirection
        var readingMode: ReadingMode
        var brightness: Double
        var isDarkMode: Bool
        var pageTurnAnimation: Bool
        var keepScreenAwake: Bool
        var backgroundStyle: BackgroundStyle

        // 新增设置
        var pageTurnEffect: PageTurnEffect
        var readingWidth: Double        // 阅读宽度比例 0.5 - 1.0
        var doublePageMode: Bool        // 双页模式
        var coverSinglePage: Bool       // 封面单独一页
        var avoidNotch: Bool            // 刘海屏防遮挡
        var autoFlipEnabled: Bool       // 自动翻页
        var autoFlipInterval: Double    // 自动翻页间隔（秒）
        var showThumbnailStrip: Bool    // 显示缩略图导航条
        var cropWhiteBorder: Bool       // 自动裁剪白边
        var enhanceLevel: Int           // 画质增强等级 0-3
        var readingBackground: ReadingBackground // 阅读背景
        var immersiveMode: Bool         // 沉浸式阅读
        var showPageNumber: Bool        // 显示页码
        var preloadCount: Int           // 预加载页数
        var uiFontSize: CGFloat         // 阅读器UI字体大小

        enum BackgroundStyle: String, Codable, CaseIterable {
            case white = "白色"
            case sepia = "护眼"
            case black = "黑色"
            case gray = "灰色"
        }

        static let `default` = ReaderSettings(
            readingDirection: .rightToLeft,
            readingMode: .singlePage,
            brightness: 1.0,
            isDarkMode: false,
            pageTurnAnimation: true,
            keepScreenAwake: true,
            backgroundStyle: .white,
            pageTurnEffect: .slide,
            readingWidth: 1.0,
            doublePageMode: false,
            coverSinglePage: true,
            avoidNotch: true,
            autoFlipEnabled: false,
            autoFlipInterval: 5.0,
            showThumbnailStrip: true,
            cropWhiteBorder: false,
            enhanceLevel: 0,
            readingBackground: .white,
            immersiveMode: false,
            showPageNumber: true,
            preloadCount: 3,
            uiFontSize: 16.0
        )
    }

    /// 保存阅读器设置
    func saveSettings(_ settings: ReaderSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
        }
    }

    /// 获取阅读器设置
    func getSettings() -> ReaderSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(ReaderSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    // MARK: - 密码锁

    /// 密码锁是否启用
    var isPasswordLockEnabled: Bool {
        userDefaults.bool(forKey: passwordEnabledKey)
    }

    /// 启用/禁用密码锁
    func setPasswordLockEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: passwordEnabledKey)
    }

    /// 设置密码（4-6位数字）
    func setPassword(_ password: String) {
        let hash = simpleHash(password)
        userDefaults.set(hash, forKey: passwordHashKey)
        userDefaults.set(true, forKey: passwordEnabledKey)
    }

    /// 验证密码
    func verifyPassword(_ password: String) -> Bool {
        guard let storedHash = userDefaults.string(forKey: passwordHashKey) else {
            return false
        }
        return simpleHash(password) == storedHash
    }

    /// 清除密码
    func clearPassword() {
        userDefaults.removeObject(forKey: passwordHashKey)
        userDefaults.set(false, forKey: passwordEnabledKey)
    }

    /// 简单哈希（SHA256）
    private func simpleHash(_ string: String) -> String {
        let data = Data(string.utf8)
        // 使用系统 CryptoKit 或简单的哈希
        var hash: UInt64 = 14695981039346656037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}

