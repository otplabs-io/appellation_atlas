import SwiftUI

/// What Compare shows: two places side by side, one or none waiting to be picked, or the often compared pairs.
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
            .frame(width: max(2, o.w * k), height: max(2, o.h * k))
            .accessibilityHidden(true)
    }
}

/// Sentences built only from the Atlas's own figures (placesText in web/atlas.js).
enum CompareText {
    static func dry(_ k: String?) -> String? {
        guard let k, k.count >= 2 else { return nil }
        if k.hasPrefix("B") { return "an arid climate" }
        return ["f": "no dry season", "s": "dry summers", "w": "dry winters", "m": "a short dry season"][String(Array(k)[1])]
    }
    static func summer(_ k: String?) -> String? {
        guard let k, k.count >= 3, !k.hasPrefix("B"), !k.hasPrefix("E") else { return nil }
        return ["a": "hot", "b": "warm", "c": "cool", "d": "cold"][String(Array(k)[2])]
    }
    static func lat(_ c: JSON) -> String {
        guard let l = c["lat"].double else { return "" }
        return "\(Int(abs(l).rounded()))°\(l < 0 ? "S" : "N")"
    }
    struct Lead { let g: String; let p: Int; let y: Int; let about: Bool; let two: String; let names: [String]; let skin: String }
    /// The leading grape and its share, when the figures are for the place itself.
    static func lead(_ f: JSON) -> Lead? {
        let pl = f["planted"]
        guard ["own", "within", "country"].contains(pl["scope"].string ?? ""), let ha = pl["ha"].double, ha > 0 else { return nil }
        let gs = pl["grapes"].array.filter { $0[0].string != "Other" }
        guard let g = gs.first, let name = g[0].string else { return nil }
        let pct: (JSON) -> Int = { Int((($0[1].double ?? 0) / ha * 100).rounded()) }
        return Lead(g: name, p: pct(g), y: pl["year"].int ?? 0, about: pl["whites_older"].bool == true,
                    two: gs.prefix(2).map { "\($0[0].string ?? "") \(pct($0))%" }.joined(separator: ", "),
                    names: gs.compactMap { $0[0].string }, skin: g[2].string ?? "")
    }
    /// The one grape a place's rules allow, if they allow only one.
    static func only(_ f: JSON) -> (name: String, skin: String)? {
        let r = f["rules"], g = r["grapes"].array
        guard g.count == 1, r["grapes_other"].array.isEmpty, let n = g[0][0].string else { return nil }
        return (n, g[0][1].string ?? "")
    }
    static func andJoin(_ t: String) -> String {
        let x = t.replacingOccurrences(of: " and ", with: ", ").components(separatedBy: ", ").filter { !$0.isEmpty }
        return x.count > 1 ? x.dropLast().joined(separator: ", ") + " and " + x.last! : (x.first ?? "")
    }

