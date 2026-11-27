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
        Picker("Show on the map", selection: $filter) {
            ForEach(MapFilter.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
    }
}

/// The settings button over the map: Units for now (the gear in web/index.html).
struct SettingsButton: View {
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            Image(systemName: "slider.horizontal.3").frame(width: 22, height: 22).padding(11)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Units")
        .sheet(isPresented: $open) { UnitsView() }
    }
}

/// The first three often compared pairs and a way to all of them (the side panel's list on the website).
struct OftenComparedList: View {
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    var body: some View {
        let ps = atlas.pairs()
        if !ps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Often compared").font(.atlasSection).foregroundStyle(Palette.ink)
                    Spacer()
                    Button("All \(ps.count)") { nav.compare = CompareRoute(pairs: true) }.font(.atlasNote.weight(.bold))
                }
                ForEach(Array(ps.prefix(3).enumerated()), id: \.offset) { i, p in
                    let a = p["a"].string ?? "", b = p["b"].string ?? ""
                    Button { nav.compare = CompareRoute(a: a, b: b) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(i + 1)").font(.atlasNote.weight(.bold)).foregroundStyle(Palette.soft).frame(width: 14, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(atlas.name(a)) · \(atlas.name(b))").font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                                Text(p["link"].string ?? "").font(.atlasNote).foregroundStyle(Palette.soft)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.landEdge))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A place's figures as a row of cards: its growing season, its heat and what is planted most (glanceStrip in atlas.js).
struct GlanceStrip: View {
    let f: JSON
    @AppStorage(Units.key) private var units = ""

    static func has(_ f: JSON) -> Bool { f["climate"]["gst"].double != nil || f["climate"]["gdd"].double != nil || CompareText.lead(f) != nil }

    var body: some View {
        let _ = units
        let c = f["climate"]
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
            if let g = c["gst"].double {
                let (gi, _) = Copy.segment(Copy.growingSeason, g)
                card("Growing season", Units.deg(g), (gi >= 0 ? Copy.growingSeason[gi].0 + ", " : "") + ((c["lat"].double ?? 0) < 0 ? "October to April" : "April to October"))
            }
            if let d = c["gdd"].double {
                card("Heat", Units.heat(d).replacingOccurrences(of: " degree days", with: ""), "degree days" + (f["winkler"][0].string.map { ", Winkler \($0)" } ?? ""))
            }
        }
        if let l = CompareText.lead(f) {
            let pl = f["planted"], ha = pl["ha"].double ?? 1
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "PLANTED, \(l.y)\(l.about ? " (APPROXIMATE)" : "")").font(.atlasLabel).kerning(0.6).foregroundStyle(Palette.soft)
                ForEach(Array(pl["grapes"].array.filter { $0[0].string != "Other" }.prefix(4).enumerated()), id: \.offset) { _, g in
                    let p = Int(((g[1].double ?? 0) / ha * 100).rounded())
                    HStack(spacing: 8) {
                        Text(g[0].string ?? "").font(.atlasNote).foregroundStyle(Palette.ink).frame(width: 110, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Palette.fill)
                                Rectangle().fill(Palette.gold).frame(width: geo.size.width * CGFloat(p) / 100)
                            }
                        }
                        .frame(height: 8)
                        Text("\(p)%").font(.atlasNote).foregroundStyle(Palette.soft).frame(width: 36, alignment: .trailing)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.landEdge))
        }
    }

    private func card(_ label: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.atlasLabel).kerning(0.6).foregroundStyle(Palette.soft)
            Text(value).font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
            Text(note).font(.atlasNote).foregroundStyle(Palette.soft)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.landEdge))
    }
}
