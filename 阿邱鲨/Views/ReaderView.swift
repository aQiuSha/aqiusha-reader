//
//  ReaderView.swift
//  阿邱鲨
//
//  漫画阅读器：仿真翻页、双页模式、连续阅读、沉浸式、画质增强
//

import SwiftUI
import UIKit

struct ReaderView: View {

    let comic: Comic
    @StateObject private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var showBars = true
    @State private var showSettingsPanel = false
    @State private var showCatalog = false
    @State private var showBookmarksPanel = false
    @State private var jumpPageText = ""
    @State private var showJumpDialog = false
    @State private var readingStartTime: Date?

    init(comic: Comic) {
        self.comic = comic
        _viewModel = StateObject(wrappedValue: ReaderViewModel(comic: comic))
    }

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 阅读背景
                backgroundView
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else if viewModel.pages.isEmpty {
                    errorView
                } else {
                    readerContent(in: geometry.size)
                }

                // 页码显示
                if viewModel.showPageNumber && !viewModel.isLoading && !viewModel.pages.isEmpty && showBars {
                    pageNumberOverlay
                }

                // 顶部工具栏
                if showBars && !viewModel.isLoading {
                    topBar
                }

                // 底部工具栏
                if showBars && !viewModel.isLoading && !viewModel.pages.isEmpty {
                    bottomBar(in: geometry.size)
                }

                // 设置面板
                if showSettingsPanel {
                    settingsPanel
                        .transition(.move(edge: .bottom))
                }

                // 目录面板
                if showCatalog {
                    catalogPanel
                        .transition(.move(edge: .leading))
                }

                // 书签面板
                if showBookmarksPanel {
                    bookmarksPanel
                        .transition(.move(edge: .trailing))
                }

                // 页码跳转对话框
                if showJumpDialog {
                    jumpDialog
                }

