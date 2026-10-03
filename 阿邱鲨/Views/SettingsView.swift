//
//  SettingsView.swift
//  阿邱鲨
//
//  设置页面
//

import SwiftUI
import MessageUI

struct SettingsView: View {

    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @State private var showClearProgressAlert = false
    @State private var showAbout = false
    @State private var showSetPassword = false
    @State private var passwordLockEnabled = ProgressService.shared.isPasswordLockEnabled
    @State private var webSharingEnabled = false
    @State private var webSharingStatus = "未启动"
    @State private var webSharingURL = ""

    private var settings: ProgressService.ReaderSettings {
        ProgressService.shared.getSettings()
    }

    var body: some View {
        List {
            // 阅读设置
            Section {
                NavigationLink {
                    ReadingSettingsView()
                } label: {
                    Label("阅读设置", systemImage: "book.pages")
                }
            } header: {
                Text("阅读")
            }

            // 书架统计
            Section {
                HStack {
                    Label("漫画总数", systemImage: "books.vertical")
                    Spacer()
                    Text("\(libraryViewModel.totalComics) 本")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("正在阅读", systemImage: "clock")
                    Spacer()
                    Text("\(libraryViewModel.readingComics) 本")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("已读完", systemImage: "checkmark.circle")
                    Spacer()
                    Text("\(libraryViewModel.finishedComics) 本")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("收藏", systemImage: "star.fill")
                    Spacer()
                    Text("\(libraryViewModel.favoriteComics) 本")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("占用空间", systemImage: "internaldrive")
                    Spacer()
                    Text(libraryViewModel.totalFileSizeText)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("书架统计")
            }

            // 阅读统计
            Section {
                let stats = ProgressService.shared.getReadingStatsSummary(
                    finishedComicsCount: libraryViewModel.finishedComics
                )

                HStack {
                    Label("总阅读时长", systemImage: "hourglass")
                    Spacer()
                    Text(ProgressService.formatDuration(stats.totalDuration))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("今日阅读", systemImage: "sun.max")
                    Spacer()
                    Text(ProgressService.formatDuration(stats.todayDuration))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("本周阅读", systemImage: "calendar")
                    Spacer()
                    Text(ProgressService.formatDuration(stats.weekDuration))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("连续阅读", systemImage: "flame")
                    Spacer()
                    Text("\(stats.currentStreak) 天")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("累计阅读页数", systemImage: "doc.on.doc")
                    Spacer()
                    Text("\(stats.totalPagesRead) 页")
                        .foregroundColor(.secondary)
                }

                // 最近 7 天阅读趋势
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近 7 天")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    WeeklyReadingChart()
                        .frame(height: 60)
                }
                .padding(.vertical, 8)
            } header: {
                Text("阅读统计")
            }

            // 隐私与安全
            Section {
                Toggle(isOn: $passwordLockEnabled) {
                    Label("启动密码锁", systemImage: "lock.shield")
                }
                .onChange(of: passwordLockEnabled) { newValue in
                    if newValue {
                        // 启用密码锁时需要先设置密码
                        showSetPassword = true
                    } else {
                        ProgressService.shared.clearPassword()
                    }
                }

                if passwordLockEnabled {
                    Button {
                        showSetPassword = true
                    } label: {
                        Label("修改密码", systemImage: "key")
                    }
                }
            } header: {
                Text("隐私与安全")
            } footer: {
                Text(passwordLockEnabled ? "启动 App 时需要输入密码或使用 Face ID 解锁" : "启用后启动 App 需要验证身份")
            }

            // 局域网共享
            Section {
                Toggle(isOn: $webSharingEnabled) {
                    Label("局域网传输", systemImage: "wifi.circle")
                }
                .onChange(of: webSharingEnabled) { newValue in
                    if newValue {
                        startWebSharing()
                    } else {
                        stopWebSharing()
                    }
                }

                if webSharingEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.blue)
                            Text("在电脑浏览器访问：")
                                .font(.subheadline)
                            Spacer()
                        }

                        Text(webSharingURL)
                            .font(.headline)
                            .foregroundColor(.blue)
                            .textSelection(.enabled)

                        Text(webSharingStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("确保手机和电脑连接同一 Wi-Fi 网络")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("局域网共享")
            } footer: {
                Text("通过浏览器拖拽文件到手机，无需数据线")
            }

            // 数据管理
            Section {
                Button(role: .destructive) {
                    showClearProgressAlert = true
                } label: {
                    Label("清除所有阅读进度", systemImage: "clock.arrow.circlepath")
                        .foregroundColor(.red)
                }

                Button(role: .destructive) {
                    ProgressService.shared.clearAllBookmarks()
                } label: {
                    Label("清除所有书签", systemImage: "bookmark.slash")
                        .foregroundColor(.red)
                }
            } header: {
                Text("数据管理")
            } footer: {
                Text("清除后阅读进度和书签将重置，漫画文件不会被删除。")
            }

            // 支持格式
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("支持格式")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        FormatBadge(text: "CBZ", color: .blue)
                        FormatBadge(text: "CBR", color: .purple)
                        FormatBadge(text: "PDF", color: .red)
                        FormatBadge(text: "EPUB", color: .green)
                        FormatBadge(text: "图片", color: .orange)
                        FormatBadge(text: "文件夹", color: .gray)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("格式支持")
            }

