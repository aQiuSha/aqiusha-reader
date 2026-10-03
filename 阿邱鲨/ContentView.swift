//
//  ContentView.swift
//  阿邱鲨
//
//  主内容视图：底部标签导航
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @State private var selectedTab: Tab = .library
    @State private var autoOpenComic: Comic?
    @State private var isLocked = false

    enum Tab: String {
        case library = "书架"
        case recent = "最近"
        case settings = "设置"
    }

    var body: some View {
        Group {
            if isLocked {
                LockScreenView {
                    isLocked = false
                }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        LibraryView()
                    }
                    .tabItem {
                        Label("书架", systemImage: "books.vertical.fill")
                    }
                    .tag(Tab.library)

                    NavigationStack {
                        RecentView()
                    }
                    .tabItem {
                        Label("最近", systemImage: "clock.fill")
                    }
                    .tag(Tab.recent)

                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem {
                        Label("设置", systemImage: "gearshape.fill")
                    }
                    .tag(Tab.settings)
                }
                .tint(Color(red: 1.0, green: 0.62, blue: 0.78))
                .onAppear {
                    // 启动后自动打开上次阅读的漫画
                    checkLastReadComic()
                }
                .fullScreenCover(item: $autoOpenComic) { comic in
                    ReaderView(comic: comic)
                        .ignoresSafeArea()
                }
            }
        }
        .onAppear {
            // 检查密码锁
            isLocked = ProgressService.shared.isPasswordLockEnabled
        }
    }

    /// 检查上次阅读的漫画并自动打开
    private func checkLastReadComic() {
        guard let lastID = ProgressService.shared.getLastReadComicID(),
              let comic = libraryViewModel.comics.first(where: { $0.id == lastID }) else {
            return
        }
        // 延迟一小段时间，让书架先加载完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            autoOpenComic = comic
        }
    }
}

// MARK: - 最近阅读视图

struct RecentView: View {

    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @State private var selectedComic: Comic?

    private var recentComics: [Comic] {
        let progressService = ProgressService.shared
        let recentProgress = progressService.getRecentComics(limit: 20)
        return recentProgress.compactMap { progress in
            libraryViewModel.comics.first { $0.id == progress.comicID }
        }
    }

    var body: some View {
        Group {
            if recentComics.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 50))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("暂无阅读记录")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("从书架中选择一本漫画开始阅读吧")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(recentComics) { comic in
                        RecentComicRow(comic: comic)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedComic = comic
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("最近阅读")
        .fullScreenCover(item: $selectedComic) { comic in
            ComicDetailView(comic: comic)
                .environmentObject(libraryViewModel)
        }
    }
}

struct RecentComicRow: View {

    let comic: Comic
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @State private var coverImage: UIImage?

    private var progress: ReadingProgress? {
        libraryViewModel.progress(for: comic)
    }

    var body: some View {
        HStack(spacing: 12) {
            // 封面
            Group {
                if let image = coverImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "book.closed.fill")
                                .foregroundColor(.gray.opacity(0.6))
                                .font(.title)
                        )
                }
            }
            .frame(width: 50, height: 70)
            .cornerRadius(4)
            .clipped()

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(comic.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(comic.format.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let progress = progress {
                    ProgressView(value: progress.progress)
                        .tint(Color(red: 1.0, green: 0.62, blue: 0.78))
                    HStack {
                        Text("第 \(progress.currentPage + 1) / \(progress.totalPages) 页")
                        Spacer()
                        Text(progress.progressText)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .onAppear {
            coverImage = libraryViewModel.coverImage(for: comic)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LibraryViewModel())
}