                // 分镜模式覆盖层
                if viewModel.panelModeEnabled && !viewModel.isLoading && !viewModel.pages.isEmpty {
                    panelModeOverlay
                }
            }
        }
        .statusBar(hidden: viewModel.immersiveMode || !showBars)
        .onAppear {
            viewModel.loadPages()
            UIApplication.shared.isIdleTimerDisabled = true
            readingStartTime = Date()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.stopAutoFlip()
            viewModel.saveProgress()
            // 记录阅读时长
            if let startTime = readingStartTime {
                let duration = Date().timeIntervalSince(startTime)
                ProgressService.shared.recordReading(duration: duration)
            }
        }
        .preferredColorScheme(viewModel.isDarkMode ? .dark : .light)
    }

    // MARK: - 阅读背景

    @ViewBuilder
    private var backgroundView: some View {
        switch viewModel.readingBackground {
        case .white:
            Color.white
        case .sepia:
            Color(red: 0.96, green: 0.92, blue: 0.84)
        case .black:
            Color.black
        case .gray:
            Color(white: 0.9)
        case .wood:
            // 木纹渐变
            LinearGradient(
                colors: [
                    Color(red: 0.76, green: 0.63, blue: 0.48),
                    Color(red: 0.68, green: 0.55, blue: 0.40),
                    Color(red: 0.72, green: 0.59, blue: 0.44)
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .paper:
            Color(red: 0.98, green: 0.97, blue: 0.93)
        }
    }

    // MARK: - 加载/错误

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在加载漫画...")
                .foregroundColor(viewModel.isDarkMode ? .white : .secondary)
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("无法加载漫画")
                .font(.headline)
            Text(viewModel.errorMessage ?? "未知错误")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("返回") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 阅读器内容

    @ViewBuilder
    private func readerContent(in size: CGSize) -> some View {
        // 条漫模式或连续阅读模式
        if viewModel.readingMode == .longStrip ||
           (viewModel.isLongStripComic && viewModel.readingMode == .singlePage) {
            continuousReader(in: size)
        }
        // 双页模式（横屏或手动开启）
        else if viewModel.doublePageMode && isLandscape {
            doublePageReader(in: size)
        }
        // 单页模式
        else {
            singlePageReader(in: size)
        }
    }

    // MARK: - 单页模式（支持仿真翻页）

    private func singlePageReader(in size: CGSize) -> some View {
        PageTurnViewController(
            pages: viewModel.pages,
            currentIndex: $viewModel.currentPageIndex,
            pageTurnEffect: viewModel.pageTurnEffect,
            rotation: viewModel.rotation,
            imageProvider: { index in
                viewModel.imageForPage(at: index)
            },
            onPageChanged: { newIndex in
                viewModel.goToPage(newIndex)
            },
            onTap: { location in
                handleTap(at: location, in: size)
            }
        )
        .ignoresSafeArea()
    }

    // MARK: - 双页模式

    private func doublePageReader(in size: CGSize) -> some View {
        HStack(spacing: 0) {
            // 左页
            if let leftIndex = viewModel.leftPageIndex {
                ZoomableImageView(
                    image: viewModel.imageForPage(at: leftIndex),
                    isDarkMode: viewModel.isDarkMode,
                    readingWidth: 1.0
                )
                .rotationEffect(.degrees(viewModel.rotation))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }

            // 中间分割线
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .frame(width: 1)

            // 右页
            if let rightIndex = viewModel.rightPageIndex {
                ZoomableImageView(
                    image: viewModel.imageForPage(at: rightIndex),
                    isDarkMode: viewModel.isDarkMode,
                    readingWidth: 1.0
                )
                .rotationEffect(.degrees(viewModel.rotation))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            handleTap(at: location, in: size)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: viewModel.rotation)
    }

    // MARK: - 连续阅读（条漫）

    private func continuousReader(in size: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.pages) { page in
                        if let image = viewModel.imageForPage(at: page.index) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .rotationEffect(.degrees(viewModel.rotation))
                                .id(page.index)
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation { showBars.toggle() }
            }
            .onAppear {
                // 滚动到当前页
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        proxy.scrollTo(viewModel.currentPageIndex, anchor: .top)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.rotation)
        }
    }

    // MARK: - 点击处理

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let leftZone = size.width * 0.3
        let rightZone = size.width * 0.7

        if location.x < leftZone {
            withAnimation { viewModel.previousPage() }
        } else if location.x > rightZone {
            withAnimation { viewModel.nextPage() }
        } else {
            withAnimation { showBars.toggle() }
        }
    }

    // MARK: - 页码覆盖层

    private var pageNumberOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    jumpPageText = "\(viewModel.currentPageNumber)"
                    showJumpDialog = true
                } label: {
                    Text("\(viewModel.currentPageNumber) / \(viewModel.totalPages)")
                        .font(.caption)
                        .foregroundColor(viewModel.isDarkMode ? .white.opacity(0.7) : .black.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(viewModel.isDarkMode ? 0.4 : 0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(viewModel.isDarkMode ? .white : .black)
                        .frame(width: 40, height: 40)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Circle())
                }

                Text(comic.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(viewModel.isDarkMode ? .white : .black)
                    .frame(maxWidth: .infinity)

                Button {
                    viewModel.toggleCurrentPageBookmark()
                } label: {
                    Image(systemName: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                        .foregroundColor(viewModel.isCurrentPageBookmarked ? .yellow :
                            (viewModel.isDarkMode ? .white : .black))
                        .frame(width: 40, height: 40)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Circle())
                }

                Button {
                    withAnimation { showCatalog = true }
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title3)
                        .foregroundColor(viewModel.isDarkMode ? .white : .black)
                        .frame(width: 40, height: 40)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(
                (viewModel.isDarkMode ? Color.black : Color.white)
                    .opacity(0.92)
                    .background(.ultraThinMaterial)
            )

            Spacer()
        }
        .transition(.move(edge: .top))
    }

    // MARK: - 底部栏

    private func bottomBar(in size: CGSize) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 10) {
                // 缩略图导航条
                if viewModel.showThumbnailStrip {
                    thumbnailStrip
                }

                // 进度条
                HStack(spacing: 12) {
                    Text("\(viewModel.currentPageNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.currentPageIndex) },
                            set: { viewModel.goToPage(Int($0)) }
                        ),
                        in: 0...Double(max(viewModel.pages.count - 1, 0))
                    )
                    .tint(.blue)

                    Text("\(viewModel.totalPages)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                }

                // 功能按钮
                HStack(spacing: 0) {
                    bottomButton(icon: "backward.end.fill", label: "首页") {
                        viewModel.goToFirstPage()
                    }

                    Spacer()

                    bottomButton(
                        icon: viewModel.readingDirection == .rightToLeft ? "arrow.right" : "arrow.left",
                        label: viewModel.readingDirection.displayName
                    ) {
                        viewModel.toggleReadingDirection()
                    }

                    Spacer()

                    bottomButton(
                        icon: viewModel.isDarkMode ? "moon.fill" : "sun.max.fill",
                        label: viewModel.isDarkMode ? "夜间" : "日间"
                    ) {
                        viewModel.isDarkMode.toggle()
                        viewModel.saveSettings()
                    }

                    Spacer()

                    bottomButton(icon: "bookmark.fill", label: "书签") {
                        withAnimation { showBookmarksPanel = true }
                    }

                    Spacer()

                    bottomButton(
                        icon: viewModel.autoFlipEnabled ? "pause.fill" : "play.fill",
                        label: "自动",
                        color: viewModel.autoFlipEnabled ? .green : nil
                    ) {
                        viewModel.toggleAutoFlip()
                    }

                    Spacer()

                    bottomButton(icon: "gearshape", label: "设置") {
                        withAnimation { showSettingsPanel = true }
                    }

                    Spacer()

                    bottomButton(icon: "forward.end.fill", label: "末页") {
                        viewModel.goToLastPage()
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .padding(.bottom, 6)
            .background(
                (viewModel.isDarkMode ? Color.black : Color.white)
                    .opacity(0.92)
                    .background(.ultraThinMaterial)
            )
        }
        .transition(.move(edge: .bottom))
    }

    private func bottomButton(icon: String, label: String, color: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(color ?? (viewModel.isDarkMode ? .white : .black))
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 缩略图导航条

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.pages) { page in
                        Button {
                            viewModel.goToPage(page.index)
                        } label: {
                            ThumbnailCell(
                                image: viewModel.thumbnailForPage(at: page.index),
                                isSelected: page.index == viewModel.currentPageIndex,
                                pageNumber: page.index + 1
                            )
                        }
                        .buttonStyle(.plain)
                        .id(page.index)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 60)
            .onChange(of: viewModel.currentPageIndex) { newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - 设置面板

    private var settingsPanel: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("阅读设置")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation { showSettingsPanel = false }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.gray)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 阅读方向
                        settingSection(title: "阅读方向") {
                            Picker("阅读方向", selection: $viewModel.readingDirection) {
                                ForEach(ReadingDirection.allCases, id: \.self) { dir in
                                    Text(dir.displayName).tag(dir)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.readingDirection) { _ in
                                viewModel.saveSettings()
                            }
                        }

                        // 阅读模式
                        settingSection(title: "阅读模式") {
                            Picker("阅读模式", selection: $viewModel.readingMode) {
                                ForEach(ReadingMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.readingMode) { _ in
                                viewModel.saveSettings()
                            }
                        }

                        // 翻页效果
                        settingSection(title: "翻页效果") {
                            Picker("翻页效果", selection: $viewModel.pageTurnEffect) {
                                ForEach(ProgressService.PageTurnEffect.allCases, id: \.self) { effect in
                                    Text(effect.rawValue).tag(effect)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.pageTurnEffect) { _ in
                                viewModel.saveSettings()
                            }
                        }

                        // 画质增强
                        settingSection(title: "画质增强") {
                            Picker("画质增强", selection: $viewModel.enhanceLevel) {
                                ForEach(0..<4) { level in
                                    Text(ImageEnhancer.EnhanceLevel(rawValue: level)?.displayName ?? "")
                                        .tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.enhanceLevel) { _ in
                                viewModel.saveSettings()
                            }
                        }

                        // 阅读背景
                        settingSection(title: "阅读背景") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(ProgressService.ReadingBackground.allCases, id: \.self) { bg in
                                        BackgroundOption(
                                            background: bg,
                                            isSelected: viewModel.readingBackground == bg
                                        ) {
                                            viewModel.readingBackground = bg
                                            viewModel.saveSettings()
                                        }
                                    }
                                }
                            }
                        }

                        // 亮度
                        settingSection(title: "亮度") {
                            HStack {
                                Image(systemName: "sun.min")
                                Slider(value: $viewModel.brightness, in: 0.1...1.0)
                                    .onChange(of: viewModel.brightness) { _ in
                                        UIScreen.main.brightness = viewModel.brightness
                                        viewModel.saveSettings()
                                    }
                                Image(systemName: "sun.max")
                            }
                            .foregroundColor(.secondary)
                        }

                        // 阅读宽度
                        settingSection(title: "阅读宽度") {
                            HStack {
                                Text("窄").font(.caption)
                                Slider(value: $viewModel.readingWidth, in: 0.5...1.0)
                                    .onChange(of: viewModel.readingWidth) { _ in
                                        viewModel.saveSettings()
                                    }
                                Text("宽").font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }

                        // 自动翻页
                        settingSection(title: "自动翻页") {
                            Toggle("启用自动翻页", isOn: $viewModel.autoFlipEnabled)
                                .tint(.blue)
                                .onChange(of: viewModel.autoFlipEnabled) { _ in
                                    if viewModel.autoFlipEnabled {
                                        viewModel.startAutoFlip()
                                    } else {
                                        viewModel.stopAutoFlip()
                                    }
                                    viewModel.saveSettings()
                                }

                            if viewModel.autoFlipEnabled {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text("翻页间隔")
                                        Spacer()
                                        Text(String(format: "%.1f 秒", viewModel.autoFlipInterval))
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $viewModel.autoFlipInterval, in: 2.0...15.0, step: 0.5)
                                        .onChange(of: viewModel.autoFlipInterval) { _ in
                                            viewModel.saveSettings()
                                            if viewModel.autoFlipEnabled {
                                                viewModel.stopAutoFlip()
                                                viewModel.startAutoFlip()
                                            }
                                        }
                                }
                                .padding(.top, 6)
                            }
                        }

                        // 开关项
                        VStack(spacing: 0) {
                            // 旋转按钮
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.rotateImage()
                                }
                            } label: {
                                HStack {
                                    Label("旋转图片", systemImage: "rotate.right")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(Int(viewModel.rotation))°")
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 14)

                            // 分镜模式
                            Button {
                                viewModel.togglePanelMode()
                            } label: {
                                HStack {
                                    Label("分镜模式", systemImage: "square.grid.3x3")
                                        .font(.subheadline)
                                    Spacer()
                                    Text(viewModel.panelModeEnabled ? "开" : "关")
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 14)

                            toggleRow(title: "夜间模式", systemImage: "moon.fill", isOn: $viewModel.isDarkMode)
                            toggleRow(title: "双页模式", systemImage: "rectangle.split.2x1", isOn: $viewModel.doublePageMode)
                            toggleRow(title: "封面单独一页", systemImage: "doc.text", isOn: $viewModel.coverSinglePage)
                            toggleRow(title: "刘海屏防遮挡", systemImage: "eye", isOn: $viewModel.avoidNotch)
                            toggleRow(title: "缩略图导航条", systemImage: "rectangle.grid.1x2", isOn: $viewModel.showThumbnailStrip)
                            toggleRow(title: "裁剪白边", systemImage: "crop", isOn: $viewModel.cropWhiteBorder)
                            toggleRow(title: "沉浸式阅读", systemImage: "eye.slash", isOn: $viewModel.immersiveMode)
                            toggleRow(title: "显示页码", systemImage: "number", isOn: $viewModel.showPageNumber)
                        }
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
                .frame(maxHeight: 400)
            }
            .padding(20)
            .background(Color(.systemBackground))
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showSettingsPanel = false }
                }
        )
    }

    private func settingSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            content()
        }
    }

    private func toggleRow(title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: isOn) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
            }
            .tint(.blue)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .onChange(of: isOn.wrappedValue) { _ in
                viewModel.saveSettings()
            }
        }
    }

    // MARK: - 目录面板

    private var catalogPanel: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("目录")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation { showCatalog = false }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                Divider()

                // 快速跳转
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .foregroundColor(.secondary)
                    TextField("输入页码", text: $jumpPageText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("跳转") {
                        if let page = Int(jumpPageText), page >= 1 && page <= viewModel.totalPages {
                            viewModel.goToPage(page - 1)
                            jumpPageText = ""
                            withAnimation { showCatalog = false }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.pages) { page in
                            Button {
                                viewModel.goToPage(page.index)
                                withAnimation { showCatalog = false }
                            } label: {
                                HStack {
                                    Text("第 \(page.index + 1) 页")
                                        .foregroundColor(
                                            page.index == viewModel.currentPageIndex ? .blue : .primary
                                        )
                                    Spacer()
                                    if page.index == viewModel.currentPageIndex {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .frame(width: 280)
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 5)

            Spacer()
        }
        .background(
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showCatalog = false }
                }
        )
    }

    // MARK: - 书签面板

    private var bookmarksPanel: some View {
        HStack {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("书签")
                        .font(.headline)
                    Text("\(viewModel.bookmarks.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        withAnimation { showBookmarksPanel = false }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                Divider()

                if viewModel.bookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.largeTitle)
                            .foregroundColor(.gray.opacity(0.4))
                        Text("暂无书签")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("阅读时点击顶部书签按钮添加")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.bookmarks) { bookmark in
                                Button {
                                    viewModel.goToBookmark(bookmark)
                                } label: {
                                    HStack(spacing: 12) {
                                        Group {
                                            if let thumbnail = bookmark.thumbnail {
                                                Image(uiImage: thumbnail)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } else {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.2))
                                            }
                                        }
                                        .frame(width: 40, height: 56)
                                        .cornerRadius(4)
                                        .clipped()

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(bookmark.name)
                                                .font(.subheadline)
                                            Text(bookmark.createdAt, style: .date)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        ProgressService.shared.deleteBookmark(bookmark)
                                    } label: {
                                        Label("删除书签", systemImage: "trash")
                                    }
                                }

                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                }
            }
            .frame(width: 300)
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.2), radius: 10, x: -5)
        }
        .background(
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showBookmarksPanel = false }
                }
        )
    }

    // MARK: - 页码跳转对话框

    private var jumpDialog: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Text("跳转到页码")
                    .font(.headline)

                HStack(spacing: 12) {
                    TextField("页码", text: $jumpPageText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .multilineTextAlignment(.center)

                    Text("/ \(viewModel.totalPages)")
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Button("取消") {
                        showJumpDialog = false
                    }
                    .buttonStyle(.bordered)

                    Button("跳转") {
                        if let page = Int(jumpPageText), page >= 1 && page <= viewModel.totalPages {
                            viewModel.goToPage(page - 1)
                            showJumpDialog = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 20)
            .padding(.horizontal, 40)
            Spacer()
        }
        .background(Color.black.opacity(0.4).ignoresSafeArea())
        .transition(.opacity)
    }

    // MARK: - 分镜模式覆盖层

    private var panelModeOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                // 黑色背景
                Color.black
                    .ignoresSafeArea()

                // 当前分镜图片
                if let panelImage = viewModel.currentPanelImage() {
                    Image(uiImage: panelImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .rotationEffect(.degrees(viewModel.rotation))
                        .animation(.easeInOut(duration: 0.2), value: viewModel.currentPanelIndex)
                } else {
                    ProgressView()
                        .tint(.white)
                }

                // 点击区域
                HStack(spacing: 0) {
                    // 左侧：上一个分镜
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation { viewModel.previousPanel() }
                        }

                    // 中间：显示工具栏
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geometry.size.width * 0.2)
                        .onTapGesture {
                            withAnimation { showBars.toggle() }
                        }

                    // 右侧：下一个分镜
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation { viewModel.nextPanel() }
                        }
                }

                // 顶部工具栏
                if showBars {
                    VStack {
                        HStack {
                            Button {
                                viewModel.togglePanelMode()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }

                            Spacer()

                            Text("分镜 \(viewModel.currentPanelIndex + 1) / \(viewModel.detectedPanels.count)")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(16)

                            Spacer()

                            Button {
                                withAnimation { showBars.toggle() }
                            } label: {
                                Image(systemName: "eye.slash")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        Spacer()
                    }
                }

                // 底部提示
                if showBars {
                    VStack {
                        Spacer()
                        Text("点击左右切换分镜，中间显示/隐藏工具栏")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .transition(.opacity)
        .onAppear {
            viewModel.detectPanelsForCurrentPage()
        }
        .onChange(of: viewModel.currentPageIndex) { _ in
            if viewModel.panelModeEnabled {
                viewModel.detectPanelsForCurrentPage()
            }
        }
    }
}

// MARK: - 仿真翻页视图控制器（UIViewRepresentable）

struct PageTurnViewController: UIViewControllerRepresentable {

    let pages: [ComicPage]
    @Binding var currentIndex: Int
    let pageTurnEffect: ProgressService.PageTurnEffect
    let rotation: Double
    let imageProvider: (Int) -> UIImage?
    let onPageChanged: (Int) -> Void
    let onTap: (CGPoint) -> Void

    func makeUIViewController(context: Context) -> UIPageViewController {
        let transitionStyle: UIPageViewController.TransitionStyle
        switch pageTurnEffect {
        case .curl:
            transitionStyle = .pageCurl  // 仿真翻页
        case .slide, .fade, .none:
            transitionStyle = .scroll
        }

        let pvc = UIPageViewController(
            transitionStyle: transitionStyle,
            navigationOrientation: .horizontal,
            options: nil
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.isDoubleSided = false

        let initialVC = context.coordinator.makePageController(for: currentIndex)
        pvc.setViewControllers([initialVC], direction: .forward, animated: false)

        // 添加点击手势
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        pvc.view.addGestureRecognizer(tapGesture)

        return pvc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        // 更新所有可见页面的旋转
        uiViewController.viewControllers?.forEach { vc in
            if let pageVC = vc as? PageContentViewController {
                pageVC.rotation = rotation
            }
        }
        // 同步当前页
        if let currentVC = uiViewController.viewControllers?.first as? PageContentViewController,
           currentVC.pageIndex != currentIndex {
            let newVC = context.coordinator.makePageController(for: currentIndex)
            let direction: UIPageViewController.NavigationDirection =
                currentIndex > currentVC.pageIndex ? .forward : .reverse
            uiViewController.setViewControllers([newVC], direction: direction, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageTurnViewController

        init(parent: PageTurnViewController) {
            self.parent = parent
        }

        func makePageController(for index: Int) -> PageContentViewController {
            let vc = PageContentViewController()
            vc.pageIndex = index
            vc.image = parent.imageProvider(index)
            vc.rotation = parent.rotation
            return vc
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? PageContentViewController else { return nil }
            let previousIndex = vc.pageIndex - 1
            guard previousIndex >= 0 else { return nil }
            return makePageController(for: previousIndex)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? PageContentViewController else { return nil }
            let nextIndex = vc.pageIndex + 1
            guard nextIndex < parent.pages.count else { return nil }
            return makePageController(for: nextIndex)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed,
                  let vc = pageViewController.viewControllers?.first as? PageContentViewController else { return }
            parent.currentIndex = vc.pageIndex
            parent.onPageChanged(vc.pageIndex)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            parent.onTap(location)
        }
    }
}

// MARK: - 单页内容控制器

class PageContentViewController: UIViewController {
    var pageIndex: Int = 0
    var rotation: Double = 0 {
        didSet { updateRotation() }
    }
    var image: UIImage? {
        didSet { imageView.image = image }
    }

    private let imageView = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func updateRotation() {
        let angle = CGFloat(rotation * .pi / 180)
        UIView.animate(withDuration: 0.2) {
            self.imageView.transform = CGAffineTransform(rotationAngle: angle)
        }
    }
}

// MARK: - 背景选项

struct BackgroundOption: View {
    let background: ProgressService.ReadingBackground
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
                Text(background.rawValue)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch background {
        case .white: return .white
        case .sepia: return Color(red: 0.96, green: 0.92, blue: 0.84)
        case .black: return .black
        case .gray: return Color(white: 0.9)
        case .wood: return Color(red: 0.76, green: 0.63, blue: 0.48)
        case .paper: return Color(red: 0.98, green: 0.97, blue: 0.93)
        }
    }
}

// MARK: - 缩略图单元格

struct ThumbnailCell: View {
    let image: UIImage?
    let isSelected: Bool
    let pageNumber: Int

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: 40, height: 56)
            .cornerRadius(4)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )

            if isSelected {
                Text("\(pageNumber)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue)
                    .cornerRadius(2)
                    .padding(.bottom, 2)
            }
        }
    }
}

// MARK: - 可缩放图片视图

struct ZoomableImageView: View {

    let image: UIImage?
    let isDarkMode: Bool
    var readingWidth: Double = 1.0

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: geometry.size.width * CGFloat(readingWidth),
                               height: geometry.size.height)
                        .frame(maxWidth: .infinity)
                } else {
                    Color.gray.opacity(0.2)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        )
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value, 1.0), 5.0)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale < 1.0 {
                            withAnimation {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1.0 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                if scale > 1.0 {
                    withAnimation {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                } else {
                    withAnimation {
                        scale = 2.0
                        lastScale = 2.0
                    }
                }
            }
        }
    }
}

// MARK: - 圆角扩展

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ReaderView(comic: Comic(
        title: "示例漫画",
        sourcePath: "test",
        format: .cbz,
        pageCount: 10
    ))
}
