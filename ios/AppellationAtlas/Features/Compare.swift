import SwiftUI

/// What the compare sheet shows: two places side by side, one place waiting for a second, or the often compared pairs.
/// Mirrors renderCompare and renderPairs in web/atlas.js.
struct CompareRoute: Identifiable, Hashable {
    var a: String?
    var b: String?
    var pairs = false
    var id: String { pairs ? "pairs" : "\(a ?? "")|\(b ?? "")" }
}

extension Atlas {
    /// The often compared pairs (public/compare.json), with both outlines.
    func pairs() -> [JSON] { (comparePairs ?? []) }
    func pair(_ a: String, _ b: String) -> JSON? {
        pairs().first { ($0["a"].string == a && $0["b"].string == b) || ($0["a"].string == b && $0["b"].string == a) }
    }
}

/// A place's outline (the "outline" in its facts: an SVG path in kilometers, y down).
struct Outline {
    let w: Double, h: Double, path: Path
    init?(_ j: JSON) {
        guard let w = j["w"].double, let h = j["h"].double, let d = j["d"].string, w > 0, h > 0 else { return nil }
        self.w = w; self.h = h
        var p = Path(), nums: [Double] = [], cmd: Character = "M"
        func flush() {
            var i = 0
            while i + 1 < nums.count {
                let pt = CGPoint(x: nums[i], y: nums[i + 1])
                if cmd == "M" && i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                i += 2
            }
            nums = []
        }
        var tok = ""
        for c in d {
            if c == "M" || c == "L" || c == "Z" {
                if !tok.isEmpty { nums.append(Double(tok) ?? 0); tok = "" }
                flush()
                if c == "Z" { p.closeSubpath() } else { cmd = c }
            } else if c == " " {
                if !tok.isEmpty { nums.append(Double(tok) ?? 0); tok = "" }
            } else { tok.append(c) }
        }
        if !tok.isEmpty { nums.append(Double(tok) ?? 0) }
        flush()
        path = p
    }
    var size: Double { max(w, h) }
}

/// An outline in its tone, drawn at k points per kilometer.
struct OutlineView: View {
    let o: Outline
    let k: Double
    let tone: Tone
    var body: some View {
        o.path
            .applying(CGAffineTransform(scaleX: k, y: k))
            .fill(tone == .other ? Palette.grey4[2] : Palette.tone(tone))
            .overlay(o.path.applying(CGAffineTransform(scaleX: k, y: k)).stroke(Palette.ink.opacity(0.35), lineWidth: 0.75))
            .frame(width: max(2, o.w * k), height: max(2, o.h * k))
            .accessibilityHidden(true)
    }
}