    /// The season first, then the rain, then what is planted, then how big each is.
    static func places(_ fa: JSON, _ fb: JSON, pair: JSON?, atlas: Atlas) -> String {
        let A = fa["name"].string ?? "", B = fb["name"].string ?? ""
        let ca = fa["climate"], cb = fb["climate"]
        var s: [String] = []
        let wa = fa["winkler"][0].string, wb = fb["winkler"][0].string
        var same = false
        let ga = ca["gst"].double, gb = cb["gst"].double
        if let ga, let gb {
            let ta = Units.tN(ga), tb = Units.tN(gb), d = abs(ta - tb)
            if d <= 1 {
                same = true
                let bench = [fa["id"].string ?? "", fb["id"].string ?? ""].allSatisfy { let t = atlas.tone($0); return t == .essential || t == .benchmark }
                let link = pair?["link"].string ?? "", tag = pair?["tag"].string ?? ""
                let intro = bench && !link.isEmpty && tag.isEmpty ? "Two benchmarks for \(andJoin(link)) with almost the same growing season" : "Almost the same growing season"
                let body = d == 0 ? "both average \(Units.deg(ga))" : "\(Units.deg(ga)) in \(A) and \(Units.deg(gb)) in \(B)"
                var wk = ""
                if let wa, let wb { wk = wa == wb ? " and both are Winkler region \(wa)" : ", Winkler region \(wa) against \(wb)" }
                s.append("\(intro): \(body)\(wk).")
            } else {
                let (W, gw, gc, ww, wc) = ta > tb ? (A, ga, gb, wa, wb) : (B, gb, ga, wb, wa)
                var t = "\(W)'s growing season is \(d)\(Units.tU) warmer: \(Units.deg(gw)) against \(Units.deg(gc))"
                if let ww, let wc { t += ww == wc ? ", though both are Winkler region \(ww)" : ", Winkler region \(ww) against \(wc)" }
                s.append(t + ".")
            }
        } else if let wa, let wb {
            s.append(wa == wb ? "Both are Winkler region \(wa)." : "\(A) is Winkler region \(wa); \(B) is \(wb).")
        }
        let da = dry(ca["koppen"].string), db = dry(cb["koppen"].string), ha = summer(ca["koppen"].string), hb = summer(cb["koppen"].string)
        func dryText(_ X: String, _ d: String) -> String {
            switch d {
            case "no dry season": "\(X) has no dry season"
            case "dry summers": "\(X)'s summers are dry"
            case "dry winters": "\(X)'s winters are dry"
            case "an arid climate": "\(X) is arid"
            default: "\(X) has \(d)"
            }
        }
        if let da, let db, da != db {
            s.append((same ? "The difference is rain. " : "") + "\(dryText(A, da)), while \(dryText(B, db)).")
        } else if let da, db != nil {
            let aFirst = ga == nil || gb == nil || ga! >= gb!
            let (P, Q, hp, hq) = aFirst ? (A, B, ha, hb) : (B, A, hb, ha)
            var t = da == "no dry season" ? "Neither has a dry season" : "Both have \(da)"
            if let hp, let hq, hp != hq { t += ", but \(P)'s summers are \(hp) and \(Q)'s \(hq)" }
            s.append(t + ".")
        }
        let la = lead(fa), lb = lead(fb)
        if let la, let lb {
            if la.g == lb.g { s.append("\(la.g) leads in both: \(la.p)% of the vines in \(A) and \(lb.p)% in \(B).") }
            else if la.names.dropFirst().first == lb.g { s.append("\(A) plants more \(la.g) than \(lb.g); in \(B), \(lb.g) is \(lb.p)% of the vines.") }
            else if lb.names.dropFirst().first == la.g { s.append("\(B) plants more \(lb.g) than \(la.g); in \(A), \(la.g) is \(la.p)% of the vines.") }
            else { s.append("\(la.g) leads in \(A), at \(la.p)% of the vines; in \(B) it is \(lb.g), at \(lb.p)%.") }
        } else if let la, let ob = only(fb) {
            s.append("\(B) is made only from \(ob.name); in \(A), \(la.g) leads at \(la.p)% of the vines.")
        } else if let lb, let oa = only(fa) {
            s.append("\(A) is made only from \(oa.name); in \(B), \(lb.g) leads at \(lb.p)% of the vines.")
        }
        func size(_ f: JSON) -> (t: String, n: Double)? {
            let n = f["rules"]["communes"].array.count, k = f["kind"][0].string, m = f["summary"]["places"].double
            if n > 0, let k { return ("one \(k) of \(n) commune\(n == 1 ? "" : "s")", 0) }
            if let m { return ("a whole \(f["depth"].int == 0 ? "country" : "region") of \(fmt(m)) places", m) }
            return nil
        }
        if let za = size(fa), let zb = size(fb), za.n == 0 || zb.n == 0, za.n != zb.n {
            let (x, y, X, Y) = za.n < zb.n ? (za, zb, A, B) : (zb, za, B, A)
            s.append("\(X) is \(x.t); \(Y) is \(y.t).")
        }
        if let ea = fa["terrain"]["elev"][1].double, let eb = fb["terrain"]["elev"][1].double, abs(ea - eb) >= 250 {
            s.append("The vineyards sit higher in \(ea > eb ? A : B), at about \(Units.elev(max(ea, eb))) against \(Units.elev(min(ea, eb))).")
        }
        return s.joined(separator: " ")
    }

    static let states = ["AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska",
        "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas",
        "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming"]