            // 关于
            Section {
                Button {
                    showAbout = true
                } label: {
                    HStack {
                        Label("关于阿邱鲨", systemImage: "info.circle")
                        Spacer()
                        Text("v1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("关于")
            }
        }
        .navigationTitle("设置")
        .alert("确认清除", isPresented: $showClearProgressAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                ProgressService.shared.clearAllProgress()
            }
        } message: {
            Text("确定要清除所有漫画的阅读进度吗？此操作不可撤销。")
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(isPresented: $showSetPassword) {
            SetPasswordView { password in
                ProgressService.shared.setPassword(password)
                passwordLockEnabled = true
                showSetPassword = false
            } onCancel: {
                showSetPassword = false
                // 如果是第一次启用但取消了，保持关闭
                if !ProgressService.shared.isPasswordLockEnabled {
                    passwordLockEnabled = false
                }
            }
        }
    }

    // MARK: - 局域网共享

    private func startWebSharing() {
        let service = WebSharingService.shared
        service.statusUpdate = { status in
            webSharingStatus = status
        }
        service.onFileReceived = { url in
            Task { @MainActor in
                // 导入收到的文件
                let libraryVM = LibraryViewModel()
                _ = try? await libraryVM.importComic(from: url)
            }
        }
        service.start(port: 8080)

        if let ip = service.getIPAddress() {
            webSharingURL = "http://\(ip):8080"
            webSharingStatus = "服务已启动"
        } else {
            webSharingURL = "http://localhost:8080"
            webSharingStatus = "无法获取 IP，请检查 Wi-Fi 连接"
        }
    }

    private func stopWebSharing() {
        WebSharingService.shared.stop()
        webSharingStatus = "已停止"
        webSharingURL = ""
    }
}

// MARK: - 阅读设置详情

struct ReadingSettingsView: View {

    @State private var settings = ProgressService.shared.getSettings()

