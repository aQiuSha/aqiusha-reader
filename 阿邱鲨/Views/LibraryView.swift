//
//  LibraryView.swift
//  阿邱鲨
//
//  书架页面：极简风格，收藏、筛选、合集、最近阅读
//

import SwiftUI
import UniformTypeIdentifiers

/// 书架视图模式
enum LibraryViewMode: String, CaseIterable {
    case grid = "网格"
    case collection = "合集"
}

struct LibraryView: View {

    @EnvironmentObject var viewModel: LibraryViewModel
    @State private var showFilePicker = false
    @State private var showSortMenu = false
    @State private var selectedComic: Comic?
    @State private var showDeleteConfirmation = false
    @State private var comicToDelete: Comic?
    @State private var showFilterMenu = false
    @State private var viewMode: LibraryViewMode = .grid
    @State private var expandedCollections: Set<String> = []
    @State private var isEditing = false
    @State private var selectedComicIDs: Set<UUID> = []
    @State private var showBatchDeleteConfirmation = false
    @State private var showBatchCollectionSheet = false
    @State private var batchCollectionName = ""
    @State private var draggingComicID: UUID?
    @State private var selectedCategory: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                // 粉嫩渐变背景
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.0, green: 0.97, blue: 0.99),
                        Color(red: 0.98, green: 0.96, blue: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if viewModel.filteredComics.isEmpty && viewModel.searchText.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // 最近阅读
                            if !viewModel.recentComics.isEmpty && viewModel.filterOption == .all && viewModel.searchText.isEmpty {
                                recentSection
                            }

                            // 筛选标签
                            filterSection

                            // 分类筛选
                            if !viewModel.allCategories.isEmpty {
                                categorySection
                            }

                            // 漫画内容（网格或合集）
                            if viewMode == .grid {
                                comicGrid
                            } else {
                                collectionView
                            }
                        }
                    }
                }

                // 导入按钮
                VStack {
                    Spacer()
                    if isEditing {
                        // 批量操作工具栏
                        batchOperationBar
                            .padding(.bottom, 16)
                    } else {
                        HStack {
                            Spacer()
                            Button {
                                showFilePicker = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 52, height: 52)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 1.0, green: 0.62, blue: 0.78),
                                                Color(red: 0.78, green: 0.5, blue: 1.0)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(Circle())
                                    .shadow(color: Color(red: 1.0, green: 0.62, blue: 0.78).opacity(0.4), radius: 16, x: 0, y: 6)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 16)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "已选择 \(selectedComicIDs.count) 本" : "阿邱鲨")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditing {
                        Button("全选") {
                            selectedComicIDs = Set(comicsWithCategoryFilter.map { $0.id })
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(isEditing ? "完成" : "编辑") {
                            withAnimation {
                                isEditing.toggle()
                                selectedComicIDs.removeAll()
                            }
                        }
                        .fontWeight(isEditing ? .semibold : .regular)

                        if !isEditing {
                            // 视图切换
                            Button {
                                viewMode = viewMode == .grid ? .collection : .grid
                            } label: {
                                Image(systemName: viewMode == .grid ? "square.grid.2x2.fill" : "square.stack.3d.up.fill")
                            }

                            Menu {
                                Picker("筛选", selection: $viewModel.filterOption) {
                                    ForEach(LibraryFilter.allCases, id: \.self) { filter in
                                        Text(filter.rawValue).tag(filter)
                                    }
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                            }

                            Menu {
                                Picker("排序", selection: $viewModel.sortOption) {
                                    ForEach(LibrarySort.allCases, id: \.self) { sort in
                                        Text(sort.rawValue).tag(sort)
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down.circle")
                            }
                        }
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "搜索漫画")
            .sheet(isPresented: $showFilePicker) {
                FilePicker { urls in
                    Task {
                        await viewModel.importComics(from: urls)
                    }
                }
            }
            .fullScreenCover(item: $selectedComic) { comic in
                ComicDetailView(comic: comic)
                    .environmentObject(viewModel)
            }
            .alert("确认删除", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let comic = comicToDelete {
                        viewModel.deleteComic(comic)
                    }
                }
            } message: {
                Text("删除后漫画文件、阅读进度和书签将一并清除，无法恢复。")
            }
            .alert("确认删除", isPresented: $showBatchDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除 \(selectedComicIDs.count) 本", role: .destructive) {
                    viewModel.deleteComics(Array(selectedComicIDs))
                    selectedComicIDs.removeAll()
                    isEditing = false
                }
            } message: {
                Text("将删除选中的 \(selectedComicIDs.count) 本漫画，包括文件、进度和书签，无法恢复。")
            }
            .sheet(isPresented: $showBatchCollectionSheet) {
                batchCollectionSheet
            }
            .overlay {
                if viewModel.isLoading {
                    ImportProgressOverlay(
                        progress: viewModel.importProgress,
                        statusText: viewModel.importStatusText ?? "正在导入漫画..."
                    )
                }
            }
            .alert("导入失败", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - 最近阅读

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近阅读")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.recentComics) { comic in
                        RecentComicCard(
                            comic: comic,
                            coverImage: viewModel.coverImage(for: comic),
                            progress: viewModel.progress(for: comic)
                        )
                        .onTapGesture {
                            viewModel.markOpened(comic)
                            selectedComic = comic
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - 筛选标签

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: viewModel.filterOption == filter,
                        count: countFor(filter)
                    ) {
                        viewModel.filterOption = filter
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func countFor(_ filter: LibraryFilter) -> Int {
        switch filter {
        case .all: return viewModel.comics.count
        case .unread:
            return viewModel.comics.filter {
                guard let p = viewModel.progress(for: $0) else { return true }
                return p.currentPage == 0
            }.count
        case .reading:
            return viewModel.comics.filter {
                guard let p = viewModel.progress(for: $0) else { return false }
                return !p.isFinished && p.currentPage > 0
            }.count
        case .finished:
            return viewModel.comics.filter {
                viewModel.progress(for: $0)?.isFinished ?? false
            }.count
        case .favorite:
            return viewModel.comics.filter { $0.isFavorite }.count
        }
    }

    // MARK: - 分类筛选

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("分类")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                if selectedCategory != nil {
                    Button("清除") {
                        selectedCategory = nil
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.allCategories, id: \.self) { category in
                        FilterChip(
                            title: category,
                            isSelected: selectedCategory == category,
                            count: viewModel.comics(in: category).count
                        ) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
    }

    /// 应用分类筛选后的漫画列表
    private var comicsWithCategoryFilter: [Comic] {
        guard let category = selectedCategory else {
            return viewModel.filteredComics
        }
        return viewModel.filteredComics.filter { $0.categories.contains(category) }
    }

    // MARK: - 漫画网格

    private var comicGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(comicsWithCategoryFilter) { comic in
                ZStack(alignment: .topLeading) {
                    ComicGridItem(
                        comic: comic,
                        coverImage: viewModel.coverImage(for: comic),
                        progress: viewModel.progress(for: comic)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isEditing {
                            toggleSelection(comic)
                        } else {
                            viewModel.markOpened(comic)
                            selectedComic = comic
                        }
                    }
                    .contextMenu {
                        if !isEditing {
                            Button {
                                viewModel.toggleFavorite(comic)
                            } label: {
                                Label(comic.isFavorite ? "取消收藏" : "收藏",
                                      systemImage: comic.isFavorite ? "star.slash" : "star")
                            }
                            Button(role: .destructive) {
                                comicToDelete = comic
                                showDeleteConfirmation = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    .onDrag {
                        draggingComicID = comic.id
                        return NSItemProvider(object: comic.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: DropViewDelegate(
                        destinationComicID: comic.id,
                        comics: viewModel.filteredComics,
                        draggingComicID: $draggingComicID
                    ) { sourceID, destID in
                        if let sourceIndex = viewModel.filteredComics.firstIndex(where: { $0.id == sourceID }),
                           let destIndex = viewModel.filteredComics.firstIndex(where: { $0.id == destID }) {
                            viewModel.moveComic(from: sourceIndex, to: destIndex)
                        }
                    })

                    // 选择指示器
                    if isEditing {
                        Image(systemName: selectedComicIDs.contains(comic.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(selectedComicIDs.contains(comic.id) ? .blue : .white)
                            .background(
                                Circle()
                                    .fill(selectedComicIDs.contains(comic.id) ? Color.white : Color.black.opacity(0.4))
                                    .frame(width: 24, height: 24)
                            )
                            .padding(8)
                    }
                }
                .opacity(draggingComicID == comic.id ? 0.4 : 1.0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, isEditing ? 120 : 100)
    }

    // MARK: - 批量操作工具栏

    private var batchOperationBar: some View {
        HStack(spacing: 12) {
            // 收藏
            Button {
                viewModel.setFavorite(true, for: Array(selectedComicIDs))
                selectedComicIDs.removeAll()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.headline)
                    Text("收藏")
                        .font(.caption2)
                }
                .foregroundColor(.yellow)
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedComicIDs.isEmpty)

            // 移动到合集
            Button {
                showBatchCollectionSheet = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.headline)
                    Text("合集")
                        .font(.caption2)
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedComicIDs.isEmpty)

            // 删除
            Button {
                showBatchDeleteConfirmation = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.headline)
                    Text("删除")
                        .font(.caption2)
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedComicIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10, y: -4)
        .padding(.horizontal, 16)
    }

    private func toggleSelection(_ comic: Comic) {
        if selectedComicIDs.contains(comic.id) {
            selectedComicIDs.remove(comic.id)
        } else {
            selectedComicIDs.insert(comic.id)
        }
    }

    // MARK: - 批量移动合集 Sheet

    private var batchCollectionSheet: some View {
        NavigationStack {
            List {
                Section("选择合集") {
                    Button {
                        viewModel.setCollection(nil, for: Array(selectedComicIDs))
                        showBatchCollectionSheet = false
                        selectedComicIDs.removeAll()
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.minus")
                                .foregroundColor(.secondary)
                            Text("移除合集")
                            Spacer()
                        }
                    }

                    ForEach(viewModel.allCollections, id: \.self) { name in
                        Button {
                            viewModel.setCollection(name, for: Array(selectedComicIDs))
                            showBatchCollectionSheet = false
                            selectedComicIDs.removeAll()
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                Text(name)
                                Spacer()
                            }
                        }
                    }
                }

                Section("新建合集") {
                    TextField("合集名称", text: $batchCollectionName)
                    Button {
                        if !batchCollectionName.isEmpty {
                            viewModel.setCollection(batchCollectionName, for: Array(selectedComicIDs))
                            showBatchCollectionSheet = false
                            selectedComicIDs.removeAll()
                            batchCollectionName = ""
                        }
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.green)
                            Text("创建并移动")
                            Spacer()
                        }
                    }
                    .disabled(batchCollectionName.isEmpty)
                }
            }
            .navigationTitle("移动到合集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showBatchCollectionSheet = false
                    }
                }
            }
        }
    }

    // MARK: - 合集视图

    private var collectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 有合集的漫画
            ForEach(viewModel.allCollections, id: \.self) { collectionName in
                let comicsInCollection = viewModel.comics(in: collectionName)
                    .filter { comic in
                        // 应用当前筛选和搜索
                        matchesFilter(comic) && matchesSearch(comic)
                    }
                guard !comicsInCollection.isEmpty else { return }

                collectionSection(
                    name: collectionName,
                    comics: comicsInCollection,
                    isExpanded: expandedCollections.contains(collectionName)
                ) {
                    if expandedCollections.contains(collectionName) {
                        expandedCollections.remove(collectionName)
                    } else {
                        expandedCollections.insert(collectionName)
                    }
                }
            }

            // 未分类的漫画
            let uncategorized = viewModel.filteredComics.filter { $0.collectionName == nil }
            if !uncategorized.isEmpty {
                collectionSection(
                    name: "未分类",
                    comics: uncategorized,
                    isExpanded: expandedCollections.contains("未分类")
                ) {
                    if expandedCollections.contains("未分类") {
                        expandedCollections.remove("未分类")
                    } else {
                        expandedCollections.insert("未分类")
                    }
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 100)
    }

    private func collectionSection(name: String, comics: [Comic], isExpanded: Bool, toggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 合集标题
            Button {
                toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    Text(name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("\(comics.count) 本")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 展开的漫画网格
            if isExpanded {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(comics) { comic in
                        ComicGridItem(
                            comic: comic,
                            coverImage: viewModel.coverImage(for: comic),
                            progress: viewModel.progress(for: comic)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.markOpened(comic)
                            selectedComic = comic
                        }
                        .contextMenu {
                            Button {
                                viewModel.toggleFavorite(comic)
                            } label: {
                                Label(comic.isFavorite ? "取消收藏" : "收藏",
                                      systemImage: comic.isFavorite ? "star.slash" : "star")
                            }
                            Button(role: .destructive) {
                                comicToDelete = comic
                                showDeleteConfirmation = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Divider()
                .padding(.leading, 16)
        }
    }

    private func matchesFilter(_ comic: Comic) -> Bool {
        switch viewModel.filterOption {
        case .all: return true
        case .unread:
            guard let p = viewModel.progress(for: comic) else { return true }
            return p.currentPage == 0
        case .reading:
            guard let p = viewModel.progress(for: comic) else { return false }
            return !p.isFinished && p.currentPage > 0
        case .finished:
            return viewModel.progress(for: comic)?.isFinished ?? false
        case .favorite:
            return comic.isFavorite
        }
    }

    private func matchesSearch(_ comic: Comic) -> Bool {
        guard !viewModel.searchText.isEmpty else { return true }
        return comic.title.localizedCaseInsensitiveContains(viewModel.searchText) ||
               (comic.author ?? "").localizedCaseInsensitiveContains(viewModel.searchText) ||
               comic.tags.contains { $0.localizedCaseInsensitiveContains(viewModel.searchText) }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56))
                .foregroundColor(.gray.opacity(0.4))

            Text("书架空空如也")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text("点击右下角 + 号导入漫画")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))

            Button {
                showFilePicker = true
            } label: {
                Label("导入漫画", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 最近阅读卡片

struct RecentComicCard: View {
    let comic: Comic
    let coverImage: UIImage?
    let progress: ReadingProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.85, blue: 0.92),
                                    Color(red: 0.9, green: 0.85, blue: 1.0)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    }
                }
                .frame(width: 90, height: 130)
                .cornerRadius(8)
                .clipped()

                if let progress = progress, progress.currentPage > 0 {
                    VStack {
                        Spacer()
                        ProgressView(value: progress.progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 1.0, green: 0.62, blue: 0.78)))
                            .scaleEffect(x: 1, y: 1.5)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                }
            }

            Text(comic.title)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 90)
        }
    }
}

