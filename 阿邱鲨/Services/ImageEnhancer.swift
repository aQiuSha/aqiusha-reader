//
//  ImageEnhancer.swift
//  阿邱鲨
//
//  图像增强服务：Waifu2x 风格画质增强 + 自动裁剪白边
//

import UIKit
import CoreImage

/// 图像增强服务
final class ImageEnhancer {

    static let shared = ImageEnhancer()

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let enhancedCache = NSCache<NSString, UIImage>()
    private let croppedCache = NSCache<NSString, UIImage>()

    private init() {}

    // MARK: - Waifu2x 风格画质增强

    /// 画质增强等级
    enum EnhanceLevel: Int, CaseIterable {
        case off = 0
        case low = 1
        case medium = 2
        case high = 3

        var displayName: String {
            switch self {
            case .off: return "关闭"
            case .low: return "轻度"
            case .medium: return "标准"
            case .high: return "强力"
            }
        }
    }

    /// 对图片进行画质增强（锐化 + 降噪 + 对比度，模拟 Waifu2x 效果）
    /// - Parameters:
    ///   - image: 原图
    ///   - level: 增强等级
    ///   - cacheKey: 缓存键（传 nil 则不缓存）
    /// - Returns: 增强后的图片
    func enhance(_ image: UIImage, level: EnhanceLevel, cacheKey: String? = nil) -> UIImage {
        guard level != .off else { return image }

        if let key = cacheKey, let cached = enhancedCache.object(forKey: key as NSString) {
            return cached
        }

        guard let ciImage = CIImage(image: image) else { return image }

        var output = ciImage

        // 1. 降噪（模拟 Waifu2x 的降噪阶段）
        let noiseLevel: Double
        let sharpenAmount: Double
        let contrastAmount: Double

        switch level {
        case .off:
            return image
        case .low:
            noiseLevel = 0.02
            sharpenAmount = 0.4
            contrastAmount = 1.05
        case .medium:
            noiseLevel = 0.04
            sharpenAmount = 0.7
            contrastAmount = 1.10
        case .high:
            noiseLevel = 0.06
            sharpenAmount = 1.0
            contrastAmount = 1.15
        }

        // 降噪
        if let noiseFilter = CIFilter(name: "CINoiseReduction") {
            noiseFilter.setValue(output, forKey: kCIInputImageKey)
            noiseFilter.setValue(noiseLevel, forKey: "inputNoiseLevel")
            noiseFilter.setValue(0.10, forKey: "inputSharpness")
            if let result = noiseFilter.outputImage {
                output = result
            }
        }

        // 锐化（模拟 Waifu2x 的超分辨率锐化）
        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(output, forKey: kCIInputImageKey)
            sharpenFilter.setValue(sharpenAmount, forKey: kCIInputSharpnessKey)
            if let result = sharpenFilter.outputImage {
                output = result
            }
        }

