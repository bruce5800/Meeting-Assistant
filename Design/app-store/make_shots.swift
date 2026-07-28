import AppKit
import ImageIO

// App Store marketing-screenshot compositor.
//   swiftc -O make_shots.swift -o make_shots && ./make_shots <rawDir> <outDir> <zh|en>
// Reads the device screenshots from <rawDir>, lays each onto a 1320×2868 canvas
// (the 6.9" size App Store Connect asks for, and exactly what the iPhone 17 Pro Max
// simulator produces) in the app icon's navy palette, and writes alpha-free PNGs.

let W: CGFloat = 1320, H: CGFloat = 2868

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

func render(_ shot: Shot, titleSize: CGFloat, imgDir: String, outPath: String) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("no context")
    }
    // 全局翻转 → 下面一律用左上角坐标系
    ctx.translateBy(x: 0, y: H)
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    // 背景渐变
    let grad = CGGradient(colorsSpace: space,
                          colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: H), options: [])

    // 标题 + 绿色短杠 + 副标题
    draw(text: shot.title, size: titleSize, weight: .bold, color: ink,
         in: CGRect(x: 64, y: 138 + (98 - titleSize) / 2, width: W - 128, height: 150))
    let bar = CGRect(x: W / 2 - 64, y: 318, width: 128, height: 11)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
    ctx.setFillColor(accent.cgColor)
    ctx.fillPath()
    draw(text: shot.sub, size: 48, weight: .medium, color: muted,
         in: CGRect(x: 86, y: 372, width: W - 172, height: 150))

    // 手机
    let img = loadImage("\(imgDir)/\(shot.file)")
    let phoneW: CGFloat = 980
    let phoneH = phoneW * CGFloat(img.height) / CGFloat(img.width)
    drawPhone(ctx, image: img, center: CGPoint(x: W / 2, y: 596 + phoneH / 2), width: phoneW)

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
guard args.count == 4, args[3] == "zh" || args[3] == "en" else {
    fputs("usage: make_shots <rawDir> <outDir> <zh|en>\n", stderr)
    exit(2)
}
let imgDir = args[1], outDir = args[2]
let shots = args[3] == "zh" ? zhShots : enShots
let titleSize: CGFloat = args[3] == "zh" ? 98 : 84
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (i, shot) in shots.enumerated() {
    render(shot, titleSize: titleSize, imgDir: imgDir,
           outPath: "\(outDir)/\(String(format: "%02d", i + 1)).png")
}
