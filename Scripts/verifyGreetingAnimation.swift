import Foundation
import CoreGraphics
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
var expected: [Data] = []
for target in ["PetPet Watch App", "PetPet"] {
    for index in 0..<12 {
        let name = String(format: "stepmate_fox_greeting_v2_%02d", index)
        let url = root.appendingPathComponent("\(target)/Assets.xcassets/GreetingV2/\(name).imageset/frame.png")
        let data = try Data(contentsOf: url)
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(image.width == 256 && image.height == 336)
        let context = CGContext(data: nil, width: 256, height: 336, bitsPerComponent: 8,
                                bytesPerRow: 256 * 4, space: space, bitmapInfo: info)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 336))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: 256 * 336 * 4)
        var visible = 0
        for y in 0..<336 {
            for x in 0..<256 {
                let alpha = pixels[(y * 256 + x) * 4 + 3]
                if x < 3 || x >= 253 || y < 3 || y >= 333 { precondition(alpha == 0, "Nontransparent border: \(index)") }
                if alpha > 128 { visible += 1 }
            }
        }
        precondition(visible > 25_000 && visible < 65_000, "Unexpected silhouette: \(index)")
        if target == "PetPet Watch App" { expected.append(data) }
        else { precondition(data == expected[index], "Different phone/watch frame") }
    }
}
precondition(expected[0] == expected[11], "Idle endpoints differ")
let gif = CGImageSourceCreateWithURL(root.appendingPathComponent("Artwork/Generated/fox-greeting-v2.gif") as CFURL, nil)!
precondition(CGImageSourceGetCount(gif) == 12, "Preview frame count differs")
print("Verified 24 matching 256×336 frames, transparent borders, silhouette bounds, identical endpoints, and 12-frame GIF preview.")