// MARK: - 筛选标签

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(count)")
                    .font(.caption2)
                    .opacity(0.7)
            }
            .foregroundColor(isSelected ? .white : Color(red: 0.6, green: 0.55, blue: 0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 1.0, green: 0.62, blue: 0.78),
                                Color(red: 0.78, green: 0.5, blue: 1.0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.white.opacity(0.6)
                    }
                }
            )
            .cornerRadius(18)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 漫画网格项

struct ComicGridItem: View {

    let comic: Comic
    let coverImage: UIImage?
    let progress: ReadingProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.5)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .overlay(
                                Image(systemName: "book.closed.fill")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.7))
                            )
                    }
                }
                .frame(height: 160)
                .cornerRadius(8)
                .clipped()

                // 收藏标记
                if comic.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .padding(5)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(5)
                }

                // 格式标签
                HStack {
                    Spacer()
                    Text(comic.format.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(3)
                }
                .padding(5)

                // 进度条
                if let progress = progress, progress.currentPage > 0 {
                    VStack {
                        Spacer()
                        ProgressView(value: progress.progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 1.0, green: 0.62, blue: 0.78)))
                            .scaleEffect(x: 1, y: 1.3)
                    }
                    .padding(.horizontal, 3)
                    .padding(.bottom, 2)
                }
            }

            Text(comic.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 34, alignment: .top)

            // 评分星星
            if comic.rating > 0 {
                HStack(spacing: 1) {
                    ForEach(1...comic.rating, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                    }
                }
                .frame(height: 10)
            }
        }
    }
}

