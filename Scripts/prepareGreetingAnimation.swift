// Packs the imagegen atlas into aligned, transparent runtime frames and a GIF preview.
// Usage: swift Scripts/prepareGreetingAnimation.swift [repository root]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Artwork/Generated/fox-greeting-v2-source.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Missing source atlas") }
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
let outputWidth = 256, outputHeight = 336, count = 12

func context(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: space, bitmapInfo: info)!
}

// Chessboard distance to a zero pixel. Used to remove small alpha artifacts
// without adding a background color to the pet's white fur.
func distance(_ foreground: [Bool], _ width: Int, _ height: Int) -> [Int] {
    var values = foreground.map { $0 ? width + height : 0 }
    for y in 0..<height {
        for x in 0..<width where values[y * width + x] > 0 {
            let i = y * width + x
            if x > 0 { values[i] = min(values[i], values[i - 1] + 1) }
            if y > 0 {
                values[i] = min(values[i], values[i - width] + 1)
                if x > 0 { values[i] = min(values[i], values[i - width - 1] + 1) }
                if x + 1 < width { values[i] = min(values[i], values[i - width + 1] + 1) }
            }
        }
    }
    for y in (0..<height).reversed() {
        for x in (0..<width).reversed() where values[y * width + x] > 0 {
            let i = y * width + x
            if x + 1 < width { values[i] = min(values[i], values[i + 1] + 1) }
            if y + 1 < height {
                values[i] = min(values[i], values[i + width] + 1)
                if x > 0 { values[i] = min(values[i], values[i + width - 1] + 1) }
                if x + 1 < width { values[i] = min(values[i], values[i + width + 1] + 1) }
            }
        }
    }
    return values
}

func components(_ mask: [Bool], _ width: Int, _ height: Int) -> [[Int]] {
    var visited = Array(repeating: false, count: mask.count)
    var result: [[Int]] = []
    for seed in mask.indices where mask[seed] && !visited[seed] {
        var queue = [seed]; visited[seed] = true
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let x = i % width, y = i / width
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let j = ny * width + nx
                    if mask[j] && !visited[j] { visited[j] = true; queue.append(j) }
                }
            }
        }
        result.append(queue)
    }
    return result.sorted { $0.count > $1.count }
}

func writePNG(_ image: CGImage, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot save PNG")
}

var frames: [CGImage] = []
var commonScale: CGFloat?
for index in 0..<count {
    let column = index % 4, row = index / 4
    let x0 = atlas.width * column / 4, x1 = atlas.width * (column + 1) / 4
    let y0 = atlas.height * row / 3, y1 = atlas.height * (row + 1) / 3
    let image = atlas.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))!
    let width = image.width, height = image.height
    let decoded = context(width, height)
    decoded.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = decoded.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
    let alpha = (0..<(width * height)).map { pixels[$0 * 4 + 3] >= 96 }
    let eroded = distance(alpha, width, height).map { $0 >= 5 }
    guard let body = components(eroded, width, height).first, body.count > width * height / 5 else {
        fatalError("Frame \(index) has no usable fox silhouette")
    }
    var outside = Array(repeating: true, count: alpha.count)
    for i in body { outside[i] = false }
    let margin = distance(outside, width, height)
    var retained: [Int] = []
    for i in alpha.indices {
        if margin[i] <= 6, pixels[i * 4 + 3] > 0 { retained.append(i) }
        else { for channel in 0..<4 { pixels[i * 4 + channel] = 0 } }
    }
    let minY = retained.map { $0 / width }.min()!, maxY = retained.map { $0 / width }.max()!
    // Align using the eyes, not the bounding box, whose width changes as the paw waves.
    var eyesMask = Array(repeating: false, count: alpha.count)
    for i in retained {
        let y = i / width
        eyesMask[i] = y > height / 5 && y < height * 2 / 5 && pixels[i * 4 + 3] > 200
            && pixels[i * 4] < 80 && pixels[i * 4 + 1] < 90 && pixels[i * 4 + 2] < 150
    }
    let eyes = components(eyesMask, width, height).filter { $0.count >= 30 }.prefix(2)
    precondition(eyes.count == 2, "Cannot find eye alignment in frame \(index)")
    let eyeX = eyes.map { group in CGFloat(group.reduce(0) { $0 + $1 % width }) / CGFloat(group.count) }.reduce(0, +) / 2
    let eyeY = eyes.map { group in CGFloat(group.reduce(0) { $0 + $1 / width }) / CGFloat(group.count) }.reduce(0, +) / 2
    let scale = commonScale ?? CGFloat(outputHeight) * 0.9 / CGFloat(maxY - minY + 1)
    commonScale = scale
    let target = context(outputWidth, outputHeight)
    target.interpolationQuality = .high
    let top = CGFloat(outputHeight) * 0.32 - eyeY * scale
    let rect = CGRect(x: CGFloat(outputWidth) / 2 - eyeX * scale,
                      y: CGFloat(outputHeight) - top - CGFloat(height) * scale,
                      width: CGFloat(width) * scale, height: CGFloat(height) * scale)
    target.draw(decoded.makeImage()!, in: rect)
    frames.append(target.makeImage()!)
    print("Prepared frame \(index): body \(body.count)px, eye anchor \(Int(eyeX)),\(Int(eyeY))")
}
// Identical endpoints prevent a pose/color jump when the reaction returns to idle.
frames[count - 1] = frames[0]
for target in ["PetPet Watch App", "PetPet"] {
    let group = root.appendingPathComponent("\(target)/Assets.xcassets/GreetingV2")
    try! FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
    let metadata: [String: Any] = ["info": ["author": "xcode", "version": 1]]
    try! JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: group.appendingPathComponent("Contents.json"))
    for (index, image) in frames.enumerated() {
        let name = String(format: "stepmate_fox_greeting_v2_%02d", index)
        let imageset = group.appendingPathComponent("\(name).imageset")
        writePNG(image, imageset.appendingPathComponent("frame.png"))
        let contents: [String: Any] = ["images": [["filename": "frame.png", "idiom": "universal"]], "info": ["author": "xcode", "version": 1]]
        try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: imageset.appendingPathComponent("Contents.json"))
    }
}
let preview = root.appendingPathComponent("Artwork/Generated/fox-greeting-v2.gif")
let gif = CGImageDestinationCreateWithURL(preview as CFURL, UTType.gif.identifier as CFString, count, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (index, image) in frames.enumerated() {
    let matte = context(outputWidth, outputHeight)
    matte.setFillColor(CGColor(red: 0.025, green: 0.09, blue: 0.21, alpha: 1))
    matte.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
    matte.draw(image, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
    let delay = index == 0 ? 0.7 : 0.1
    CGImageDestinationAddImage(gif, matte.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
}
precondition(CGImageDestinationFinalize(gif), "Cannot save GIF preview")
print("Saved 12 aligned transparent frames per app and GIF preview: \(preview.path)")