    /// Under a place's name: its state for an American place, else its country, then its latitude (subOf in web/atlas.js).
    static func sub(_ f: JSON, _ id: String, _ atlas: Atlas) -> String {
        let st = f["ava"]["states"].strings
        let country = atlas.places[id]?.country ?? ""
        let place = st.count == 1 ? (states[st[0]] ?? st[0]) : country == atlas.name(id) ? "" : country
        return [place, lat(f["climate"])].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// A source's short name, for the lines at the foot of Compare (shortName in web/atlas.js).
    static func short(_ n: String, wine: Bool) -> String {
        let table: [(String, String)] = [("Fick and Hijmans 2017", "WorldClim 2.1"), ("Beck et al. 2023", "Beck et al. 2023 Köppen maps"), ("Winkler, Cook", "Winkler 1974"),
                                         ("Jones 2010", "Jones 2010"), ("Anderson, Nelgen and Puga", "University of Adelaide grape-area database"), ("Candiago et al. 2022", "Candiago et al. 2022")]
        for (p, t) in table where n.hasPrefix(p) { return t }
        var m = n
        for tail in [" (what the wines taste like)", " (key facts)", " (what the label terms mean)"] where m.hasSuffix(tail) { m = String(m.dropLast(tail.count)) }
        guard let r = m.range(of: ", ") else { return m }
        return wine ? m[..<r.lowerBound] + " on " + m[r.upperBound...] : String(m[..<r.lowerBound])
    }
}

// ---- the page

/// Opens Compare and the pairs over everything when Nav asks for it (a button, or atlas://compare/france/burgundy/vs/italy/barolo).
struct CompareCoverHost: ViewModifier {
    @Environment(Nav.self) private var nav
    func body(content: Content) -> some View {
        @Bindable var nav = nav
        content.fullScreenCover(item: $nav.compare) { CompareScreen(start: $0) }
    }
}

/// Settings and About, opened from the buttons over the map.
struct SettingsCoverHost: ViewModifier {
    @Environment(Nav.self) private var nav
    @Environment(\.horizontalSizeClass) private var width
    func body(content: Content) -> some View {
        @Bindable var nav = nav
        content
            .fullScreenCover(isPresented: Binding(get: { nav.settings && width != .regular }, set: { nav.settings = $0 })) { SettingsPage() }
            .sheet(isPresented: Binding(get: { nav.settings && width == .regular }, set: { nav.settings = $0 })) { SettingsPage() }
            .sheet(isPresented: $nav.about) { AboutView() }
    }
}

extension View {
    func compareCover() -> some View { modifier(CompareCoverHost()) }
    func settingsCover() -> some View { modifier(SettingsCoverHost()) }
}

/// Compare and the pairs, with a way back through what was opened.
struct CompareScreen: View {
    @State var route: CompareRoute
    @State private var back: [CompareRoute] = []
    @Environment(\.dismiss) private var dismiss

    init(start: CompareRoute) { _route = State(initialValue: start) }

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width >= 1150
            Group {
                if route.pairs { PairsPage(wide: wide, open: open, goBack: goBack) }
                else { ComparePage(route: $route, wide: wide, width: g.size.width, open: open, goBack: goBack) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.paper.ignoresSafeArea())
    }

