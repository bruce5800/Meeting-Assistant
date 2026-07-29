import AppKit
import ImageIO

// App Store marketing-screenshot compositor.
//   swiftc -O make_shots.swift -o make_shots
//   ./make_shots <rawDir> <outDir> <zh|en> [canvas]
//
// canvas 省略时按源图长宽比自动选择 App Store Connect 当前要求的槽位尺寸：
//   iphone65  1284×2778  iPhone 6.5"（ASC「6.5 英寸显示屏」槽位）← iPhone 默认
//   iphone69  1320×2868  iPhone 6.9"
//   ipad129   2048×2732  iPad 12.9"（ASC 老一代 iPad 槽位）      ← iPad 默认
//   ipad13    2064×2752  iPad 13"
// 版式参数以一套基准等比缩放到各尺寸，所以换画布不需要重新调版。

struct Canvas {
    let w: CGFloat, h: CGFloat
    let titleTop: CGFloat, titleSizeZH: CGFloat, titleSizeEN: CGFloat
    let barY: CGFloat, barW: CGFloat, barH: CGFloat
    let subY: CGFloat, subSize: CGFloat
    let deviceTop: CGFloat, deviceW: CGFloat

    /// 以本画布为基准，等比缩放出另一尺寸的版式
    func scaled(to width: CGFloat, _ height: CGFloat) -> Canvas {
        let k = min(width / w, height / h)
        func s(_ v: CGFloat) -> CGFloat { (v * k).rounded() }
        return Canvas(w: width, h: height,
                      titleTop: s(titleTop), titleSizeZH: s(titleSizeZH), titleSizeEN: s(titleSizeEN),
                      barY: s(barY), barW: s(barW), barH: s(barH),
                      subY: s(subY), subSize: s(subSize),
                      deviceTop: s(deviceTop), deviceW: s(deviceW))
    }

    // 基准版式（在这两个尺寸上手工调好，其余由 scaled(to:) 推导）
    static let iPhone69 = Canvas(w: 1320, h: 2868,
                                 titleTop: 138, titleSizeZH: 98, titleSizeEN: 84,
                                 barY: 318, barW: 128, barH: 11,
                                 subY: 372, subSize: 48,
                                 deviceTop: 596, deviceW: 980)
    static let iPad13 = Canvas(w: 2064, h: 2752,
                               titleTop: 150, titleSizeZH: 124, titleSizeEN: 108,
                               barY: 356, barW: 160, barH: 13,
                               subY: 424, subSize: 58,
                               deviceTop: 625, deviceW: 1490)

    static let iPhone65 = iPhone69.scaled(to: 1284, 2778)
    static let iPad129 = iPad13.scaled(to: 2048, 2732)

    static func named(_ name: String) -> Canvas? {
        switch name.lowercased() {
        case "iphone65": .iPhone65
        case "iphone69": .iPhone69
        case "ipad129": .iPad129
        case "ipad13": .iPad13
        default: nil
        }
    }

    /// 竖长比 > 1.6 认为是 iPhone，接近 4:3 的是 iPad；默认取 ASC 当前的槽位尺寸
    static func matching(_ image: CGImage) -> Canvas {
        CGFloat(image.height) / CGFloat(image.width) > 1.6 ? .iPhone65 : .iPad129
    }
}

struct Shot {
    let file: String
    let title: String
    let sub: String
}

let zhShots: [Shot] = [
    Shot(file: "01-live.png", title: "提问的瞬间，答案已经在了",
         sub: "边开会边转写——识别到问题立刻流式作答"),
    Shot(file: "03-records.png", title: "私有问题，问你自己的资料",
         sub: "AI 答不了的，本地知识库接手并标注来源"),
    Shot(file: "02-teleprompter.png", title: "念稿再也不用低头找行",
         sub: "提词器随你的语音自动滚动、高亮当前句"),
    Shot(file: "04-summary.png", title: "散会那一刻，纪要就好了",
         sub: "概要 · 要点 · 问答结论 · 待办，一键导出"),
    Shot(file: "05-settings.png", title: "一个问题都不漏掉",
         sub: "四层检测 · 本地离线与云端识别随时切换"),
]

// 英文标题控制在 80 pt 下单行不折行
let enShots: [Shot] = [
    Shot(file: "01-live.png", title: "Answers before you ask twice",
         sub: "Live transcription — questions answered as they're asked"),
    Shot(file: "03-records.png", title: "Ask about your own docs",
         sub: "On-device knowledge base answers, with cited sources"),
    Shot(file: "02-teleprompter.png", title: "Never lose your place",
         sub: "The teleprompter follows your voice, line by line"),
    Shot(file: "04-summary.png", title: "Minutes, the moment you finish",
         sub: "Summary · key points · decisions · action items — export in a tap"),
    Shot(file: "05-settings.png", title: "Never miss a question",
         sub: "Four detection layers · on-device or cloud speech recognition"),
]

