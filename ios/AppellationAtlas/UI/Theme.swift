import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// A color with a light and a dark version, picked by the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// The Atlas palette. Light values are the website's design tokens (web/assets/app.css and web/atlas.css). Dark values
/// keep the same meaning: gold for Benchmark regions, grey for the rest, a stronger shade for better known places.
enum Palette {
    static let ink = Color(light: 0x1F2D3A, dark: 0xE6ECF1)
    static let soft = Color(light: 0x47525C, dark: 0xA3AFBA)
    static let coral = Color(light: 0xD9482B, dark: 0xF06A4C)
    static let coralText = Color(light: 0xB93414, dark: 0xF58B70)
    static let gold = Color(light: 0xE9B44C, dark: 0xE9B44C)
    static let goldTint = Color(light: 0xF9EBC6, dark: 0x4A3C1A)
    static let teal = Color(light: 0x1F6F73, dark: 0x5FB8BC)
    static let paper = Color(light: 0xFCFAF5, dark: 0x0F161D)
    static let fill = Color(light: 0xEEF2F5, dark: 0x1D2833)
    static let ocean = Color(light: 0xCFE3EE, dark: 0x0E2231)
    static let oceanHigh = Color(light: 0xE4F0F6, dark: 0x1A3A50)
    static let land = Color(light: 0xF7F8F9, dark: 0x24313D)
    static let landEdge = Color(light: 0xC3CED6, dark: 0x40505D)
    static let target = Color(light: 0xD9482B, dark: 0xF06A4C)
    static let sibling = Color(light: 0xE2E9EE, dark: 0x2A3743)
    static let regionStroke = Color(light: 0xFFFFFF, dark: 0x0E1820)
    static let halo = Color(light: 0xFFFFFF, dark: 0x0E1820)
    static let graticule = Color(light: 0xFFFFFF, dark: 0x2E5068)

    /// Benchmark (gold) shades by tier, 0 for places with no score.
    static let gold4 = [Color(light: 0xEEF2F5, dark: 0x2A3743), Color(light: 0xF9EBC6, dark: 0x5A4820),
                        Color(light: 0xF5D58A, dark: 0x8A6922), Color(light: 0xE9B44C, dark: 0xC2902C), Color(light: 0xC98F22, dark: 0xF0BE58)]
    /// Emerging (grey) shades by tier.
    static let grey4 = [Color(light: 0xEEF2F5, dark: 0x2A3743), Color(light: 0xDDE3E8, dark: 0x334150),
                        Color(light: 0xCBD3DA, dark: 0x445462), Color(light: 0xB6C1CA, dark: 0x5A6A78), Color(light: 0x9EABB6, dark: 0x7A8996)]

    static func shade(benchmark: Bool, tier: Int) -> Color {
        benchmark ? gold4[max(1, tier)] : grey4[tier]
    }

    static let red = Color(light: 0x8E2F3C, dark: 0xC0566A)
    static let pink = Color(light: 0xD98C95, dark: 0xE3A0A8)
    static let monthTemp = Color(light: 0xE5DCC6, dark: 0x3A3426)
    static let monthRain = Color(light: 0xCFE3EE, dark: 0x1F3A4C)

    static func rock(_ id: String) -> Color {
        switch id {
        case "limestone", "chalk": Color(light: 0xEFE9D8, dark: 0x3B3829)
        case "marl": Color(light: 0xE3DBC4, dark: 0x3A3426)
        case "volcanic": Color(light: 0xD9C9C6, dark: 0x3E3130)
        case "granite": Color(light: 0xE6D3CF, dark: 0x423331)
        case "schist", "shale": Color(light: 0xD5DCE2, dark: 0x2E3945)
        case "gravel", "sand", "sandstone": Color(light: 0xF3E4C2, dark: 0x43391F)
        default: Color(light: 0xE4DFD3, dark: 0x35322B)
        }
    }
}

/// The type styles, after the website's ts-* classes, set in the system font so they scale with Dynamic Type.
extension Font {
    static let atlasTitle = Font.system(.largeTitle, design: .default).weight(.heavy)
    static let atlasSection = Font.system(.headline).weight(.bold)
    static let atlasLabel = Font.system(.caption2).weight(.heavy)
    static let atlasValue = Font.system(.title3).weight(.bold)
    static let atlasNote = Font.system(.caption)
    static let atlasBody = Font.system(.subheadline)
    static let atlasEyebrow = Font.system(.caption).weight(.heavy)
}
