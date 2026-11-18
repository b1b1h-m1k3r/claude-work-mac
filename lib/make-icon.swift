// Recolors the Claude app icon: dark background, white logo.
// Usage: swift make-icon.swift <in.icns> <out.png>
// Pixels that are clearly colored (the orange tile) become near-black.
// White logo pixels stay white. Soft shadow pixels (dark, unsaturated) are kept.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let img = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("cannot read icon\n".data(using: .utf8)!)
    exit(1)
}

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
img.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

let px = ctx.data!.bindMemory(to: UInt8.self, capacity: size * size * 4)
let darkValue: Float = 30

func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

for i in 0..<(size * size) {
    let o = i * 4
    let a = Float(px[o + 3]) / 255
    if a == 0 { continue }
    // un-premultiply
    let r = Float(px[o]) / 255 / a * 255
    let g = Float(px[o + 1]) / 255 / a * 255
    let b = Float(px[o + 2]) / 255 / a * 255
    let sat = max(r, g, b) - min(r, g, b)
    let lum = (r + g + b) / 3
    let colored = min(max((sat - 32) / 50, 0), 1)       // orange tile
    let whiteW = smoothstep(120, 200, lum)               // logo (bright, unsaturated)
    let neutral = whiteW * 255 + (1 - whiteW) * lum      // logo -> white, shadow -> as is
    let out = colored * darkValue + (1 - colored) * neutral
    let v = UInt8(min(max(out * a, 0), 255))
    px[o] = v; px[o + 1] = v; px[o + 2] = v
}

guard let outImg = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: outImg)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