/// Sentences built only from the Atlas's own figures (placesText in web/atlas.js).
enum CompareText {
    static func dry(_ k: String?) -> String? {
        guard let k, k.count >= 2 else { return nil }
        if k.hasPrefix("B") { return "an arid climate" }
        return ["f": "no dry season", "s": "dry summers", "w": "dry winters", "m": "a short dry season"][String(k[k.index(after: k.startIndex)])]
    }
    static func lat(_ c: JSON) -> String {
        guard let l = c["lat"].double else { return "" }
        return "\(Int(abs(l).rounded()))°\(l < 0 ? "S" : "N")"
    }
    struct Lead { let g: String; let p: Int; let y: Int; let about: Bool; let two: String }
    /// The leading grape and its share, when the figures are for the place itself.
    static func lead(_ f: JSON) -> Lead? {
        let pl = f["planted"]
        guard ["own", "within"].contains(pl["scope"].string ?? ""), let ha = pl["ha"].double, ha > 0 else { return nil }
        let gs = pl["grapes"].array.filter { $0[0].string != "Other" }
        guard let g = gs.first, let name = g[0].string else { return nil }
        let pct: (JSON) -> Int = { Int((($0[1].double ?? 0) / ha * 100).rounded()) }
        return Lead(g: name, p: pct(g), y: pl["year"].int ?? 0, about: pl["whites_older"].bool == true,
                    two: gs.prefix(2).map { "\($0[0].string ?? "") \(pct($0))%" }.joined(separator: ", "))
    }
    static func places(_ fa: JSON, _ fb: JSON) -> String {
        let A = fa["name"].string ?? "", B = fb["name"].string ?? ""
        let ca = fa["climate"], cb = fb["climate"]
        var s: [String] = []
        if let ga = ca["gst"].double, let gb = cb["gst"].double {
            let ta = Units.tN(ga), tb = Units.tN(gb)
            s.append(ta == tb ? "Both have a growing season that averages \(Units.deg(ga))."
                     : "\(A)'s growing season averages \(Units.deg(ga)), \(abs(ta - tb))\(Units.tU) \(ta > tb ? "warmer" : "cooler") than \(B)'s \(Units.deg(gb)).")
        }
        if let wa = fa["winkler"][0].string, let wb = fb["winkler"][0].string {
            s.append(wa == wb ? "Both are Winkler region \(wa)." : "\(A) is Winkler region \(wa) and \(B) is region \(wb).")
        }
        if let da = dry(ca["koppen"].string), let db = dry(cb["koppen"].string) {
            s.append(da == db ? (da == "no dry season" ? "Neither has a dry season." : "Both have \(da).") : "\(A) has \(da), while \(B) has \(db).")
        }
        if let la = lead(fa), let lb = lead(fb) {
            let ab: (Lead) -> String = { $0.about ? "about " : "" }
            s.append(la.g == lb.g ? "\(la.g) leads in both: \(ab(la))\(la.p)% of the vines in \(A) (\(la.y)) and \(ab(lb))\(lb.p)% in \(B) (\(lb.y))."
                     : "The leading grape in \(A) is \(la.g), \(ab(la))\(la.p)% of the vines (\(la.y)). In \(B) it is \(lb.g), \(ab(lb))\(lb.p)% (\(lb.y)).")
        }
        if let ea = fa["terrain"]["elev"][1].double, let eb = fb["terrain"]["elev"][1].double {
            s.append("The land sits at about \(Units.elev(ea)) in \(A) and \(Units.elev(eb)) in \(B).")
        }
        return s.joined(separator: " ")
    }
}

