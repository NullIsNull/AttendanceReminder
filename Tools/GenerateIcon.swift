// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = CGPath(roundedRect: CGRect(x: 48, y: 48, width: 928, height: 928),
                                cornerWidth: 205, cornerHeight: 205, transform: nil)
        context.addPath(background)
        context.clip()
        let colors = [CGColor(red: 0.08, green: 0.20, blue: 0.48, alpha: 1),
                      CGColor(red: 0.17, green: 0.46, blue: 0.91, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 900, y: 1024), options: [])
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.96))
        context.setLineWidth(44)
        context.strokeEllipse(in: CGRect(x: 226, y: 242, width: 560, height: 560))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: 506, y: 682))
        context.addLine(to: CGPoint(x: 506, y: 522))
        context.addLine(to: CGPoint(x: 620, y: 450))
        context.strokePath()
        context.setFillColor(CGColor(red: 0.30, green: 0.91, blue: 0.72, alpha: 1))
        context.fillEllipse(in: CGRect(x: 610, y: 160, width: 260, height: 260))
        context.setStrokeColor(CGColor(red: 0.06, green: 0.18, blue: 0.29, alpha: 1))
        context.setLineWidth(28)
        context.move(to: CGPoint(x: 674, y: 290))
        context.addLine(to: CGPoint(x: 724, y: 240))
        context.addLine(to: CGPoint(x: 808, y: 332))
        context.strokePath()
        let suffix = scale == 1 ? "" : "@2x"
        let url = destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(output, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(output) else { throw NSError(domain: "Icon", code: 1) }
    }
}

if CommandLine.arguments.count > 2 {
    func word(_ value: Int) -> Data {
        var bigEndian = UInt32(value).bigEndian
        return Data(bytes: &bigEndian, count: 4)
    }
    let entries = [("icp4", "16x16"), ("ic11", "16x16@2x"), ("icp5", "32x32"),
                   ("ic12", "32x32@2x"), ("ic07", "128x128"), ("ic13", "128x128@2x"),
                   ("ic08", "256x256"), ("ic14", "256x256@2x"), ("ic09", "512x512"),
                   ("ic10", "512x512@2x")]
    var body = Data()
    for (type, name) in entries {
        let png = try Data(contentsOf: destination.appendingPathComponent("icon_\(name).png"))
        body.append(Data(type.utf8))
        body.append(word(png.count + 8))
        body.append(png)
    }
    var file = Data("icns".utf8)
    file.append(word(body.count + 8))
    file.append(body)
    try file.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