// MARK: - 文件选择器

struct FilePicker: UIViewControllerRepresentable {

    let urls: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            .data,
            UTType(filenameExtension: "cbz") ?? .data,
            UTType(filenameExtension: "zip") ?? .data,
            UTType(filenameExtension: "cbr") ?? .data,
            UTType(filenameExtension: "rar") ?? .data,
            UTType(filenameExtension: "epub") ?? .data,
            UTType(filenameExtension: "mobi") ?? .data,
            UTType(filenameExtension: "7z") ?? .data,
            UTType(filenameExtension: "tar") ?? .data,
            .pdf,
            .image
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let urls: ([URL]) -> Void

        init(urls: @escaping ([URL]) -> Void) {
            self.urls = urls
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            self.urls(urls)
        }
    }
}

// MARK: - 导入进度遮罩

struct ImportProgressOverlay: View {
    let progress: Double
    let statusText: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .frame(width: 160)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.white)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(22)
            .background(Color.black.opacity(0.7))
            .cornerRadius(14)
        }
    }
}

// MARK: - 加载遮罩

struct LoadingOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(.white)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(22)
            .background(Color.black.opacity(0.7))
            .cornerRadius(14)
        }
    }
}

// MARK: - 拖拽排序代理

struct DropViewDelegate: DropDelegate {
    let destinationComicID: UUID
    let comics: [Comic]
    @Binding var draggingComicID: UUID?
    let onDrop: (UUID, UUID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingID = draggingComicID,
              draggingID != destinationComicID else {
            return false
        }
        onDrop(draggingID, destinationComicID)
        draggingComicID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        // 可以添加视觉反馈
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

#Preview {
    LibraryView()
        .environmentObject(LibraryViewModel())
}



