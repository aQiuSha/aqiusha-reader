# 阿邱鲨 - iOS 全格式漫画阅读器

一只爱读漫画的小鲨鱼 🦈

## 项目简介

阿邱鲨是一款基于 SwiftUI 开发的 iOS 原生漫画阅读器，**支持 CBZ / CBR / PDF / EPUB / 图片 / 文件夹** 全格式，本地导入、隐私安全。界面简洁优雅，阅读体验流畅，功能对标冰块阅读器。

## 功能特性

### 📚 书架管理
- 三列网格布局展示漫画封面
- **最近阅读**横向卡片，一键续读
- **筛选标签**：全部 / 未读 / 在读 / 已读 / 收藏
- 支持搜索（标题/作者/标签）
- 多种排序：导入时间 / 标题 / 阅读进度 / 最近阅读 / 文件大小 / **评分**
- 显示阅读进度条和格式标签
- **收藏功能**：星标标记喜欢的漫画
- **漫画评分**：1-5 星打分，按评分排序，书架显示评分星星
- **自动合集整理**：自动识别"第01卷""Vol.01"等命名，归类到同一合集
- **合集视图**：按合集分组展示，可展开/折叠
- **自定义分类**：手动创建分类，漫画可归入多个分类，按分类筛选
- **批量操作**：多选后批量删除、收藏、移动到合集
- **拖拽排序**：长按拖拽调整书架顺序
- 长按/右键菜单：收藏、删除
- 书架统计（总数/在读/已读/收藏/占用空间）

### 📖 漫画详情页
- 大封面展示 + 模糊背景
- 漫画信息：页数、格式、大小、进度、作者、标签、合集
- 继续阅读 / 开始阅读按钮
- 收藏按钮
- **漫画评分**：1-5 星可点击评分，点击同一星可取消
- **分类管理**：将漫画添加到自定义分类，可移除
- **编辑信息**：可修改标题、作者、标签、合集名称
- 书签横向滚动预览
- 文件信息详情

### 📖 漫画阅读
- **仿真翻页**：基于 UIPageViewController 的 pageCurl 仿真翻页，支持滑动/仿真/淡入/无动画四种效果
- **单页模式**：左右滑动翻页，点击屏幕左/中/右区域翻页/唤出菜单
- **横屏双页展示**：横屏自动双页并排，封面可单独一页
- **连续阅读（条漫）**：垂直滚动连续阅读，自动检测长图条漫
- **条漫自动检测**：导入时自动识别高宽比 >1.5 的长图，自动切换条漫模式
- **双指缩放**：放大查看细节，双击快速缩放
- **阅读方向**：支持从左到右 / 从右到左 / 从上到下
- **夜间模式**：一键切换深色背景
- **亮度调节**：阅读内直接调节屏幕亮度
- **目录跳转**：快速跳转到任意页
- **页码快速跳转**：点击页码或目录面板输入页码直接跳转
- **进度记忆**：自动保存阅读进度，下次打开继续阅读
- **启动继续阅读**：App 启动后自动打开上次阅读的漫画
- **屏幕常亮**：阅读时保持屏幕不锁屏
- **书签功能**：任意页添加书签，带缩略图，侧边栏管理
- **自动翻页**：2-15 秒自定义间隔，阅读内实时调节
- **缩略图导航条**：底部横向缩略图，点击快速跳转
- **画质增强**：Waifu2x 风格四档增强（关闭/轻度/标准/强力），降噪+锐化+对比度+边缘增强
- **裁剪白边**：自动检测并裁剪图片四周白边
- **图片预加载**：预加载当前页前后 1-8 页，翻页更流畅
- **阅读背景**：6 种背景（白色/护眼/黑色/灰色/木纹/纸张）
- **阅读宽度**：50%-100% 可调
- **封面单独一页**：双页模式下封面独占
- **刘海屏防遮挡**：自动避开刘海区域
- **显示页码**：底部悬浮页码显示
- **沉浸式阅读**：隐藏状态栏和工具栏，全屏沉浸体验
- **图片旋转**：单页 90 度旋转，适合横构图漫画
- **分镜模式**：自动识别并放大漫画分镜，手机上看细节更清楚

### 📁 全格式支持

| 格式 | 扩展名 | 说明 | 依赖 |
|------|--------|------|------|
| **CBZ** | .cbz / .zip | 漫画 ZIP 压缩包（最常用） | 系统原生，零依赖 |
| **CBR** | .cbr / .rar | 漫画 RAR 压缩包 | 需集成 UnrarKit（可选） |
| **PDF** | .pdf | PDF 文档 | 系统原生 PDFKit |
| **EPUB** | .epub | EPUB 电子书（自动解析 OPF 阅读顺序） | 系统原生，零依赖 |
| **图片** | .jpg/.png/.webp/.gif/.bmp 等 | 单张图片 | 系统原生 |
| **文件夹** | — | 包含图片的文件夹 | 系统原生 |

