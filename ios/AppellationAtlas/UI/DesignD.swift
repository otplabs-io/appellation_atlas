import CoreText
import SwiftUI

// Design D, "daylight": the pieces the screens share. The sizes, colors and type are the website's (the D block in
// web/atlas.css), so the app and the site match.

/// The website's two typefaces, from its own font files (web/assets/fonts, copied to Fonts/), registered at launch.
enum DFont {
    static func register() {
        for u in Bundle.main.urls(forResourcesWithExtension: "woff2", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Poppins, for names and headings (--display). Sizes follow Dynamic Type from the given style.
    static func display(_ size: CGFloat, _ w: Font.Weight = .bold, relativeTo s: Font.TextStyle = .body) -> Font {
        Font.custom(w == .heavy || w == .black ? "Poppins-ExtraBold" : w == .semibold ? "Poppins-SemiBold" : "Poppins-Bold", size: size, relativeTo: s)
    }
    /// Nunito Sans, for everything else (--body).
    static func text(_ size: CGFloat, _ w: Font.Weight = .regular, relativeTo s: Font.TextStyle = .body) -> Font {
        let n = switch w { case .heavy, .black: "ExtraBold"; case .bold: "Bold"; case .semibold: "SemiBold"; default: "Regular" }
        return Font.custom("NunitoSans12ptExtraLight12pt-" + n, size: size, relativeTo: s)
    }
}

extension Palette {
    /// --card, --line, --page, --ground and --edge in web/atlas.css.
    static let card = Color(light: 0xFFFFFF, dark: 0x16202A)
    static let line = Color(light: 0xE2E9EE, dark: 0x2A3743)
    static let ground = Color(light: 0xE9EEF2, dark: 0x0A1016)
    static let edge = Color(light: 0x1F2D3A, dark: 0xE6ECF1).opacity(0.12)
    static let tealDeep = Color(light: 0x17575A, dark: 0x4FA3A7)
}

/// A panel floating over the map: the paper color, nearly opaque, over a blur (.glass in web/atlas.css).
struct GlassPanel: ViewModifier {
    var radius: CGFloat = 28
    var opacity: Double = 0.94
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.paper.opacity(opacity)))
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.edge, lineWidth: 1))
            .shadow(color: Color(light: 0x1F2D3A, dark: 0x000000).opacity(0.14), radius: 12, y: 10)
    }
}

/// A small control over the map (.pill in web/atlas.css).
struct GlassPill: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.paper.opacity(0.9)))
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.edge, lineWidth: 1))
            .shadow(color: Color(light: 0x1F2D3A, dark: 0x000000).opacity(0.12), radius: 4, y: 2)
    }
}

/// A white card with a hairline edge (CARD in the design).
struct CardBox: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}

extension View {
    func glassPanel(_ radius: CGFloat = 28, opacity: Double = 0.94) -> some View { modifier(GlassPanel(radius: radius, opacity: opacity)) }
    func glassPill(_ radius: CGFloat) -> some View { modifier(GlassPill(radius: radius)) }
    func cardBox(_ radius: CGFloat = 20) -> some View { modifier(CardBox(radius: radius)) }
}

/// The small capitals over a block: GROWING SEASON, HOW THE PLACES COMPARE.
struct Caps: View {
    let text: String
    var color: Color = Palette.soft
    init(_ text: String, color: Color = Palette.soft) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.text(11.5, .heavy, relativeTo: .caption2)).kerning(0.7).foregroundStyle(color)
    }
}

/// A round button over the map, 48 points on the home screen and 44 on a place.
struct RoundButton<Label: View>: View {
    var size: CGFloat = 48
    let action: () -> Void
    @ViewBuilder var label: Label
    var body: some View {
        Button(action: action) {
            label.frame(width: size, height: size).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassPill(size / 2)
    }
}

/// A row of choices in a grey well, the chosen one in ink (.filter in web/atlas.css).
struct DSegmented: View {
    let options: [(String, String)]
    @Binding var selection: String
    var height: CGFloat = 36
    var size: CGFloat = 13
    var label = ""
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { tag, text in
                let on = selection == tag
                Button { selection = tag } label: {
                    Text(text).font(.text(size, on ? .heavy : .bold, relativeTo: .footnote))
                        .foregroundStyle(on ? Palette.paper : Palette.soft)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: height)
                        .background(on ? Palette.ink : .clear, in: RoundedRectangle(cornerRadius: height > 34 ? 10 : 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(height > 34 ? 4 : 3)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: height > 34 ? 14 : 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The search box: a magnifier and the words (.search in web/atlas.css).
struct DSearchBox: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    var prompt = "Search a country, region or appellation"
    var height: CGFloat = 48
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.soft)
            TextField(prompt, text: $query)
                .font(.text(15, relativeTo: .body))
                .foregroundStyle(Palette.ink)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty || focused.wrappedValue {
                Button { query = ""; focused.wrappedValue = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.soft) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.landEdge, lineWidth: 1))
    }
}

/// The map's key: a card down the side at home on a phone, a pill along the bottom on an iPad (.key in web/atlas.css).
struct MapKeyD: View {
    var row = false
    var body: some View {
        let items: [Tone] = [.essential, .benchmark, .inside, .other]
        let layout = row ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        layout {
            ForEach(items, id: \.self) { t in
                HStack(spacing: row ? 6 : 8) {
                    Rectangle().fill(Palette.tone(t)).frame(width: 14, height: 10)
                    Text(Copy.tone(t).one).font(.text(12, relativeTo: .caption)).foregroundStyle(Palette.soft).fixedSize()
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, row ? 8 : 10)
        .glassPill(row ? 14 : 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Key: darkest gold, essential benchmark; gold, benchmark; light gold, inside a benchmark; grey, other")
    }
}

/// The back arrow in the design's teal.
struct BackChevron: View {
    var body: some View { Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.teal) }
}

/// A white circle with the back arrow, at the top left of Compare, the pairs and Settings.
struct CircleBack: View {
    let action: () -> Void
    var label = "Back"
    var body: some View {
        Button(action: action) {
            BackChevron().frame(width: 44, height: 44)
                .background(Palette.card, in: Circle())
                .overlay(Circle().stroke(Palette.edge, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A rounded button with words: white with an edge, or teal (.cpill in web/atlas.css).
struct PillLink: View {
    let title: String
    var teal = false
    var height: CGFloat = 40
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.text(13, .heavy, relativeTo: .footnote))
                .foregroundStyle(teal ? Palette.paper : Palette.ink)
                .padding(.horizontal, 14).frame(height: height)
                .background(teal ? Palette.teal : Palette.card, in: Capsule())
                .overlay(Capsule().stroke(teal ? Palette.teal : Palette.edge, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