        // 对比度增强
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(output, forKey: kCIInputImageKey)
            contrastFilter.setValue(contrastAmount, forKey: kCIInputContrastKey)
            if let result = contrastFilter.outputImage {
                output = result
            }
        }

        // 边缘增强（让漫画线条更清晰）
        if let edgeFilter = CIFilter(name: "CIEdges") {
            edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
            edgeFilter.setValue(1.0, forKey: kCIInputIntensityKey)
            if let edges = edgeFilter.outputImage {
                // 将边缘检测结果与原图混合
                if let blendFilter = CIFilter(name: "CIMultiplyBlendMode") {
                    blendFilter.setValue(edges, forKey: kCIInputImageKey)
                    blendFilter.setValue(output, forKey: kCIInputBackgroundImageKey)
                    if let result = blendFilter.outputImage {
                        output = result
                    }
                }
            }
        }

        // 渲染为 UIImage
        guard let cgImage = context.createCGImage(output, from: ciImage.extent) else {
            return image
        }

        let enhanced = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)

        if let key = cacheKey {
            enhancedCache.setObject(enhanced, forKey: key as NSString)
        }

        return enhanced
    }

    // MARK: - 自动裁剪白边

    /// 自动裁剪图片四周的白边/浅色边
    /// - Parameters:
    ///   - image: 原图
    ///   - threshold: 白色阈值（0-255，越高越严格），默认 240
    ///   - cacheKey: 缓存键
    /// - Returns: 裁剪后的图片
    func cropWhiteBorder(_ image: UIImage, threshold: UInt8 = 240, cacheKey: String? = nil) -> UIImage {
        if let key = cacheKey, let cached = croppedCache.object(forKey: key as NSString) {
            return cached
        }

        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height

        // 缩小后检测，提升性能
        let scale: CGFloat = 0.1
        let smallWidth = max(1, Int(CGFloat(width) * scale))
        let smallHeight = max(1, Int(CGFloat(height) * scale))

        guard let context = CGContext(
            data: nil,
            width: smallWidth,
            height: smallHeight,
            bitsPerComponent: 8,
            bytesPerRow: smallWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))

        guard let pixelData = context.data else { return image }
        let pixels = pixelData.assumingMemoryBound(to: UInt8.self)

        func isWhitePixel(_ x: Int, _ y: Int) -> Bool {
            let offset = (y * smallWidth + x) * 4
            let r = pixels[offset]
            let g = pixels[offset + 1]
            let b = pixels[offset + 2]
            return r >= threshold && g >= threshold && b >= threshold
        }

        // 检测上边界
        var top = 0
        for y in 0..<smallHeight {
            var allWhite = true
            for x in 0..<smallWidth {
                if !isWhitePixel(x, y) {
                    allWhite = false
                    break
                }
            }
            if !allWhite { break }
            top += 1
        }

        // 检测下边界
        var bottom = smallHeight
        for y in stride(from: smallHeight - 1, through: top, by: -1) {
            var allWhite = true
            for x in 0..<smallWidth {
                if !isWhitePixel(x, y) {
                    allWhite = false
                    break
                }
            }
            if !allWhite { break }
            bottom -= 1
        }

        // 检测左边界
        var left = 0
        for x in 0..<smallWidth {
            var allWhite = true
            for y in top..<bottom {
                if !isWhitePixel(x, y) {
                    allWhite = false
                    break
                }
            }
            if !allWhite { break }
            left += 1
        }

        // 检测右边界
        var right = smallWidth
        for x in stride(from: smallWidth - 1, through: left, by: -1) {
            var allWhite = true
            for y in top..<bottom {
                if !isWhitePixel(x, y) {
                    allWhite = false
                    break
                }
            }
            if !allWhite { break }
            right -= 1
        }

        // 如果裁剪区域太小，返回原图
        guard right - left > smallWidth / 4, bottom - top > smallHeight / 4 else {
            return image
        }

        // 转换回原图坐标
        let cropRect = CGRect(
            x: CGFloat(left) / scale,
            y: CGFloat(top) / scale,
            width: CGFloat(right - left) / scale,
            height: CGFloat(bottom - top) / scale
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard let croppedCG = cgImage.cropping(to: cropRect) else { return image }

        let cropped = UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)

        if let key = cacheKey {
            croppedCache.setObject(cropped, forKey: key as NSString)
        }

        return cropped
    }

    // MARK: - 条漫检测

    /// 检测图片是否为条漫（长图）
    /// - Parameter image: 图片
    /// - Returns: 是否为条漫（高宽比 > 1.5）
    func isLongStripImage(_ image: UIImage) -> Bool {
        let ratio = image.size.height / max(image.size.width, 1)
        return ratio > 1.5
    }

    /// 检测一组图片是否整体为条漫
    /// - Parameter images: 图片数组
    /// - Returns: 条漫比例超过 60% 则判定为条漫
    func isLongStripComic(_ images: [UIImage]) -> Bool {
        guard !images.isEmpty else { return false }
        let longCount = images.filter { isLongStripImage($0) }.count
        return Double(longCount) / Double(images.count) > 0.6
    }

    // MARK: - 分镜检测

    /// 漫画分镜区域
    struct ComicPanel {
        let rect: CGRect  // 归一化坐标 0-1
        let index: Int
    }

    /// 检测漫画分镜区域
    /// - Parameter image: 漫画图片
    /// - Returns: 检测到的分镜区域数组（按从上到下、从左到右排序）
    func detectPanels(_ image: UIImage) -> [ComicPanel] {
        guard let cgImage = image.cgImage else { return [] }

        let width = cgImage.width
        let height = cgImage.height

        // 缩小后检测，提升性能
        let scale: CGFloat = 0.15
        let smallWidth = max(1, Int(CGFloat(width) * scale))
        let smallHeight = max(1, Int(CGFloat(height) * scale))

        guard let context = CGContext(
            data: nil,
            width: smallWidth,
            height: smallHeight,
            bitsPerComponent: 8,
            bytesPerRow: smallWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))

        guard let pixelData = context.data else { return [] }
        let pixels = pixelData.assumingMemoryBound(to: UInt8.self)

        // 转换为灰度图并检测边缘
        var edgeGrid = [[Bool]](repeating: [Bool](repeating: false, count: smallWidth), count: smallHeight)

        for y in 1..<(smallHeight - 1) {
            for x in 1..<(smallWidth - 1) {
                let center = grayAt(x, y)
                let right = grayAt(x + 1, y)
                let bottom = grayAt(x, y + 1)
                // 检测明显的亮度变化（分镜边框）
                let diff = abs(Int(center) - Int(right)) + abs(Int(center) - Int(bottom))
                edgeGrid[y][x] = diff > 60
            }
        }

        func grayAt(_ x: Int, _ y: Int) -> UInt8 {
            let offset = (y * smallWidth + x) * 4
            let r = pixels[offset]
            let g = pixels[offset + 1]
            let b = pixels[offset + 2]
            return UInt8((Int(r) + Int(g) + Int(b)) / 3)
        }

        // 基于边缘检测分镜区域（简化版：检测水平和垂直的长线）
        var panels: [CGRect] = []

        // 检测水平分割线
        var horizontalLines: [Int] = [0, smallHeight]
        for y in 2..<(smallHeight - 2) {
            var lineCount = 0
            for x in 0..<smallWidth {
                if edgeGrid[y][x] { lineCount += 1 }
            }
            if Double(lineCount) / Double(smallWidth) > 0.7 {
                horizontalLines.append(y)
            }
        }
        horizontalLines.sort()

        // 检测垂直分割线
        var verticalLines: [Int] = [0, smallWidth]
        for x in 2..<(smallWidth - 2) {
            var lineCount = 0
            for y in 0..<smallHeight {
                if edgeGrid[y][x] { lineCount += 1 }
            }
            if Double(lineCount) / Double(smallHeight) > 0.5 {
                verticalLines.append(x)
            }
        }
        verticalLines.sort()

        // 合并相近的线
        func mergeLines(_ lines: [Int], threshold: Int) -> [Int] {
            var result: [Int] = []
            for line in lines {
                if let last = result.last, abs(line - last) < threshold {
                    continue
                }
                result.append(line)
            }
            return result
        }

        horizontalLines = mergeLines(horizontalLines, threshold: 5)
        verticalLines = mergeLines(verticalLines, threshold: 5)

        // 生成矩形区域
        for i in 0..<(horizontalLines.count - 1) {
            for j in 0..<(verticalLines.count - 1) {
                let x = verticalLines[j]
                let y = horizontalLines[i]
                let w = verticalLines[j + 1] - x
                let h = horizontalLines[i + 1] - y

                // 过滤太小的区域
                guard w > smallWidth / 6, h > smallHeight / 6 else { continue }

                // 转换为归一化坐标
                let normalizedRect = CGRect(
                    x: CGFloat(x) / CGFloat(smallWidth),
                    y: CGFloat(y) / CGFloat(smallHeight),
                    width: CGFloat(w) / CGFloat(smallWidth),
                    height: CGFloat(h) / CGFloat(smallHeight)
                )
                panels.append(normalizedRect)
            }
        }

        // 如果没有检测到分镜，返回整个图片
        if panels.isEmpty {
            panels = [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        // 按从上到下、从左到右排序
        panels.sort { p1, p2 in
            if abs(p1.minY - p2.minY) > 0.1 {
                return p1.minY < p2.minY
            }
            return p1.minX < p2.minX
        }

        return panels.enumerated().map { ComicPanel(rect: $0.element, index: $0.offset) }
    }

    // MARK: - 缓存管理

    /// 清空所有缓存
    func clearCache() {
        enhancedCache.removeAllObjects()
        croppedCache.removeAllObjects()
    }
}
