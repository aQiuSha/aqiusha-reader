# 阿邱鲨 - GitHub Actions 自动编译说明

## 步骤 1：注册 GitHub 账号
1. 打开 https://github.com
2. 点击 Sign up 注册账号（免费）

## 步骤 2：创建新仓库
1. 登录后点击右上角 + → New repository
2. 仓库名随便填，比如 `aqiusha-reader`
3. 选 Public（公开）
4. 不要勾选 README、.gitignore 这些
5. 点击 Create repository

## 步骤 3：上传代码
### 方法A：网页上传（最简单）
1. 在你刚创建的仓库页面，点击 "uploading an existing file"
2. 把整个 `阿邱鲨` 文件夹里的所有文件拖进去
3. 等上传完，点击 Commit changes

### 方法B：用 Git 命令
如果你会用 git，直接 push 上去就行。

## 步骤 4：等待自动编译
1. 上传代码后，点击仓库顶部的 Actions 标签
2. 你会看到 "Build iOS IPA" 正在运行
3. 等 5-10 分钟，编译完成（绿勾）

## 步骤 5：下载 IPA
1. 点击完成的那次编译
2. 拉到最下面 Artifacts 区域
3. 点击 `阿邱鲨-ipa` 下载
4. 解压后得到 `阿邱鲨-unsigned.ipa`

## 步骤 6：安装到 iPhone
这个是**未签名**的 ipa，需要用侧载工具安装：

### 用 Sideloadly（推荐）
1. 下载 Sideloadly：https://sideloadly.io/
2. 安装到 Windows 电脑
3. 用数据线连接 iPhone 到电脑
4. 把 ipa 文件拖进 Sideloadly
5. 输入你的 Apple ID
6. 点击 Start，等待安装完成

### 用 AltStore
1. 下载 AltServer 安装到电脑
2. 连接 iPhone，通过 AltStore 安装 ipa
3. 7 天后需要重新签名

## 注意事项
- 未签名 ipa 每 7 天需要重新签一次（免费 Apple ID）
- 如果有开发者账号，可以修改 workflow 加签名配置
- 第一次编译可能慢一点，GitHub Actions 免费额度每月 2000 分钟
