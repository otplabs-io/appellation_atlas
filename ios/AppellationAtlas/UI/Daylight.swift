import SwiftUI

/// "Show on the map": all places, the benchmarks, or the essential benchmarks only (the filter in web/index.html).
enum MapFilter: String, CaseIterable {
    case all, bench, essential
    var label: String { switch self { case .all: "All places"; case .bench: "Benchmarks"; case .essential: "Essential" } }
    static let key = "mapFilter"
}

extension Atlas {
    /// A place's fill on the map under the filter: places it leaves out stay plain land (mapShade in atlas.js).
    func mapShade(_ id: String) -> Color {
        let t = tone(id)
        switch MapFilter(rawValue: UserDefaults.standard.string(forKey: MapFilter.key) ?? "all") ?? .all {
        case .bench where t == .inside || t == .other: return Palette.gold4[0]
        case .essential where t != .essential: return Palette.gold4[0]
        default: return Palette.tone(t)
        }
    }
}

struct MapFilterPicker: View {
    @AppStorage(MapFilter.key) private var filter = MapFilter.all.rawValue
    var body: some View {
        DSegmented(options: MapFilter.allCases.map { ($0.rawValue, $0.label) }, selection: $filter, label: "Show on the map")
    }
}

/// Settings, over the map: the sliders in a round button (the gear in web/index.html).
struct SettingsButton: View {
    var size: CGFloat = 48
    var plain = false   // the white circle in the iPad panel's title row
    @Environment(Nav.self) private var nav
    var body: some View {
        let icon = Image(systemName: "slider.horizontal.3").font(.system(size: size > 44 ? 18 : 16, weight: .semibold)).foregroundStyle(Palette.ink)
        Group {
            if plain {
                Button { nav.settings = true } label: {
                    icon.frame(width: size, height: size).background(Palette.card, in: Circle()).overlay(Circle().stroke(Palette.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                RoundButton(size: size) { nav.settings = true } label: { icon }
            }
        }
        .accessibilityLabel("Settings")
    }
}

/// The first three often compared pairs and a way to all of them (the side panel's list on the website).
struct OftenComparedList: View {
    var count = 3
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    var body: some View {
        let ps = atlas.pairs()
        if !ps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Often compared").font(.display(15, .bold, relativeTo: .headline)).foregroundStyle(Palette.ink)
                    Spacer()
                    Button("All \(ps.count)") { nav.compare = CompareRoute(pairs: true) }
                        .font(.text(13, .heavy, relativeTo: .footnote)).foregroundStyle(Palette.teal)
                }
                ForEach(Array(ps.prefix(count).enumerated()), id: \.offset) { i, p in
                    let a = p["a"].string ?? "", b = p["b"].string ?? ""
                    Button { nav.compare = CompareRoute(a: a, b: b) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)").font(.display(12, .heavy, relativeTo: .caption)).foregroundStyle(Palette.soft)
                                .frame(width: 18, alignment: .trailing).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(atlas.name(a)) · \(atlas.name(b))").font(.text(13.5, .heavy, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading)
                                Text(p["link"].string ?? "").font(.text(12, relativeTo: .caption)).foregroundStyle(Palette.soft)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .cardBox(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A place's figures as cards: what is planted most, its growing season and its heat (glanceStrip in atlas.js).
/// On a phone they sit in a row to swipe through; on an iPad the plantings run across the top of a grid.
struct GlanceStrip: View {
    let f: JSON
    var row = true
    @AppStorage(Units.key) private var units = ""

    static func has(_ f: JSON) -> Bool { f["climate"]["gst"].double != nil || f["climate"]["gdd"].double != nil || hasPlanted(f) }
    /// Its own plantings, or failing those the nearest wider area's (planted_wider, from wider_planted in src/atlas.py).
    static func hasPlanted(_ f: JSON) -> Bool { CompareText.lead(f) != nil || !f["planted_wider"]["grapes"].array.isEmpty }
    static func count(_ f: JSON) -> Int { [f["climate"]["gst"].double != nil, f["climate"]["gdd"].double != nil, hasPlanted(f)].filter { $0 }.count }

    var body: some View {
        let _ = units
        let c = f["climate"]
        if row {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    if Self.hasPlanted(f) { planted(width: 236, label: 92, gap: 8, size: 13).frame(width: 236) }
                    if let g = c["gst"].double { season(g, c, bar: true).frame(width: 200) }
                    if let d = c["gdd"].double { heat(d).frame(width: 200) }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -20)
        } else {
            VStack(spacing: 10) {
                if Self.hasPlanted(f) { planted(width: nil, label: 110, gap: 10, size: 13.5) }
                HStack(alignment: .top, spacing: 10) {
                    if let g = c["gst"].double { season(g, c, bar: false) }
                    if let d = c["gdd"].double { heat(d) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func planted(width: CGFloat?, label: CGFloat, gap: CGFloat, size: CGFloat) -> some View {
        // its own figures as shares of its vineyard, or the wider area's, already in percent
        let rows: [(String, Int)], head: String
        if let l = CompareText.lead(f) {
            let pl = f["planted"], ha = pl["ha"].double ?? 1
            rows = pl["grapes"].array.filter { $0[0].string != "Other" }.prefix(4).map { ($0[0].string ?? "", Int((($0[1].double ?? 0) / ha * 100).rounded())) }
            head = "PLANTED, \(l.y)\(l.about ? " (APPROXIMATE)" : "")"
        } else {
            let w = f["planted_wider"]
            rows = w["grapes"].array.map { ($0[0].string ?? "", $0[1].int ?? 0) }
            head = "PLANTED IN \((w["name"].string ?? "").uppercased()), \(w["year"].int ?? 0)\(w["about"].bool == true ? " (APPROXIMATE)" : "")"
        }
        return VStack(alignment: .leading, spacing: row ? 9 : 8) {
            Text(verbatim: head).font(.text(11.5, .heavy, relativeTo: .caption2)).kerning(0.7).foregroundStyle(Palette.soft)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                let p = r.1, name = r.0
                HStack(spacing: gap) {
                    Text(name).font(.text(size, relativeTo: .footnote)).foregroundStyle(Palette.ink).lineLimit(1).frame(width: label, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Palette.fill)
                            Rectangle().fill(Palette.gold).frame(width: geo.size.width * CGFloat(p) / 100)
                        }
                    }
                    .frame(height: 8)
                    Text("\(p)%").font(.text(size, relativeTo: .footnote)).foregroundStyle(Palette.soft).frame(width: row ? 34 : 38, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBox(20)
    }

    private func season(_ g: Double, _ c: JSON, bar: Bool) -> some View {
        let (gi, _) = Copy.segment(Copy.growingSeason, g)
        return card("Growing season", Units.deg(g), (gi >= 0 ? Copy.growingSeason[gi].0 + ", " : "") + ((c["lat"].double ?? 0) < 0 ? "October to April" : "April to October")) {
            if bar {
                HStack(spacing: 2) {
                    ForEach(0..<6, id: \.self) { k in Rectangle().fill(k == gi ? Palette.gold : Palette.fill).frame(height: 10) }
                }
                .padding(.top, 4)
                .accessibilityHidden(true)
            }
        }
    }

    private func heat(_ d: Double) -> some View {
        card("Heat", Units.heat(d).replacingOccurrences(of: " degree days", with: ""), "degree days" + (f["winkler"][0].string.map { ", Winkler \($0)" } ?? "")) { EmptyView() }
    }

    private func card<Extra: View>(_ label: String, _ value: String, _ note: String, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: row ? 6 : 4) {
            Caps(label)
            Text(value).font(.display(26, .bold, relativeTo: .title)).foregroundStyle(Palette.ink)
            Text(note).font(.text(13, relativeTo: .footnote)).foregroundStyle(Palette.soft).fixedSize(horizontal: false, vertical: true)
            extra()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBox(20)
        .accessibilityElement(children: .combine)
    }
}