struct CompareSheet: View {
    @State var route: CompareRoute
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if route.pairs { PairsList(route: $route) } else { ComparePage(route: $route) }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ComparePage: View {
    @Binding var route: CompareRoute
    @Environment(Atlas.self) private var atlas
    @Environment(\.horizontalSizeClass) private var width
    @AppStorage(Units.key) private var units = ""
    @State private var query = ""

    var body: some View {
        let _ = units
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                chooser
                if let a = route.a, let b = route.b, let fa = atlas.facts(a), let fb = atlas.facts(b) {
                    compared(a, fa, b, fb)
                } else {
                    picker
                }
            }
            .padding(20)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Compare")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Other pairs") { route = CompareRoute(pairs: true) } }
        }
    }

    private var chooser: some View {
        FlowLayout(spacing: 8) {
            chip(route.a) { route.a = route.b; route.b = nil }
            Text("and").font(.atlasNote).foregroundStyle(Palette.soft)
            chip(route.b) { route.b = nil }
        }
    }

    @ViewBuilder private func chip(_ id: String?, remove: @escaping () -> Void) -> some View {
        if let id {
            HStack(spacing: 8) {
                Rectangle().fill(Palette.tone(atlas.tone(id))).frame(width: 10, height: 10)
                Text(atlas.name(id)).font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                Button(action: remove) { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.mini)
                    .accessibilityLabel("Choose another place instead of \(atlas.name(id))")
            }
            .padding(.leading, 12).padding(.trailing, 4).frame(minHeight: 40)
            .overlay(Capsule().stroke(Palette.landEdge))
        } else {
            Text("Choose a place").font(.subheadline).foregroundStyle(Palette.soft)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .overlay(Capsule().stroke(Palette.landEdge, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.soft)
                TextField(route.a == nil ? "Search for the first place" : "Search a place to compare with \(atlas.name(route.a!))", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(12).background(Palette.fill, in: RoundedRectangle(cornerRadius: 14))
            ForEach(atlas.search(query, limit: 12).filter { $0.id != route.a }) { p in
                Button { pick(p.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text([p.kind, p.country].filter { !$0.isEmpty }.joined(separator: ", ")).font(.atlasNote).foregroundStyle(Palette.soft)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
            if let a = route.a, query.isEmpty {
                let near = atlas.pairs().compactMap { p -> String? in p["a"].string == a ? p["b"].string : p["b"].string == a ? p["a"].string : nil }
                if !near.isEmpty {
                    SubCaption("Often compared with \(atlas.name(a))")
                    FlowLayout(spacing: 6) {
                        ForEach(near, id: \.self) { id in
                            Button { pick(id) } label: {
                                HStack(spacing: 6) { Rectangle().fill(Palette.tone(atlas.tone(id))).frame(width: 10, height: 10); Text(atlas.name(id)) }
                                    .font(.subheadline.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(Palette.fill, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func pick(_ id: String) {
        query = ""
        if route.a == nil { route.a = id } else { route.b = id }
    }

    @ViewBuilder private func compared(_ a: String, _ fa: JSON, _ b: String, _ fb: JSON) -> some View {
        let p = atlas.pair(a, b)
        let box: Double = width == .regular ? 220 : 150
        shapes(a, fa, b, fb, box)
        if p?["tag"].string == "different-grapes" {
            Text("\(atlas.name(a)) and \(atlas.name(b)) are made from different grapes, so this compares the wines typical of each, not one grape in two places.")
                .font(.atlasBody).foregroundStyle(Palette.ink).padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.goldTint, in: RoundedRectangle(cornerRadius: 14))
        }
        let text = CompareText.places(fa, fb)
        if !text.isEmpty {
            heading("How the places compare")
            Text(text).font(.atlasBody).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
        heading("Side by side")
        charts(fa, fb)
        table(a, fa, b, fb)
        if let w = p?["wines"].array, !w.isEmpty {
            heading("How the wines compare")
            ForEach(Array(w.enumerated()), id: \.offset) { _, x in
                VStack(alignment: .leading, spacing: 4) {
                    Text(x["head"].string ?? "").font(.atlasSection).foregroundStyle(Palette.ink)
                    Text(x["text"].string ?? "").font(.atlasBody).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        heading("Sources")
        sources(fa, fb, p)
        Button("Other often compared pairs") { route = CompareRoute(pairs: true) }.font(.atlasNote)
    }

    private func heading(_ t: String) -> some View { Text(t).font(.atlasSection).foregroundStyle(Palette.ink).padding(.top, 6) }

    @ViewBuilder private func shapes(_ a: String, _ fa: JSON, _ b: String, _ fb: JSON, _ box: Double) -> some View {
        let oa = Outline(fa["outline"]), ob = Outline(fb["outline"])
        VStack(spacing: 10) {
            if let oa, let ob {
                let s = box / max(oa.size, ob.size)
                let loose = min(oa.size, ob.size) * s < box / 10
                let smallIsA = oa.size < ob.size
                let zoom = !loose && min(oa.size, ob.size) * s < box / 4
                let z = (box / 2 / min(oa.size, ob.size) / s).rounded()
                HStack(alignment: .bottom, spacing: 12) {
                    column(a, fa, art: HStack(alignment: .bottom, spacing: 10) {
                        OutlineView(o: oa, k: loose ? box / oa.size : s, tone: atlas.tone(a))
                        if zoom && smallIsA { inset(oa, s * z, a, z) }
                    }, box: box)
                    column(b, fb, art: HStack(alignment: .bottom, spacing: 10) {
                        OutlineView(o: ob, k: loose ? box / ob.size : s, tone: atlas.tone(b))
                        if zoom && !smallIsA { inset(ob, s * z, b, z) }
                    }, box: box)
                }
                if loose {
                    Text("Too different in size to draw to one scale. \(atlas.name(oa.size > ob.size ? a : b)) is about \(fmt((max(oa.size, ob.size) / min(oa.size, ob.size)).rounded())) times as long.")
                        .font(.atlasNote).foregroundStyle(Palette.soft).multilineTextAlignment(.center)
                } else {
                    scaleBar(pxkm: s, box: box)
                }
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    column(a, fa, art: Text("No outline").font(.atlasNote).foregroundStyle(Palette.soft), box: 40)
                    column(b, fb, art: Text("No outline").font(.atlasNote).foregroundStyle(Palette.soft), box: 40)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.landEdge))
    }

    private func inset(_ o: Outline, _ k: Double, _ id: String, _ z: Double) -> some View {
        VStack(spacing: 2) {
            OutlineView(o: o, k: k, tone: atlas.tone(id))
            Text("×\(Int(z))").font(.atlasNote).foregroundStyle(Palette.soft)
        }
        .padding(6)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.landEdge, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func column(_ id: String, _ f: JSON, art: some View, box: Double) -> some View {
        VStack(spacing: 4) {
            art.frame(height: box, alignment: .bottom)
            HStack(spacing: 6) {
                Rectangle().fill(Palette.tone(atlas.tone(id))).frame(width: 10, height: 10)
                Text(atlas.name(id)).font(.atlasSection).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            }
            let country = atlas.places[id]?.country ?? ""
            Text([country == atlas.name(id) ? "" : country, CompareText.lat(f["climate"])].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.atlasNote).foregroundStyle(Palette.soft)
        }
        .frame(maxWidth: .infinity)
    }

    /// A scale bar about a third of the box wide, in round miles or kilometers (scaleBar in web/atlas.js).
    private func scaleBar(pxkm: Double, box: Double) -> some View {
        let u = Units.us(.dist) ? 1.609344 : 1, want = box / 3 / pxkm / u, p = pow(10, floor(log10(want)))
        let n = [1, 2, 5, 10].map { $0 * p }.filter { $0 <= want }.last ?? p
        return HStack(spacing: 8) {
            Rectangle().fill(.clear).frame(width: n * u * pxkm, height: 5)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.soft).frame(height: 1) }
                .overlay(alignment: .leading) { Rectangle().fill(Palette.soft).frame(width: 1) }
                .overlay(alignment: .trailing) { Rectangle().fill(Palette.soft).frame(width: 1) }
            Text("\(fmt(n)) \(Units.us(.dist) ? (n == 1 ? "mile" : "miles") : "km") · both drawn to the same scale")
                .font(.atlasNote).foregroundStyle(Palette.soft)
        }
    }

    @ViewBuilder private func charts(_ fa: JSON, _ fb: JSON) -> some View {
        let cs = [fa, fb].filter { !$0["climate"]["tavg"].array.isEmpty }
        if !cs.isEmpty {
            SubCaption("Average temperature by month, \(Units.tU)")
            let grid = width == .regular ? [GridItem(.flexible(), spacing: 20), GridItem(.flexible())] : [GridItem(.flexible())]
            LazyVGrid(columns: grid, alignment: .leading, spacing: 12) {
                ForEach(Array(cs.enumerated()), id: \.offset) { _, f in
                    let c = f["climate"]
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(f["name"].string ?? "") · \(Units.deg(c["gst"].double ?? 0)) season").font(.atlasNote.weight(.semibold)).foregroundStyle(Palette.ink)
                        MonthsChart(values: c["tavg"].doubles.map(toF), shown: c["tavg"].doubles.map { Double(Units.tN($0)) }, unit: Units.tU,
                                    season: Palette.coral, base: Palette.monthTemp, south: (c["lat"].double ?? 0) < 0, labels: true)
                    }
                }
            }
        }
    }

    private func table(_ a: String, _ fa: JSON, _ b: String, _ fb: JSON) -> some View {
        let ca = fa["climate"], cb = fb["climate"]
        let planted: (JSON) -> String = { f in CompareText.lead(f).map { "\($0.two) (\($0.y)\($0.about ? ", approximate" : ""))" } ?? "" }
        let elev: (JSON) -> String = { f in f["terrain"]["elev"][1].double.map { Units.elev($0) } ?? "" }
        let rows: [(String, String, String)] = [
            ("Growing season", ca["gst"].double.map { Units.deg($0) } ?? "", cb["gst"].double.map { Units.deg($0) } ?? ""),
            ("Heat", ca["gdd"].double.map { Units.heat($0) } ?? "", cb["gdd"].double.map { Units.heat($0) } ?? ""),
            ("Winkler region", fa["winkler"][0].string ?? "", fb["winkler"][0].string ?? ""),
            ("Climate", ca["koppen_name"].string ?? "", cb["koppen_name"].string ?? ""),
            ("Planted", planted(fa), planted(fb)),
            ("Elevation", elev(fa), elev(fb)),
        ].filter { !$0.1.isEmpty || !$0.2.isEmpty }
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                Text(atlas.name(a)).font(.atlasLabel).foregroundStyle(Palette.soft)
                Text(atlas.name(b)).font(.atlasLabel).foregroundStyle(Palette.soft)
            }
            ForEach(rows, id: \.0) { r in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow(alignment: .top) {
                    Text(r.0).font(.atlasNote.weight(.bold)).foregroundStyle(Palette.soft)
                    Text(r.1.isEmpty ? "no figures" : r.1).font(.atlasNote).foregroundStyle(r.1.isEmpty ? Palette.soft : Palette.ink)
                    Text(r.2.isEmpty ? "no figures" : r.2).font(.atlasNote).foregroundStyle(r.2.isEmpty ? Palette.soft : Palette.ink)
                }
            }
        }
    }

    /// The sources behind the two places' climate, plantings and outlines, then the ones the wine text is written from.
    private func sources(_ fa: JSON, _ fb: JSON, _ p: JSON?) -> some View {
        var seen = Set<String>(), list: [(String, String?)] = []
        for f in [fa, fb] {
            for g in ["climate", "planted", "map"] {
                for i in f["src_for"][g].array.compactMap(\.int) {
                    let s = f["sources"][i]
                    if let n = s["name"].string, seen.insert(n).inserted { list.append((n, s["url"].string)) }
                }
            }
        }
        for s in p?["sources"].array ?? [] { if let n = s["name"].string, seen.insert(n).inserted { list.append((n, s["url"].string)) } }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(list, id: \.0) { n, u in
                if let u, let url = URL(string: u) { Link(n, destination: url).font(.atlasNote) } else { Text(n).font(.atlasNote).foregroundStyle(Palette.soft) }
            }
        }
    }
}

/// The 50 often compared pairs, each pair's outlines drawn to one scale unless marked (renderPairs in web/atlas.js).
struct PairsList: View {
    @Binding var route: CompareRoute
    @Environment(Atlas.self) private var atlas
    @Environment(\.horizontalSizeClass) private var width

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("The pairs people set side by side most, among benchmark regions.").font(.atlasBody).foregroundStyle(Palette.soft)
                let cols = width == .regular ? [GridItem(.flexible(), spacing: 8), GridItem(.flexible())] : [GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(Array(atlas.pairs().enumerated()), id: \.offset) { i, p in row(i, p) }
                }
                Text("Each pair is drawn to one scale, so you can see how their sizes compare, unless marked not to scale.")
                    .font(.atlasNote).foregroundStyle(Palette.soft).padding(.top, 6)
            }
            .padding(20)
        }
        .navigationTitle("Often compared")
    }

    private func row(_ i: Int, _ p: JSON) -> some View {
        let a = p["a"].string ?? "", b = p["b"].string ?? ""
        let oa = Outline(p["oa"]), ob = Outline(p["ob"])
        let box = 46.0
        let s = box / max(oa?.size ?? 1, ob?.size ?? 1)
        let loose = min(oa?.size ?? 1, ob?.size ?? 1) * s < box / 5   // too small to see at this size (looseAt 5 in web/atlas.js)
        let tag = p["tag"].string ?? ""
        return Button { route = CompareRoute(a: a, b: b) } label: {
            HStack(spacing: 10) {
                Text("\(i + 1)").font(.subheadline.weight(.heavy)).foregroundStyle(Palette.soft).frame(width: 24, alignment: .trailing)
                HStack(alignment: .bottom, spacing: 4) {
                    if let oa { OutlineView(o: oa, k: loose ? box / oa.size : s, tone: atlas.tone(a)) }
                    if let ob { OutlineView(o: ob, k: loose ? box / ob.size : s, tone: atlas.tone(b)) }
                }
                .frame(width: 100, height: 48, alignment: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(atlas.name(a)) · \(atlas.name(b))").font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                    Text(p["link"].string ?? "").font(.atlasNote).foregroundStyle(Palette.soft)
                    HStack(spacing: 4) {
                        if tag == "different-grapes" { badge("Different grapes", Palette.goldTint) }
                        if tag == "sounds-alike" { badge("More different than they sound", Palette.oceanHigh) }
                        if loose { badge("Not to scale", Palette.fill) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.landEdge))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badge(_ t: String, _ bg: Color) -> some View {
        Text(t).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.ink).padding(.horizontal, 5).background(bg, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Opens the compare sheet when Nav asks for it (a button, or a link like atlas://compare/france/burgundy/vs/italy/barolo).
struct CompareSheetHost: ViewModifier {
    @Environment(Nav.self) private var nav
    func body(content: Content) -> some View {
        @Bindable var nav = nav
        content.sheet(item: $nav.compare) { CompareSheet(route: $0).presentationSizing(.page) }   // the full page on iPad, two columns wide
    }
}

extension View {
    func compareSheet() -> some View { modifier(CompareSheetHost()) }
}