    private func open(_ r: CompareRoute) { back.append(route); withAnimation(.snappy) { route = r } }
    private func goBack() { if let r = back.popLast() { withAnimation(.snappy) { route = r } } else { dismiss() } }
}

struct ComparePage: View {
    @Binding var route: CompareRoute
    let wide: Bool
    var width: CGFloat = 1366
    let open: (CompareRoute) -> Void
    let goBack: () -> Void
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Units.key) private var units = ""
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        let _ = units
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let a = route.a, let b = route.b, let fa = atlas.facts(a), let fb = atlas.facts(b) {
                    compared(a, fa, b, fb)
                } else {
                    picker
                }
            }
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // ---- the bar along the top

    private var header: some View {
        Group {
            if wide {
                HStack(spacing: 12) {
                    CircleBack(action: goBack)
                    Text("Compare").font(.display(26, .heavy, relativeTo: .title)).foregroundStyle(Palette.ink).padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
                    chips
                    Spacer()
                    PillLink(title: "Other pairs") { open(CompareRoute(pairs: true)) }
                }
                .padding(.horizontal, 32).padding(.top, 20)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        CircleBack(action: goBack)
                        Spacer()
                        Text("Compare").font(.display(17, .heavy, relativeTo: .headline)).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                        Spacer()
                        PillLink(title: "Other pairs") { open(CompareRoute(pairs: true)) }
                    }
                    if route.a == nil || route.b == nil { chips.padding(.top, 6) }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 6)
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            chip(route.a, "A first place") { route.a = route.b; route.b = nil }
            Text("and").font(.text(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Palette.soft)
            chip(route.b, "A second place") { route.b = nil }
        }
    }

    @ViewBuilder private func chip(_ id: String?, _ empty: String, remove: @escaping () -> Void) -> some View {
        if let id {
            HStack(spacing: 8) {
                Rectangle().fill(Palette.tone(atlas.tone(id))).frame(width: 10, height: 10)
                Text(atlas.name(id)).font(.text(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Palette.ink).lineLimit(1)
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.soft)
                        .frame(width: 24, height: 24).background(Palette.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose another place instead of \(atlas.name(id))")
            }
            .padding(.leading, 14).padding(.trailing, 8).frame(height: 40)
            .background(Palette.card, in: Capsule())
            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
        } else {
            Text(empty).font(.text(14, .bold, relativeTo: .subheadline)).foregroundStyle(Palette.soft)
                .padding(.horizontal, 14).frame(height: 40)
                .overlay(Capsule().stroke(Palette.landEdge, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    // ---- picking a place

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSearchBox(query: $query, focused: $searching, prompt: route.a == nil ? "Search the first place" : "Search a place to compare with \(atlas.name(route.a!))")
            ForEach(atlas.search(query, limit: 12).filter { $0.id != route.a }) { p in
                Button { pick(p.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.text(15, .bold, relativeTo: .body)).foregroundStyle(Palette.ink)
                        Text([p.kind, p.country].filter { !$0.isEmpty }.joined(separator: ", ")).font(.atlasNote).foregroundStyle(Palette.soft)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
            if let a = route.a, query.isEmpty {
                let near = atlas.pairs().compactMap { p -> String? in p["a"].string == a ? p["b"].string : p["b"].string == a ? p["a"].string : nil }
                if !near.isEmpty {
                    Caps("Often compared with \(atlas.name(a))").padding(.top, 4)
                    FlowLayout(spacing: 6) {
                        ForEach(near, id: \.self) { id in
                            Button { pick(id) } label: {
                                HStack(spacing: 6) { Rectangle().fill(Palette.tone(atlas.tone(id))).frame(width: 10, height: 10); Text(atlas.name(id)) }
                                    .font(.text(13, .heavy, relativeTo: .footnote)).foregroundStyle(Palette.ink)
                                    .padding(.horizontal, 12).frame(height: 34)
                                    .background(Palette.card, in: Capsule()).overlay(Capsule().stroke(Palette.line, lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if query.isEmpty {
                Button("See all often compared pairs") { open(CompareRoute(pairs: true)) }.font(.atlasNote).foregroundStyle(Palette.teal).padding(.top, 4)
            }
        }
        .padding(.horizontal, wide ? 32 : 16).padding(.top, 14)
        .frame(maxWidth: wide ? 720 : .infinity, alignment: .leading)
        .onAppear { if route.a == nil || route.b == nil { searching = true } }
    }

    private func pick(_ id: String) {
        query = ""; searching = false
        if route.a == nil { route.a = id } else { route.b = id }
    }

    // ---- two places side by side

    @ViewBuilder private func compared(_ a: String, _ fa: JSON, _ b: String, _ fb: JSON) -> some View {
        let p = atlas.pair(a, b)
        if wide {
            // two columns, 1.1 to 1, as on the website
            let room = max(600, width - 64 - 36), lw = room * 1.1 / 2.1
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 18) {
                    shapes(a, fa, b, fb)
                    months(fa, fb)
                    rows(fa, fb)
                }
                .frame(width: lw)
                VStack(alignment: .leading, spacing: 22) {
                    note(a, b, p)
                    placesText(fa, fb, p)
                    wines(a, fa, b, fb, p)
                    sources(fa, fb, p)
                }
                .frame(width: room - lw)
            }
            .padding(.horizontal, 32).padding(.top, 22)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                shapes(a, fa, b, fb).padding(.top, -2)
                note(a, b, p)
                placesText(fa, fb, p)
                months(fa, fb)
                rows(fa, fb).padding(.top, -2)
                wines(a, fa, b, fb, p).padding(.top, 2)
                sources(fa, fb, p)
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private func shapes(_ a: String, _ fa: JSON, _ b: String, _ fb: JSON) -> some View {
        let box: Double = wide ? 293 : 154, art: CGFloat = wide ? 300 : 158
        let oa = Outline(fa["outline"]), ob = Outline(fb["outline"])
        VStack(spacing: wide ? 10 : 8) {
            if let oa, let ob {
                let s = box / max(oa.size, ob.size)
                let smallIsA = oa.size < ob.size
                let zoom = min(oa.size, ob.size) * s < box / 4
                let small = smallIsA ? oa : ob
                let z = min((wide ? 196 : 110) / small.w, (wide ? 132 : 76) / small.h) / s
                HStack(alignment: .top, spacing: wide ? 16 : 10) {
                    column(a, fa, art: art) { place(oa, s, a, zoom && smallIsA ? z : nil, art: art) }
                    column(b, fb, art: art) { place(ob, s, b, zoom && !smallIsA ? z : nil, art: art) }
                }
                scaleBar(pxkm: s, box: box)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    column(a, fa, art: 40) { Text("No outline").font(.atlasNote).foregroundStyle(Palette.soft) }
                    column(b, fb, art: 40) { Text("No outline").font(.atlasNote).foregroundStyle(Palette.soft) }
                }
            }
        }
        .padding(.horizontal, wide ? 18 : 14).padding(.top, wide ? 18 : 14).padding(.bottom, wide ? 12 : 10)
        .frame(maxWidth: .infinity)
        .cardBox(24)
    }

    /// A place's shape at the shared scale; one too small to read there also gets an enlarged copy above it.
    private func place(_ o: Outline, _ s: Double, _ id: String, _ z: Double?, art: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            OutlineView(o: o, k: s, tone: atlas.tone(id))
            if let z {
                VStack(spacing: 4) {
                    OutlineView(o: o, k: s * z, tone: atlas.tone(id))
                        .frame(width: wide ? 220 : 128, height: wide ? 150 : 90)
                        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.landEdge, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    Text("enlarged \(fmt(z.rounded())) times").font(.text(wide ? 11 : 10, relativeTo: .caption2)).foregroundStyle(Palette.soft)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, wide ? 10 : 6)
            }
        }
        .frame(height: art)
    }

    private func column<Art: View>(_ id: String, _ f: JSON, art: CGFloat, @ViewBuilder _ draw: () -> Art) -> some View {
        VStack(spacing: wide ? 10 : 8) {
            draw().frame(height: art, alignment: .bottom)
            VStack(spacing: wide ? 2 : 0) {
                HStack(spacing: wide ? 6 : 5) {
                    Rectangle().fill(Palette.tone(atlas.tone(id))).frame(width: wide ? 10 : 9, height: wide ? 10 : 9)
                    Text(atlas.name(id)).font(.display(wide ? 18 : 15, .heavy, relativeTo: .headline)).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                }
                Text(CompareText.sub(f, id, atlas)).font(.text(wide ? 12.5 : 11.5, relativeTo: .caption)).foregroundStyle(Palette.soft)
                if f["outline"]["far"].string != nil { Text("Far-off islands and territories not drawn").font(.text(11, relativeTo: .caption2)).foregroundStyle(Palette.soft).multilineTextAlignment(.center) }   // src/outlines.py
            }
        }
        .frame(maxWidth: .infinity)
        .onTapGesture { nav.compare = nil; nav.go(id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens \(atlas.name(id)) on the map")
    }

    /// A scale bar about a third of the box wide, in round miles or kilometers (scaleBar in web/atlas.js).
    private func scaleBar(pxkm: Double, box: Double) -> some View {
        let u = Units.us(.dist) ? 1.609344 : 1, want = box / 3 / pxkm / u, p = pow(10, floor(log10(want)))
        let n = [1, 2, 5, 10].map { $0 * p }.filter { $0 <= want }.last ?? p
        return HStack(spacing: 8) {
            Rectangle().fill(.clear).frame(width: n * u * pxkm, height: wide ? 5 : 4)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.soft).frame(height: 1) }
                .overlay(alignment: .leading) { Rectangle().fill(Palette.soft).frame(width: 1) }
                .overlay(alignment: .trailing) { Rectangle().fill(Palette.soft).frame(width: 1) }
            Text("\(fmt(n)) \(Units.us(.dist) ? (n == 1 ? "mile" : "miles") : "km") · both drawn to the same scale")
                .font(.text(wide ? 12 : 11, relativeTo: .caption2)).foregroundStyle(Palette.soft)
        }
    }

    @ViewBuilder private func note(_ a: String, _ b: String, _ p: JSON?) -> some View {
        if p?["tag"].string == "different-grapes" {
            let t = Units.text(p?["note"].string ?? "") .isEmpty ? "\(atlas.name(a)) and \(atlas.name(b)) are made from different grapes, so this page compares the typical wine of each." : Units.text(p?["note"].string ?? "")
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 18)).foregroundStyle(Palette.ink).frame(width: 22)
                (Text("Different grapes. ").font(.text(14, .heavy, relativeTo: .subheadline)) + Text(t).font(.text(14, relativeTo: .subheadline)))
                    .foregroundStyle(Palette.ink).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.goldTint, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func placesText(_ fa: JSON, _ fb: JSON, _ p: JSON?) -> some View {
        let t = CompareText.places(fa, fb, pair: p, atlas: atlas)
        if !t.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Caps("How the places compare", color: Palette.coralText)
                Text(t).font(.text(wide ? 15 : 14.5, relativeTo: .body)).lineSpacing(wide ? 6 : 3).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func months(_ fa: JSON, _ fb: JSON) -> some View {
        let cs = [fa, fb].filter { !$0["climate"]["tavg"].array.isEmpty }
        if !cs.isEmpty {
            VStack(alignment: .leading, spacing: wide ? 6 : 4) {
                Caps("Average by month, \(Units.tU)")
                HStack(alignment: .top, spacing: wide ? 22 : 14) {
                    ForEach(Array(cs.enumerated()), id: \.offset) { _, f in MonthBars(f: f, h: wide ? 96 : 57, wide: wide) }
                }
            }
        }
    }

    private func rows(_ fa: JSON, _ fb: JSON) -> some View {
        let ca = fa["climate"], cb = fb["climate"]
        let la = CompareText.lead(fa), lb = CompareText.lead(fb), both = la != nil && lb != nil
        func grapes(_ f: JSON, _ l: CompareText.Lead?) -> String {
            if let l { return "\(l.two)\(both ? "" : " planted") (\(l.y)\(l.about ? ", approximate" : ""))" }
            if let o = CompareText.only(f) { return "\(o.name), the only grape its rules allow" }
            return ""
        }
        let ga = grapes(fa, la), gb = grapes(fb, lb)
        let list: [(String, String, String)] = [
            ("Heat", ca["gdd"].double.map { Units.heat($0) } ?? "", cb["gdd"].double.map { Units.heat($0) } ?? ""),
            (both || (ga.isEmpty && gb.isEmpty) ? "Planted" : "Grapes", ga, gb),
        ].filter { !$0.1.isEmpty || !$0.2.isEmpty }
        return VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, r in
                HStack(alignment: .top, spacing: wide ? 12 : 8) {
                    Text(r.0).font(.text(wide ? 14 : 13.5, .heavy, relativeTo: .subheadline)).foregroundStyle(Palette.soft).frame(width: wide ? 92 : 70, alignment: .leading)
                    Text(r.1.isEmpty ? "No figures" : r.1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.2.isEmpty ? "No figures" : r.2).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.text(wide ? 14 : 13.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, wide ? 11 : 9)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private func wines(_ a: String, _ fa: JSON, _ b: String, _ fb: JSON, _ p: JSON?) -> some View {
        let w = p?["wines"].array ?? []
        let own = [(a, fa), (b, fb)].filter { !$0.1["style"]["notes"].array.isEmpty }
        if !w.isEmpty || !own.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Caps(w.isEmpty ? "The wines" : "How the wines compare", color: Palette.coralText)
                if !w.isEmpty {
                    ForEach(Array(w.enumerated()), id: \.offset) { _, x in
                        wine(x["head"].string ?? "", x["c"].string ?? "w", Units.text(x["text"].string ?? "").components(separatedBy: "\n\n"))
                    }
                } else {
                    ForEach(own, id: \.0) { id, f in
                        let l = CompareText.lead(f), o = CompareText.only(f)
                        let c = l.map { $0.skin == "R" ? "r" : $0.skin == "W" ? "w" : "p" } ?? o.map { $0.skin == "red" ? "r" : $0.skin == "white" ? "w" : "p" } ?? "w"
                        wine(atlas.name(id), c, Array(f["style"]["notes"].strings.prefix(2)))
                    }
                }
            }
            .padding(wide ? 20 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBox(22)
        }
    }

    private func wine(_ head: String, _ c: String, _ paras: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(c == "r" ? Palette.coral : c == "p" ? Palette.pink : c == "n" ? Palette.soft : Palette.gold).frame(width: 9, height: 9)
                Text(head).font(.display(15, .bold, relativeTo: .headline)).foregroundStyle(Palette.ink)
            }
            ForEach(Array(paras.enumerated()), id: \.offset) { _, t in
                Text(t).font(.text(wide ? 14.5 : 14, relativeTo: .subheadline)).lineSpacing(wide ? 5 : 3).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Where each part comes from, one line per kind, the source names linked (cmpSources in web/atlas.js).
    private func sources(_ fa: JSON, _ fb: JSON, _ p: JSON?) -> some View {
        func of(_ f: JSON, _ k: String) -> [JSON] { f["src_for"][k].array.compactMap(\.int).map { f["sources"][$0] } }
        let style: (JSON) -> [JSON] = { f in f["sources"].array.filter { ($0["name"].string ?? "").hasSuffix("(what the wines taste like)") } }
        let usesRules = [fa, fb].filter { CompareText.lead($0) == nil && CompareText.only($0) != nil }
        let w = (p?["wines"].array.isEmpty == false) ? (p?["sources"].array ?? []) : style(fa) + style(fb)
        let lines: [(String, [JSON], Bool)] = [
            ("Climate", of(fa, "climate") + of(fb, "climate"), false),
            ("Rules", usesRules.flatMap { of($0, "map") }, false),
            ("Plantings", of(fa, "planted") + of(fb, "planted"), false),
            ("Wines", w, true),
        ]
        return VStack(alignment: .leading, spacing: 3) {
            Text("SOURCES").font(.text(wide ? 12 : 11.5, .heavy, relativeTo: .caption2)).kerning(0.5)
            ForEach(lines.filter { !$0.1.isEmpty }, id: \.0) { head, list, wine in
                var seen = Set<String>()
                let items = list.filter { seen.insert(CompareText.short($0["name"].string ?? "", wine: wine)).inserted }
                Text(sourceLine(head, items, wine))
            }
        }
        .font(.text(wide ? 12 : 11.5, relativeTo: .caption2))
        .foregroundStyle(Palette.soft)
        .tint(Palette.soft)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func sourceLine(_ head: String, _ items: [JSON], _ wine: Bool) -> AttributedString {
        var s = AttributedString(head + ": ")
        for (i, x) in items.enumerated() {
            var t = AttributedString(CompareText.short(x["name"].string ?? "", wine: wine))
            if let u = x["url"].string, let url = URL(string: u) { t.link = url; t.underlineStyle = .single }
            s += t
            s += AttributedString(i == items.count - 1 ? "." : wine ? "; " : ", ")
        }
        return s
    }
}

/// Twelve months as bars, 30°F to 74°F on one scale for every place, the growing season in coral, each value on top
/// (monChart in web/atlas.js).
struct MonthBars: View {
    let f: JSON
    let h: CGFloat
    let wide: Bool
    var body: some View {
        let c = f["climate"], south = (c["lat"].double ?? 0) < 0
        let gs: Set<Int> = south ? [9, 10, 11, 0, 1, 2, 3] : [3, 4, 5, 6, 7, 8, 9]
        let t = c["tavg"].doubles
        let name = (f["name"].string ?? "").replacingOccurrences(of: #" (Valley|County|AVA|DOC|DOCG|DOCa|DO)$"#, with: "", options: .regularExpression)
        VStack(alignment: .leading, spacing: wide ? 3 : 2) {
            HStack(alignment: .bottom, spacing: wide ? 2 : 1) {
                ForEach(Array(t.enumerated()), id: \.offset) { i, v in
                    VStack(spacing: 0) {
                        Text("\(Units.tN(v))").font(.text(wide ? 10 : 8, .bold, relativeTo: .caption2)).foregroundStyle(Palette.ink).lineLimit(1).fixedSize()
                        Rectangle().fill(gs.contains(i) ? Palette.coral : Palette.monthTemp)
                            .frame(height: max(2, (toF(v) - 30) * h / 44))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: wide ? 2 : 1) {
                ForEach(Array("JFMAMJJASOND".enumerated()), id: \.offset) { _, m in
                    Text(String(m)).font(.text(wide ? 10 : 8, relativeTo: .caption2)).foregroundStyle(Palette.soft).frame(maxWidth: .infinity)
                }
            }
            Text("\(name) · \(Units.deg(c["gst"].double ?? 0)) season").font(.text(wide ? 13 : 12, .heavy, relativeTo: .caption)).foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("\(f["name"].string ?? "") by month: \(t.map { "\(Units.tN($0))" }.joined(separator: ", ")) \(Units.tU)")
    }
}

/// The often compared pairs, each pair's outlines drawn to one scale unless marked (renderPairs in web/atlas.js).
struct PairsPage: View {
    let wide: Bool
    let open: (CompareRoute) -> Void
    let goBack: () -> Void
    @Environment(Atlas.self) private var atlas

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CircleBack(action: goBack)
                    Spacer()
                    PillLink(title: "Compare any two", teal: true) { open(CompareRoute()) }
                }
                .padding(.horizontal, wide ? 32 : 16).padding(.top, wide ? 20 : 6).padding(.bottom, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Often compared").font(.display(30, .heavy, relativeTo: .largeTitle)).kerning(-0.6).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                    Text("The pairs people set side by side most, among benchmark regions.").font(.text(14, relativeTo: .subheadline)).foregroundStyle(Palette.soft)
                }
                .padding(.horizontal, wide ? 36 : 20).padding(.top, 6).padding(.bottom, 12)
                let cols = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: wide ? 3 : 1)
                LazyVGrid(columns: cols, spacing: wide ? 8 : 6) {
                    ForEach(Array(atlas.pairs().enumerated()), id: \.offset) { i, p in row(i, p) }
                }
                .padding(.horizontal, wide ? 32 : 16)
                Text("Each pair is drawn to one scale, so you can see how their sizes compare, unless marked not to scale.")
                    .font(.text(11.5, relativeTo: .caption2)).foregroundStyle(Palette.soft)
                    .padding(.horizontal, wide ? 36 : 20).padding(.top, 12)
            }
            .padding(.bottom, 40)
        }
    }

    private func row(_ i: Int, _ p: JSON) -> some View {
        let a = p["a"].string ?? "", b = p["b"].string ?? ""
        let oa = Outline(p["oa"]), ob = Outline(p["ob"])
        let box = 46.0
        let s = box / max(oa?.size ?? 1, ob?.size ?? 1)
        let loose = min(oa?.size ?? 1, ob?.size ?? 1) * s < box / 5   // too small to see at this size (looseAt 5 in web/atlas.js)
        let tag = p["tag"].string ?? ""
        return Button { open(CompareRoute(a: a, b: b)) } label: {
            HStack(spacing: 10) {
                Text("\(i + 1)").font(.display(13, .heavy, relativeTo: .footnote)).foregroundStyle(Palette.soft).frame(width: 22, alignment: .trailing)
                HStack(alignment: .bottom, spacing: 4) {
                    if let oa { OutlineView(o: oa, k: loose ? box / oa.size : s, tone: atlas.tone(a)) }
                    if let ob { OutlineView(o: ob, k: loose ? box / ob.size : s, tone: atlas.tone(b)) }
                }
                .frame(width: 92, height: 48, alignment: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(atlas.name(a)) · \(atlas.name(b))").font(.text(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    Text(p["link"].string ?? "").font(.text(12, relativeTo: .caption)).foregroundStyle(Palette.soft)
                    if tag != "" || loose {
                        HStack(spacing: 4) {
                            if tag == "different-grapes" { badge("Different grapes", Palette.goldTint, Palette.ink) }
                            if tag == "sounds-alike" { badge("More different than they sound", Palette.oceanHigh, Palette.ink) }
                            if loose { badge("Not to scale", Palette.fill, Palette.soft) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8).padding(.leading, 8).padding(.trailing, 12)
            .frame(maxHeight: .infinity)
            .cardBox(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badge(_ t: String, _ bg: Color, _ fg: Color) -> some View {
        Text(t).font(.text(10.5, .heavy, relativeTo: .caption2)).foregroundStyle(fg).padding(.horizontal, 5).background(bg, in: RoundedRectangle(cornerRadius: 4))
    }
}
