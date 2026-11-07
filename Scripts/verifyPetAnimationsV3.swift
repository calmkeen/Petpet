import Foundation
import CoreGraphics
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
var expected: [String: Data] = [:]
for target in ["PetPet Watch App", "PetPet"] {
    for mode in ["running", "greeting"] {
        for index in 0..<16 {
            let name = String(format: "stepmate_fox_\(mode)_v3_%02d", index)
            let file = root.appendingPathComponent("\(target)/Assets.xcassets/PetAnimationsV3/\(name).imageset/frame.png")
            let data = try Data(contentsOf: file)
            let source = CGImageSourceCreateWithData(data as CFData, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            precondition(image.width == 256 && image.height == 336, "Frame size: \(name)")
            let context = CGContext(data: nil, width: 256, height: 336, bitsPerComponent: 8, bytesPerRow: 256 * 4, space: space, bitmapInfo: bitmapInfo)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 336))
            let pixels = context.data!.bindMemory(to: UInt8.self, capacity: 256 * 336 * 4)
            var visible = 0
            for y in 0..<336 {
                for x in 0..<256 {
                    let p = (y * 256 + x) * 4, alpha = pixels[p + 3]
                    if x < 3 || x >= 253 || y < 3 || y >= 333 { precondition(alpha == 0, "Clipped frame: \(name)") }
                    if alpha > 128 { visible += 1 }
                    precondition(Int(pixels[p + 1]) <= max(Int(pixels[p]), Int(pixels[p + 2])) + 2, "Green matte residue: \(name)")
                }
            }
            precondition(visible > 25_000 && visible < 65_000, "Silhouette: \(name)")
            if target == "PetPet Watch App" { expected[name] = data }
            else { precondition(expected[name] == data, "Different phone/watch frame: \(name)") }
        }
    }
}
precondition(expected["stepmate_fox_greeting_v3_00"] == expected["stepmate_fox_greeting_v3_15"], "Greeting endpoints differ")
for mode in ["running", "greeting"] {
    let preview = root.appendingPathComponent("Artwork/Generated/fox-\(mode)-v3.gif")
    let gif = CGImageSourceCreateWithURL(preview as CFURL, nil)!
    precondition(CGImageSourceGetCount(gif) == 16, "GIF count: \(mode)")
}
print("Verified 64 transparent 256×336 frame copies, matte removal, bounds, greeting endpoints, and both 16-frame GIF previews.")
