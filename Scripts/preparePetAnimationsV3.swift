// swift Scripts/preparePetAnimationsV3.swift [repository root]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let width = 256, height = 336, count = 16
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace, bitmapInfo: bitmapInfo)!
}
func components(_ mask: [Bool], _ w: Int, _ h: Int) -> [[Int]] {
    var visited = Array(repeating: false, count: mask.count), groups: [[Int]] = []
    for seed in mask.indices where mask[seed] && !visited[seed] {
        var queue = [seed], cursor = 0; visited[seed] = true
        while cursor < queue.count {
            let i = queue[cursor]; cursor += 1
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let x = i % w + dx, y = i / w + dy
                    guard x >= 0, x < w, y >= 0, y < h else { continue }
                    let j = y * w + x
                    if mask[j] && !visited[j] { visited[j] = true; queue.append(j) }
                }
            }
        }
        groups.append(queue)
    }
    return groups.sorted { $0.count > $1.count }
}
struct Frame {
    let image: CGImage
    let eye: CGPoint
    let eyeGap: CGFloat
    let bounds: CGRect
}
var originals: [String: [Frame]] = [:]
for mode in ["greeting", "running"] {
    let source = CGImageSourceCreateWithURL(root.appendingPathComponent("Artwork/Generated/fox-\(mode)-v3-source.png") as CFURL, nil)!
    let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    var frames: [Frame] = []
    for index in 0..<count {
        let col = index % 4, row = index / 4
        let x0 = atlas.width * col / 4, y0 = atlas.height * row / 4
        let w = atlas.width * (col + 1) / 4 - x0, h = atlas.height * (row + 1) / 4 - y0
        let cropped = atlas.cropping(to: CGRect(x: x0, y: y0, width: w, height: h))!
        let decoded = context(w, h)
        decoded.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = decoded.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var visible: [Int] = []
        for i in 0..<(w * h) {
            let p = i * 4
            let r = Double(pixels[p]), g = Double(pixels[p + 1]), b = Double(pixels[p + 2])
            let alpha = max(0, min(1, 1 - max(0, g - max(r, b)) / 245))
            if alpha < 0.1 { for channel in 0..<4 { pixels[p + channel] = 0 }; continue }
            let green = max(0, min((r + b) * 0.5, g - 245 * (1 - alpha)))
            pixels[p] = UInt8(min(r, alpha * 255).rounded())
            pixels[p + 1] = UInt8(min(green, alpha * 255).rounded())
            pixels[p + 2] = UInt8(min(b, alpha * 255).rounded())
            pixels[p + 3] = UInt8((alpha * 255).rounded())
            if alpha > 0.5 { visible.append(i) }
        }
        precondition(visible.count > w * h / 5 && visible.count < w * h * 4 / 5, "Bad matte: \(mode) \(index)")
        var eyeMask = Array(repeating: false, count: w * h)
        for i in visible {
            let y = i / w
            eyeMask[i] = y > h / 6 && y < h * 2 / 5 && pixels[i * 4] < 85 && pixels[i * 4 + 1] < 95 && pixels[i * 4 + 2] < 165
        }
        let eyes = components(eyeMask, w, h).filter { $0.count >= 30 }.prefix(2).map { group in
            CGPoint(x: CGFloat(group.reduce(0) { $0 + $1 % w }) / CGFloat(group.count), y: CGFloat(group.reduce(0) { $0 + $1 / w }) / CGFloat(group.count))
        }.sorted { $0.x < $1.x }
        precondition(eyes.count == 2, "Missing eyes: \(mode) \(index)")
        let minX = visible.map { $0 % w }.min()!, maxX = visible.map { $0 % w }.max()!
        let minY = visible.map { $0 / w }.min()!, maxY = visible.map { $0 / w }.max()!
        frames.append(Frame(image: decoded.makeImage()!, eye: CGPoint(x: (eyes[0].x + eyes[1].x) / 2, y: (eyes[0].y + eyes[1].y) / 2),
                            eyeGap: eyes[1].x - eyes[0].x, bounds: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)))
    }
    originals[mode] = frames
}
let reference = originals["greeting"]![0]
let eyeTarget = CGPoint(x: CGFloat(width) / 2, y: 116)
let desiredGap = reference.eyeGap * CGFloat(height) * 0.86 / reference.bounds.height
var fit: CGFloat = 1
for frame in originals.values.flatMap({ $0 }) {
    let scale = desiredGap / frame.eyeGap
    fit = min(fit, (eyeTarget.x - 5) / ((frame.eye.x - frame.bounds.minX) * scale),
              (CGFloat(width) - eyeTarget.x - 5) / ((frame.bounds.maxX - frame.eye.x) * scale),
              (eyeTarget.y - 5) / ((frame.eye.y - frame.bounds.minY) * scale),
              (CGFloat(height) - eyeTarget.y - 5) / ((frame.bounds.maxY - frame.eye.y) * scale))
}
for mode in ["greeting", "running"] {
    var packed: [CGImage] = []
    for frame in originals[mode]! {
        let scale = desiredGap / frame.eyeGap * fit
        let canvas = context(width, height); canvas.interpolationQuality = .high
        let top = eyeTarget.y - frame.eye.y * scale
        canvas.draw(frame.image, in: CGRect(x: eyeTarget.x - frame.eye.x * scale, y: CGFloat(height) - top - CGFloat(frame.image.height) * scale,
                                            width: CGFloat(frame.image.width) * scale, height: CGFloat(frame.image.height) * scale))
        packed.append(canvas.makeImage()!)
    }
    if mode == "greeting" { packed[count - 1] = packed[0] }
    for target in ["PetPet Watch App", "PetPet"] {
        let group = root.appendingPathComponent("\(target)/Assets.xcassets/PetAnimationsV3")
        try! FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        try! JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]).write(to: group.appendingPathComponent("Contents.json"))
        for (index, image) in packed.enumerated() {
            let name = String(format: "stepmate_fox_\(mode)_v3_%02d", index)
            let directory = group.appendingPathComponent("\(name).imageset")
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("frame.png")
            let output = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(output, image, nil); precondition(CGImageDestinationFinalize(output))
            let contents: [String: Any] = ["images": [["filename": "frame.png", "idiom": "universal"]], "info": ["author": "xcode", "version": 1]]
            try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("Contents.json"))
        }
    }
    let output = CGImageDestinationCreateWithURL(root.appendingPathComponent("Artwork/Generated/fox-\(mode)-v3.gif") as CFURL, UTType.gif.identifier as CFString, count, nil)!
    CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (index, image) in packed.enumerated() {
        let matte = context(width, height)
        matte.setFillColor(CGColor(red: 0.025, green: 0.09, blue: 0.21, alpha: 1)); matte.fill(CGRect(x: 0, y: 0, width: width, height: height))
        matte.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let delay = mode == "greeting" && index == 0 ? 0.6 : [0.06, 0.07, 0.07][index % 3]
        CGImageDestinationAddImage(output, matte.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(output))
    print("Packed \(mode): 16 transparent 256×336 frames per app + GIF preview; shared scale fit \(fit)")
}
