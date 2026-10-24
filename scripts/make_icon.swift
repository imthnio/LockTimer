// 生成 1024×1024 应用图标：swift make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// 底板（macOS 图标网格：824 方块，圆角约 185）
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0x281E50, 0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
rgb(0x16151B).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

tilePath.addClip()
NSGradient(colors: [rgb(0x7B61FF), rgb(0x3D8BFF), rgb(0x1FB89A)],
           atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: tile, angle: -50)
// 柔光
NSGradient(colors: [rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0)])!
    .draw(in: NSBezierPath(ovalIn: CGRect(x: 120, y: 520, width: 620, height: 460)), relativeCenterPosition: .zero)

let c = CGPoint(x: 512, y: 512)
// 刻度环
ctx.setLineCap(.round)
for i in 0..<24 {
    let a = CGFloat(i) / 24 * 2 * .pi
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.28).cgColor)
    ctx.setLineWidth(10)
    ctx.move(to: CGPoint(x: c.x + cos(a) * 262, y: c.y + sin(a) * 262))
    ctx.addLine(to: CGPoint(x: c.x + cos(a) * 286, y: c.y + sin(a) * 286))
    ctx.strokePath()
}
// 倒计时进度环
ctx.setLineWidth(36)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.22).cgColor)
ctx.addArc(center: c, radius: 330, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
ctx.strokePath()
ctx.setStrokeColor(rgb(0xFFFFFF).cgColor)
ctx.addArc(center: c, radius: 330, startAngle: .pi / 2, endAngle: .pi / 2 - 1.45 * .pi, clockwise: true)
ctx.strokePath()

// 锁
let white = rgb(0xFFFFFF)
white.setStroke()
let shackle = NSBezierPath()
shackle.lineWidth = 46
shackle.lineCapStyle = .round
shackle.move(to: CGPoint(x: 432, y: 520))
shackle.line(to: CGPoint(x: 432, y: 600))
shackle.appendArc(withCenter: CGPoint(x: 512, y: 600), radius: 80, startAngle: 180, endAngle: 0, clockwise: true)
shackle.line(to: CGPoint(x: 592, y: 520))
shackle.stroke()
white.setFill()
NSBezierPath(roundedRect: CGRect(x: 382, y: 352, width: 260, height: 200), xRadius: 52, yRadius: 52).fill()
rgb(0x4A6CF0).setFill()
NSBezierPath(ovalIn: CGRect(x: 488, y: 448, width: 48, height: 48)).fill()
NSBezierPath(roundedRect: CGRect(x: 500, y: 400, width: 24, height: 70), xRadius: 12, yRadius: 12).fill()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