    var body: some View {
        List {
            Section {
                Picker("默认阅读方向", selection: $settings.readingDirection) {
                    ForEach(ReadingDirection.allCases, id: \.self) { dir in
                        Text(dir.displayName).tag(dir)
                    }
                }

                Picker("默认阅读模式", selection: $settings.readingMode) {
                    ForEach(ReadingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("翻页效果", selection: $settings.pageTurnEffect) {
                    ForEach(ProgressService.PageTurnEffect.allCases, id: \.self) { effect in
                        Text(effect.rawValue).tag(effect)
                    }
                }
            } header: {
                Text("阅读偏好")
            }

            Section {
                Picker("画质增强", selection: $settings.enhanceLevel) {
                    ForEach(0..<4) { level in
                        Text(ImageEnhancer.EnhanceLevel(rawValue: level)?.displayName ?? "")
                            .tag(level)
                    }
                }

                Toggle("自动裁剪白边", isOn: $settings.cropWhiteBorder)

                VStack(alignment: .leading) {
                    Text("预加载页数")
                    Picker("预加载页数", selection: $settings.preloadCount) {
                        Text("1 页").tag(1)
                        Text("3 页").tag(3)
                        Text("5 页").tag(5)
                        Text("8 页").tag(8)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            } header: {
                Text("画质与性能")
            }

            Section {
                Toggle("翻页动画", isOn: $settings.pageTurnAnimation)
                Toggle("保持屏幕常亮", isOn: $settings.keepScreenAwake)
                Toggle("缩略图导航条", isOn: $settings.showThumbnailStrip)
                Toggle("显示页码", isOn: $settings.showPageNumber)
                Toggle("沉浸式阅读", isOn: $settings.immersiveMode)
            } header: {
                Text("阅读体验")
            }

            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("阅读宽度")
                        Spacer()
                        Text("\(Int(settings.readingWidth * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.readingWidth, in: 0.5...1.0)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading) {
                    HStack {
                        Text("界面字体大小")
                        Spacer()
                        Text("\(Int(settings.uiFontSize))pt")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.uiFontSize, in: 12...24, step: 1)
                }
                .padding(.vertical, 4)

                Toggle("双页模式", isOn: $settings.doublePageMode)
                Toggle("封面单独一页", isOn: $settings.coverSinglePage)
                Toggle("刘海屏防遮挡", isOn: $settings.avoidNotch)
            } header: {
                Text("显示设置")
            }

            Section {
                Toggle("自动翻页", isOn: $settings.autoFlipEnabled)

                if settings.autoFlipEnabled {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("翻页间隔")
                            Spacer()
                            Text(String(format: "%.1f 秒", settings.autoFlipInterval))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.autoFlipInterval, in: 2.0...15.0, step: 0.5)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("自动翻页")
            }

            Section {
                Picker("阅读背景", selection: $settings.readingBackground) {
                    ForEach(ProgressService.ReadingBackground.allCases, id: \.self) { bg in
                        Text(bg.rawValue).tag(bg)
                    }
                }
                Toggle("夜间模式", isOn: $settings.isDarkMode)
            } header: {
                Text("外观")
            }
        }
        .navigationTitle("阅读设置")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings) { newValue in
            ProgressService.shared.saveSettings(newValue)
        }
    }
}

// MARK: - 周阅读图表

struct WeeklyReadingChart: View {
    private let weeklyData = ProgressService.shared.getWeeklyReadingData()

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(weeklyData) { stat in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(stat.duration > 0 ? Color.blue : Color.gray.opacity(0.2))
                            .frame(height: barHeight(for: stat.duration, in: geometry.size.height))
                        Text(dayLabel(for: stat.date))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func barHeight(for duration: TimeInterval, in totalHeight: CGFloat) -> CGFloat {
        let maxDuration = weeklyData.map { $0.duration }.max() ?? 1
        let ratio = maxDuration > 0 ? duration / maxDuration : 0
        return max(CGFloat(ratio) * (totalHeight - 20), 2)
    }

    private func dayLabel(for dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return "" }
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "E"
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        return weekdayFormatter.string(from: date)
    }
}

// MARK: - 格式徽章

struct FormatBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.8))
            .cornerRadius(4)
    }
}

// MARK: - 关于页面

struct AboutView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // App 图标
                Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)
                    .shadow(radius: 8)

                Text("阿邱鲨")
                    .font(.title.weight(.bold))

                Text("全格式漫画阅读器")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("版本 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                VStack(spacing: 12) {
                    Text("一只爱读漫画的小鲨鱼 🦈")
                        .font(.body)
                        .multilineTextAlignment(.center)

                    Text("支持 CBZ / CBR / PDF / EPUB / 图片等多种格式\n本地导入，隐私安全")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()

                Text("用 SwiftUI 精心打造")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 20)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(LibraryViewModel())
    }
}

