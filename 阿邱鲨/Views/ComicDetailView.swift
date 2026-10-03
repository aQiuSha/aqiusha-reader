//
//  ComicDetailView.swift
//  阿邱鲨
//
//  漫画详情页：封面、信息、进度、书签、开始阅读
//

import SwiftUI

struct ComicDetailView: View {

    let comic: Comic
    @EnvironmentObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showReader = false
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var editTitle = ""
    @State private var editAuthor = ""
    @State private var editTags = ""
    @State private var editCollection = ""
    @State private var showCategorySheet = false
    @State private var newCategoryName = ""

    private var progress: ReadingProgress? {
        viewModel.progress(for: comic)
    }

    private var bookmarks: [Bookmark] {
        viewModel.bookmarks(for: comic)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 顶部封面区域
                headerSection

                // 信息区域
                infoSection

                // 操作按钮
                actionSection

                // 评分
                ratingSection

                // 书签区域
                if !bookmarks.isEmpty {
                    bookmarksSection
                }

                // 文件信息
                fileInfoSection
            }
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        editTitle = comic.title
                        editAuthor = comic.author ?? ""
                        editTags = comic.tags.joined(separator: ", ")
                        editCollection = comic.collectionName ?? ""
                        showEditSheet = true
                    } label: {
                        Label("编辑信息", systemImage: "pencil")
                    }
                    Button {
                        viewModel.toggleFavorite(comic)
                    } label: {
                        Label(comic.isFavorite ? "取消收藏" : "收藏",
                              systemImage: comic.isFavorite ? "star.slash" : "star")
                    }
                    Button {
                        showCategorySheet = true
                    } label: {
                        Label("管理分类", systemImage: "tag.fill")
                    }
                    Button {
                        showImagePicker = true
                    } label: {
                        Label("更换封面", systemImage: "photo")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                }
            }
        }
        .fullScreenCover(isPresented: $showReader) {
            ReaderView(comic: comic)
                .ignoresSafeArea()
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                viewModel.deleteComic(comic)
                dismiss()
            }
        } message: {
            Text("删除后漫画文件、阅读进度和书签将一并清除，无法恢复。")
        }
        .sheet(isPresented: $showEditSheet) {
            editSheet
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker { image in
                saveCustomCover(image: image)
            }
        }
        .sheet(isPresented: $showCategorySheet) {
            categorySheet
        }
    }

    // MARK: - 编辑信息 Sheet

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("标题", text: $editTitle)
                    TextField("作者", text: $editAuthor)
                    TextField("标签（逗号分隔）", text: $editTags)
                }

                Section("合集") {
                    TextField("合集名称（留空表示未分类）", text: $editCollection)

                    if !viewModel.allCollections.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.allCollections, id: \.self) { name in
                                    Button(name) {
                                        editCollection = name
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("编辑信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showEditSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let tags = editTags
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        viewModel.updateComic(
                            comic,
                            title: editTitle,
                            author: editAuthor,
                            tags: tags,
                            collectionName: editCollection
                        )
                        showEditSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - 分类管理 Sheet

    private var categorySheet: some View {
        NavigationStack {
            List {
                Section("当前分类") {
                    if comic.categories.isEmpty {
                        Text("未分类")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(comic.categories, id: \.self) { category in
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundColor(.blue)
                                Text(category)
                                Spacer()
                                Button {
                                    viewModel.removeComic(comic, from: category)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }

                Section("添加到分类") {
                    if viewModel.allCategories.isEmpty {
                        Text("暂无分类，在下方创建")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.allCategories, id: \.self) { category in
                            if !comic.categories.contains(category) {
                                Button {
                                    viewModel.addComic(comic, to: category)
                                } label: {
                                    HStack {
                                        Image(systemName: "tag")
                                            .foregroundColor(.gray)
                                        Text(category)
                                        Spacer()
                                        Image(systemName: "plus.circle")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("新建分类") {
                    HStack {
                        TextField("分类名称", text: $newCategoryName)
                        Button {
                            if !newCategoryName.isEmpty {
                                viewModel.addComic(comic, to: newCategoryName)
                                newCategoryName = ""
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                        }
                        .disabled(newCategoryName.isEmpty)
                    }
                }
            }
            .navigationTitle("管理分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showCategorySheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - 顶部封面

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            // 背景模糊封面
            Group {
                if let cover = viewModel.coverImage(for: comic) {
                    Image(uiImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 320)
                        .clipped()
                        .blur(radius: 30)
                        .opacity(0.6)
                } else {
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(height: 320)
                }
            }

            // 封面图
            VStack(spacing: 12) {
                Group {
                    if let cover = viewModel.coverImage(for: comic) {
                        Image(uiImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "book.closed.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                            )
                    }
                }
                .frame(width: 160, height: 220)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)

                Text(comic.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 40)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .padding(.bottom, 24)
            .padding(.top, 60)
        }
    }

    // MARK: - 信息区域

    private var infoSection: some View {
        HStack(spacing: 0) {
            infoItem(value: "\(comic.pageCount)", label: "页数")
            Divider()
                .frame(height: 32)
            infoItem(value: comic.format.displayName, label: "格式")
            Divider()
                .frame(height: 32)
            infoItem(value: comic.fileSizeText, label: "大小")
            Divider()
                .frame(height: 32)
            infoItem(value: progress?.progressText ?? "0%", label: "进度")
        }
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
    }

    private func infoItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 操作按钮

    private var actionSection: some View {
        VStack(spacing: 12) {
            // 进度条
            if let progress = progress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("阅读进度")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("第 \(progress.currentPage + 1) / \(progress.totalPages) 页")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: progress.progress)
                        .tint(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            // 开始阅读按钮
            Button {
                showReader = true
            } label: {
                HStack {
                    Image(systemName: "book.fill")
                    Text(progress?.currentPage ?? 0 > 0 ? "继续阅读" : "开始阅读")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // 收藏按钮
            Button {
                viewModel.toggleFavorite(comic)
            } label: {
                HStack {
                    Image(systemName: comic.isFavorite ? "star.fill" : "star")
                        .foregroundColor(comic.isFavorite ? .yellow : .blue)
                    Text(comic.isFavorite ? "已收藏" : "收藏")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .padding(.top, 8)
    }

    // MARK: - 评分区域

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的评分")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if comic.rating > 0 {
                    Text("\(comic.rating) 星")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        viewModel.updateRating(comic, rating: comic.rating == star ? 0 : star)
                    } label: {
                        Image(systemName: star <= comic.rating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundColor(star <= comic.rating ? .yellow : .gray)
                    }
                    .buttonStyle(.plain)
                }

                if comic.rating > 0 {
                    Button("清除") {
                        viewModel.updateRating(comic, rating: 0)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .padding(.top, 8)
    }

    // MARK: - 书签区域

    private var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("书签")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("\(bookmarks.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(bookmarks) { bookmark in
                        BookmarkCard(bookmark: bookmark) {
                            // 跳转到书签页
                            showReader = true
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .padding(.top, 8)
    }

    // MARK: - 文件信息

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("文件信息")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                infoRow(title: "文件名", value: (comic.sourcePath as NSString).lastPathComponent)
                infoRow(title: "格式", value: comic.format.displayName)
                infoRow(title: "页数", value: "\(comic.pageCount) 页")
                infoRow(title: "大小", value: comic.fileSizeText)
                if let author = comic.author, !author.isEmpty {
                    infoRow(title: "作者", value: author)
                }
                if !comic.tags.isEmpty {
                    infoRow(title: "标签", value: comic.tags.joined(separator: ", "))
                }
                if let collection = comic.collectionName {
                    infoRow(title: "合集", value: collection)
                }
                if !comic.categories.isEmpty {
                    infoRow(title: "分类", value: comic.categories.joined(separator: ", "))
                }
                infoRow(title: "导入时间", value: dateString(comic.importDate), isLast: true)
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
        .padding(.bottom, 40)
    }

    private func infoRow(title: String, value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if !isLast {
                Divider()
                    .padding(.leading, 14)
            }
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 书签卡片

struct BookmarkCard: View {
    let bookmark: Bookmark
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let thumbnail = bookmark.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "bookmark.fill")
                                    .foregroundColor(.white)
                            )
                    }
                }
                .frame(width: 80, height: 110)
                .cornerRadius(6)
                .clipped()

                Text(bookmark.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 80)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ComicDetailView(comic: Comic(
        title: "示例漫画",
        sourcePath: "test",
        format: .cbz,
        pageCount: 100
    ))
    .environmentObject(LibraryViewModel())
}