> **CBR 说明**：CBR/RAR 格式需要集成 UnrarKit 库才能解压。未集成时导入 CBR 会提示安装方法，其他格式不受影响。集成步骤见下文「CBR 格式启用方法」。

### ⚙️ 设置
- 默认阅读方向 / 模式 / 翻页效果
- 画质增强（四档）/ 裁剪白边 / 预加载页数
- 阅读宽度调节
- 双页模式 / 封面单独一页 / 刘海屏防遮挡
- 自动翻页开关 + 自定义间隔
- 缩略图导航条 / 显示页码 / 沉浸式阅读
- 阅读背景（6种）/ 夜间模式
- 翻页动画 / 屏幕常亮
- **阅读统计**：总时长/今日/本周/连续阅读天数/累计页数，含7天趋势图
- **密码锁**：启动 App 需要 4 位数字密码或 Face ID/Touch ID，保护隐私
- **局域网共享**：电脑通过浏览器拖拽文件到手机，不用数据线
- 阅读进度和书签管理

## 系统要求

- **macOS**：13.0 或更高版本（运行 Xcode）
- **Xcode**：15.0 或更高版本
- **iOS**：16.0 或更高版本（部署目标）
- **iPhone / iPad**：均支持

## 编译运行步骤

### 1. 准备环境
1. 在 Mac 上安装 [Xcode](https://developer.apple.com/xcode/)（App Store 免费下载）
2. 首次打开 Xcode，等待组件安装完成
3. 登录 Apple ID（Xcode → Settings → Accounts）

### 2. 打开项目
1. 将整个 `阿邱鲨` 文件夹复制到 Mac 上
2. 双击 `阿邱鲨.xcodeproj` 文件，用 Xcode 打开
3. 等待 Xcode 索引完成（首次可能需要几分钟）

### 3. 配置签名
1. 在 Xcode 左侧项目导航器中，点击最顶部的 **阿邱鲨** 项目
2. 选择 **TARGETS → 阿邱鲨**
3. 进入 **Signing & Capabilities** 标签页
4. 勾选 **Automatically manage signing**
5. 在 **Team** 下拉中选择你的 Apple ID 团队
6. **Bundle Identifier** 可保持默认 `com.aqiusha.reader`，如需修改请确保唯一

### 4. （可选）启用 CBR/RAR 支持
如果需要阅读 CBR 格式漫画，添加 UnrarKit 依赖：

1. Xcode 菜单：**File → Add Package Dependencies...**
2. 在搜索框输入：`https://github.com/abbeycode/UnrarKit.git`
3. 选择 **Up to Next Major Version**，点击 **Add Package**
4. 选择 **阿邱鲨** target，点击 **Add Package**
5. 等待依赖下载完成，重新编译即可

> 不添加此依赖也能正常编译运行，仅 CBR/RAR 格式不可用。

### 5. 运行到模拟器
1. 在 Xcode 顶部工具栏选择模拟器（如 iPhone 15 Pro）
2. 点击左上角的 ▶️ 运行按钮（或按 `Cmd + R`）
3. 等待编译完成，模拟器会自动启动并运行 App

### 6. 运行到真机（可选）
1. 用数据线将 iPhone 连接到 Mac
2. 在 iPhone 上信任这台电脑
3. 在 Xcode 顶部选择你的 iPhone 设备
4. 点击运行按钮
5. 首次运行需要在 iPhone 的 **设置 → 通用 → VPN与设备管理** 中信任开发者证书

### 7. 导入漫画
- **方式一**：在 App 内点击右下角 + 号，从文件 App 中选择漫画文件
- **方式二**：在 Mac/PC 上通过 Finder 文件共享将漫画拖入 App 的 Documents 目录
- **方式三**：通过 AirDrop 发送漫画文件到 iPhone，选择用"阿邱鲨"打开
- **方式四**：在文件 App 中长按漫画文件 → 共享 → 用"阿邱鲨"打开
- **方式五**：**局域网传输** - 设置中开启局域网共享，电脑浏览器访问显示的地址，拖拽文件上传

## 项目结构

```
阿邱鲨/
├── 阿邱鲨.xcodeproj/          # Xcode 工程文件
│   └── project.pbxproj
├── 阿邱鲨/                     # 源代码目录
│   ├── 阿邱鲨App.swift         # App 入口
│   ├── ContentView.swift       # 主视图（Tab 导航 + 最近阅读）
│   ├── Info.plist              # 应用配置（含文档类型声明）
│   ├── Assets.xcassets/        # 资源目录
│   │   ├── AppIcon.appiconset/ # App 图标
│   │   └── AccentColor.colorset/
│   ├── Models/                 # 数据模型
│   │   ├── Comic.swift         # 漫画模型（含格式枚举、收藏、合集）
│   │   ├── ReadingProgress.swift # 阅读进度模型
│   │   └── Bookmark.swift      # 书签模型（含缩略图）
│   ├── Views/                  # 界面层
│   │   ├── LibraryView.swift   # 书架页面（极简风格、筛选、最近阅读、批量操作、拖拽排序、分类筛选）
│   │   ├── ComicDetailView.swift # 漫画详情页（评分、分类管理）
│   │   ├── ReaderView.swift    # 阅读器页面（仿真翻页、双页、连续阅读、画质增强、图片旋转、分镜模式）
│   │   ├── SettingsView.swift  # 设置页面（密码锁、局域网共享）
│   │   └── LockScreenView.swift # 密码锁界面
│   ├── ViewModels/             # 视图模型
│   │   ├── LibraryViewModel.swift
│   │   └── ReaderViewModel.swift
│   └── Services/               # 服务层
│       ├── ArchiveService.swift       # ZIP/CBZ 解压（系统 Compression）
│       ├── RARArchiveService.swift    # RAR/CBR 解压（UnrarKit，条件编译）
│       ├── EPUBService.swift          # EPUB 解析（OPF 阅读顺序）
│       ├── ComicImportService.swift   # 全格式漫画导入
│       ├── ProgressService.swift      # 进度+书签+丰富设置+密码锁持久化
│       ├── ImageEnhancer.swift        # 画质增强+裁剪白边+条漫检测+分镜检测
│       └── WebSharingService.swift    # 局域网共享 HTTP 服务器
└── README.md                   # 本文件
```

## 架构设计

采用 **MVVM 架构**：
- **Model**：数据模型（Comic、ReadingProgress、Bookmark）
- **View**：SwiftUI 视图（LibraryView、ComicDetailView、ReaderView、SettingsView）
- **ViewModel**：视图模型（LibraryViewModel、ReaderViewModel）
- **Service**：底层服务（解压、导入、进度存储）

数据存储：
- 漫画元数据：UserDefaults（JSON 序列化）
- 阅读进度：UserDefaults
- 书签：UserDefaults（含缩略图数据）
- 阅读设置：UserDefaults
- 漫画文件：App Documents 目录
- 解压文件：App Documents/Extracted 目录

## 格式实现说明

### CBZ/ZIP
基于系统 `Compression` 框架实现，无需第三方依赖。支持 store 和 deflate 两种压缩方式。通过手动包装 zlib header 后调用 `compression_decode_buffer` 解压 raw deflate 数据流。

### CBR/RAR
通过 `#if canImport(UnrarKit)` 条件编译实现。集成 UnrarKit 后自动启用；未集成时给出明确的集成提示，不影响其他格式编译运行。

### EPUB
EPUB 本质是 ZIP 压缩包。解压后：
1. 读取 `META-INF/container.xml` 找到 OPF 文件路径
2. 解析 OPF XML 中的 `manifest`（资源清单）和 `spine`（阅读顺序）
3. 按 spine 顺序提取图片资源（支持直接图片和 XHTML 内嵌图片两种形式）
4. 解析失败时回退到按文件名自然排序

### PDF
使用系统 `PDFKit` 框架，按需渲染每一页为 UIImage。

## 已知限制

1. **CBR 需可选依赖**：RAR 格式涉及专利，需集成 UnrarKit（步骤见上文）
2. **ZIP 解压**：基于系统 Compression 框架，极少数特殊压缩的 ZIP 可能解压失败，如遇问题建议使用 [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 替换 `ArchiveService`
3. **大文件性能**：超大 PDF（>500MB）或超大压缩包解压可能较慢
4. **云同步**：当前版本仅本地存储，不支持 iCloud 同步
5. **书架数据**：卸载 App 会丢失所有数据，请定期备份

## 后续优化建议

1. **iCloud 同步**：使用 CloudKit 同步阅读进度和书架
2. **手势自定义**：允许用户自定义点击区域和手势
3. **主题皮肤**：多种阅读主题可选
4. **7Z 支持**：集成 LZMA SDK 支持 .cb7 格式
5. **MOBI/AZW3**：集成 Kindle 格式支持
6. **阅读社区**：书评、推荐、分享功能

## 技术栈

- **语言**：Swift 5.9
- **UI 框架**：SwiftUI
- **最低系统**：iOS 16.0
- **数据持久化**：UserDefaults + FileManager
- **图片处理**：UIKit / PDFKit / Core Image
- **画质增强**：Core Image 滤镜链（降噪+锐化+对比度+边缘）
- **压缩解压**：Compression framework（ZIP）+ UnrarKit（RAR，可选）
- **EPUB 解析**：原生 XML 解析 + ZIP 解压

## 许可证

本项目仅供学习和个人使用。

---

**阿邱鲨** - 让每一本漫画都有处可栖 📚🦈