// MARK: - Palette（取自 App 图标 QA-Duo）

let bgTop = NSColor(srgbRed: 0x2C/255.0, green: 0x3E/255.0, blue: 0x6B/255.0, alpha: 1)
let bgBottom = NSColor(srgbRed: 0x0D/255.0, green: 0x13/255.0, blue: 0x22/255.0, alpha: 1)
let accent = NSColor(srgbRed: 0x3D/255.0, green: 0xDC/255.0, blue: 0x97/255.0, alpha: 1)  // 图标里答案气泡的绿
let ink = NSColor.white
let muted = NSColor(srgbRed: 0xA3/255.0, green: 0xB0/255.0, blue: 0xC8/255.0, alpha: 1)

// MARK: - Helpers

func loadImage(_ path: String) -> CGImage {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("cannot load \(path)")
    }
    return img
}

func draw(text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
          in rect: CGRect, tracking: CGFloat = 0) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: para,
        .kern: tracking,
    ]
    NSAttributedString(string: text, attributes: attrs).draw(in: rect)
}

/// 把设备截图画成一台圆角"手机"，带柔和投影与一圈发丝描边。
func drawPhone(_ ctx: CGContext, image: CGImage, center: CGPoint, width: CGFloat) {
    let aspect = CGFloat(image.height) / CGFloat(image.width)
    let w = width, h = width * aspect
    let radius = w * 0.118                       // iPhone 屏幕圆角比例

    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 投影（先填一层同形状的黑底来投）
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 26), blur: 76,
                  color: NSColor.black.withAlphaComponent(0.6).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 截图裁进圆角
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)                     // 抵消全局翻转
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.restoreGState()

    // 发丝描边
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Canvas

func render(_ shot: Shot, lang: String, canvas: Canvas?, imgDir: String, outPath: String) {
    let img = loadImage("\(imgDir)/\(shot.file)")
    let c = canvas ?? Canvas.matching(img)
    let titleSize = lang == "zh" ? c.titleSizeZH : c.titleSizeEN

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(c.w), height: Int(c.h), bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("no context")
    }
    // 全局翻转 → 下面一律用左上角坐标系
    ctx.translateBy(x: 0, y: c.h)
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    // 背景渐变
    let grad = CGGradient(colorsSpace: space,
                          colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: c.h), options: [])

    // 标题 + 绿色短杠 + 副标题
    let side = c.w * 0.05
    draw(text: shot.title, size: titleSize, weight: .bold, color: ink,
         in: CGRect(x: side, y: c.titleTop, width: c.w - side * 2, height: titleSize * 2.2))
    let bar = CGRect(x: c.w / 2 - c.barW / 2, y: c.barY, width: c.barW, height: c.barH)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: c.barH / 2,
                       cornerHeight: c.barH / 2, transform: nil))
    ctx.setFillColor(accent.cgColor)
    ctx.fillPath()
    draw(text: shot.sub, size: c.subSize, weight: .medium, color: muted,
         in: CGRect(x: side * 1.4, y: c.subY, width: c.w - side * 2.8, height: c.subSize * 3))

    // 设备
    let deviceH = c.deviceW * CGFloat(img.height) / CGFloat(img.width)
    drawPhone(ctx, image: img, center: CGPoint(x: c.w / 2, y: c.deviceTop + deviceH / 2),
              width: c.deviceW)

    NSGraphicsContext.restoreGraphicsState()
    guard let out = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
              URL(fileURLWithPath: outPath) as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("cannot encode \(outPath)")
    }
    CGImageDestinationAddImage(dest, out, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(outPath)") }
    print("wrote \(outPath)")
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count == 4 || args.count == 5, args[3] == "zh" || args[3] == "en" else {
    fputs("""
    usage: make_shots <rawDir> <outDir> <zh|en> [canvas]
      canvas: iphone65 (1284×2778, 默认) | iphone69 (1320×2868)
              ipad129  (2048×2732, 默认) | ipad13   (2064×2752)

    """, stderr)
    exit(2)
}
let imgDir = args[1], outDir = args[2], lang = args[3]
var canvas: Canvas?
if args.count == 5 {
    guard let named = Canvas.named(args[4]) else {
        fputs("unknown canvas: \(args[4])\n", stderr)
        exit(2)
    }
    canvas = named
}
let shots = lang == "zh" ? zhShots : enShots
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (i, shot) in shots.enumerated() {
    render(shot, lang: lang, canvas: canvas, imgDir: imgDir,
           outPath: "\(outDir)/\(String(format: "%02d", i + 1)).png")
}
