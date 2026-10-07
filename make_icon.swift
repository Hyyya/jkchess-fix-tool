// 生成「金铲铲修复工具」应用图标 1024x1024 PNG
import AppKit

let size = NSSize(width: 1024, height: 1024)
let img = NSImage(size: size)
img.lockFocus()

// 背景：橙色渐变
let grad = NSGradient(colors: [
    NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.20, alpha: 1),
    NSColor(calibratedRed: 0.93, green: 0.40, blue: 0.06, alpha: 1),
])!
grad.draw(in: NSRect(origin: .zero, size: size), angle: -60)

// 中间白色大扳手(修复语义)
let cfg = NSImage.SymbolConfiguration(pointSize: 560, weight: .bold)
if let sym = NSImage(systemSymbolName: "wrench.and.screwdriver.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let sr = NSRect(x: (1024 - 760) / 2, y: (1024 - 760) / 2, width: 760, height: 760)
    sym.isTemplate = true
    NSColor.white.set()
    sym.draw(in: sr)
}

// 底部游戏控制器(金铲铲语义)，白色
let cfg2 = NSImage.SymbolConfiguration(pointSize: 200, weight: .bold)
if let g = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg2) {
    let gr = NSRect(x: (1024 - 320) / 2, y: 60, width: 320, height: 240)
    g.isTemplate = true
    NSColor.white.set()
    g.draw(in: gr)
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("图标生成失败\n", stderr); exit(1)
}
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/jk_icon_1024.png")
try! png.write(to: out)
print("图标已生成: \(out.path)")
