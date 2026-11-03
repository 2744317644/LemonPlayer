import SwiftUI
import LemonSubtitle

/// SRT/VTT 自绘字幕层（可调样式）。ASS 仍由内核 libass 渲染，不走这里。
struct SubtitleOverlayView: View {
    let lines: [String]
    let style: SubtitleStyle

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: style.fontSize, weight: .semibold))
                    .foregroundStyle(Color(hex: style.textColorHex))
                    .shadow(color: Color(hex: style.outlineColorHex), radius: style.outlineWidth)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(style.backgroundOpacity))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    var hexString: String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "#FFFFFF"
        #endif
    }
}
