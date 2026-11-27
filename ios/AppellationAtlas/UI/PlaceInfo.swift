import SwiftUI

/// A place's page, as design D lays it out: what it is and what it is known for, its figures as cards, the places inside
/// it and Compare, then a bar of chips over its sections. A phone shows it in the sheet over the map, an iPad in the
/// panel beside it (renderTitle, glanceStrip and renderInfo in web/atlas.js).
struct PlaceInfo: View {
    let compact: Bool
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @Environment(Globe.self) private var globe

    var body: some View {
        let id = nav.place
        if id != "world", let f = atlas.facts(id) {
            PlaceSections(id: id, f: f, range: globe.range, compact: compact).id(id)
        } else if id != "world" {
            ProgressView().frame(maxWidth: .infinity).padding(40)
        }
    }
}

extension EnvironmentValues {
    /// Whether a section draws the hairline above it (not the first, which sits under the chip bar).
    @Entry var sectionRule = true
}

struct PlaceSections: View {
    let id: String
    let f: JSON
    let range: (Double, Double)
    let compact: Bool
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @State private var allParts = false
    @State private var active: Key?
    @State private var tops: [Key: CGFloat] = [:]
    @AppStorage(Units.key) private var units = ""   // so the figures redraw when the units change

    enum Key: String, CaseIterable {
        case keyfacts, style, terms, short, planted, allowed, climate, soil, land, places, parts, rules, ava, gi, found, none, sources
        var jump: String? {
            switch self {
            case .keyfacts: "Key facts"
            case .style: "Style"
            case .terms: "Label"
            case .planted: "Planted"
            case .allowed: "Grapes"
            case .climate: "Climate"
            case .soil: "Rock and soil"
            case .land: "Land"
            case .places: "Places"
            case .parts: "Differences"
            case .rules: "Vineyard"
            case .ava: "AVA"
            case .gi: "GI"
            case .found: "Notes"
            default: nil
            }
        }
    }

    private var hasPlaces: Bool { !atlas.placesIn(atlas.viewFor(id)).isEmpty }

    private var present: [Key] {
        var k: [Key] = []
        if !f["keyfacts"].array.isEmpty { k.append(.keyfacts) }
        if !f["style"]["notes"].array.isEmpty { k.append(.style) }
        if !f["terms"].array.isEmpty { k.append(.terms) }
        if f["research"]["sheet"].truthy { k.append(.short) }
        if !f["planted"]["grapes"].array.isEmpty { k.append(.planted) }
        if !f["summary"]["grapes"].array.isEmpty && !f["planted"].truthy { k.append(.allowed) }
        if f["climate"].truthy { k.append(.climate) }
        if f["soil"].truthy || f["rocks"].truthy { k.append(.soil) }
        if f["terrain"].truthy { k.append(.land) }
        if hasPlaces { k.append(.places) }
        if !f["parts"].array.isEmpty { k.append(.parts) }
        if f["rules"].truthy { k.append(.rules) }
        if f["ava"].truthy { k.append(.ava) }
        if f["gi"].truthy { k.append(.gi) }
        if !f["research"]["claims"].array.isEmpty { k.append(.found) }
        if !(f["summary"].truthy || f["rules"].truthy || f["ava"].truthy || f["climate"].truthy || f["research"].truthy || f["planted"].truthy || f["rocks"].truthy) { k.append(.none) }
        k.append(.sources)
        return k
    }

    var body: some View {
        let _ = units
        let keys = present
        let jumps = keys.filter { $0.jump != nil }
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                lead { k in withAnimation { proxy.scrollTo(k, anchor: .top) } }
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(keys.enumerated()), id: \.element) { i, k in
                            section(k)
                                .padding(.horizontal, 20)
                                .environment(\.sectionRule, i > 0)
                                .id(k)
                                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { tops[k] = $0 }
                        }
                        FeedbackLink(name: f["name"].string ?? "", id: id).padding(.horizontal, 20).padding(.top, 8)
                    } header: {
                        if jumps.count >= 2 { chipBar(jumps, proxy) }
                    }
                }
            }
            .onChange(of: tops) { _, t in
                let on = keys.filter { $0.jump != nil && (t[$0] ?? .infinity) <= 90 }.last ?? jumps.first
                if on != active { active = on }
            }
            // For screenshots: run with -section climate to open the page at that section.
            .task {
                guard let s = UserDefaults.standard.string(forKey: "section"), let k = Key(rawValue: s), keys.contains(k) else { return }
                try? await Task.sleep(for: .seconds(1))
                proxy.scrollTo(k, anchor: .top)
            }
        }
    }

    // ---- the top of the page

    private var kindText: String {
        let kinds = f["kind"].strings
        if !kinds.isEmpty { return kinds.map(capitalized).joined(separator: " and ") }
        if f["depth"].int == 0 { return "Country" }
        return f["shape"].string == "Eurostat LAU, the commune it is named for" ? "Commune" : "Region"
    }

    private func lead(_ jump: @escaping (Key) -> Void) -> some View {
        let t = atlas.tone(id)
        let sm = f["summary"]
        let vid = atlas.viewFor(id), leafPage = id != vid
        return VStack(alignment: .leading, spacing: 14) {
            if !compact { Crumbs() }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(kindText.uppercased() + (t != .other ? " ·" : "")).font(.text(12.5, .heavy, relativeTo: .caption)).kerning(1.4).foregroundStyle(Palette.coralText)
                    if t != .other {   // grey places carry no badge, as in renderTitle in atlas.js
                        Text(Copy.tone(t).one.uppercased())
                            .font(.text(12.5, .heavy, relativeTo: .caption)).kerning(1.4)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(t == .essential ? Palette.gold4[3] : t == .benchmark ? Palette.gold4[2] : Palette.gold4[1], in: RoundedRectangle(cornerRadius: 2))
                            .foregroundStyle(Palette.ink)
                    }
                }
                HStack(alignment: .center, spacing: 12) {
                    Text(atlas.name(id)).font(.display(40, .heavy, relativeTo: .largeTitle)).kerning(-1).foregroundStyle(Palette.ink)
                        .lineLimit(3).minimumScaleFactor(0.5)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    StarButton(placeID: id)
                }
                if let also = f["also"].strings.nilIfEmpty {
                    Text("Also " + also.joined(separator: ", ")).font(.atlasNote).foregroundStyle(Palette.soft)
                }
                if let b = f["blurb"]["text"].string, !b.isEmpty {   // what the place is known for (blurb in web/atlas.js)
                    Text(b).font(.text(15, relativeTo: .body)).lineSpacing(3).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
                SavedNote(placeID: id)
            }
            .textSelection(.enabled)
            if GlanceStrip.has(f) {
                HStack(alignment: .firstTextBaseline) {
                    Text("At a glance").font(.display(15, .bold, relativeTo: .headline)).foregroundStyle(Palette.ink)
                    Spacer()
                    if compact && GlanceStrip.count(f) > 1 { Text("Swipe for more").font(.text(12, relativeTo: .caption)).foregroundStyle(Palette.soft) }
                }
                GlanceStrip(f: f, row: compact)
            }
            HStack(spacing: 8) {
                if hasPlaces {
                    let n = sm["places"].double
                    Button { jump(.places) } label: {
                        Text(!leafPage && n != nil ? "\(fmt(n)) places inside" : leafPage ? "More in \(atlas.name(vid))" : "\(atlas.placesIn(vid).count) places inside")
                            .font(.text(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).frame(height: compact ? 48 : 46)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.landEdge, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { nav.compare = CompareRoute(a: id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 14, weight: .bold))
                        Text("Compare").font(.text(14, .heavy, relativeTo: .subheadline))
                    }
                    .foregroundStyle(Palette.paper)
                    .frame(maxWidth: .infinity).frame(height: compact ? 48 : 46)
                    .background(Palette.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, compact ? 22 : 20)
        .padding(.bottom, 16)
    }

    private func chipBar(_ jumps: [Key], _ proxy: ScrollViewProxy) -> some View {
        ScrollViewReader { bar in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(jumps, id: \.self) { k in
                        let on = (active ?? jumps.first) == k
                        Button { active = k; withAnimation { proxy.scrollTo(k, anchor: .top) } } label: {
                            Text(k.jump!).font(.text(13, .heavy, relativeTo: .footnote))
                                .foregroundStyle(on ? Palette.paper : Palette.teal)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(on ? Palette.ink : Palette.fill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(k)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .onChange(of: active) { _, k in if let k { withAnimation { bar.scrollTo(k, anchor: .center) } } }
        }
        .background(Palette.paper.opacity(0.98))
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    @ViewBuilder private func section(_ k: Key) -> some View {
        switch k {
        case .keyfacts: keyfacts
        case .style: style
        case .terms: terms
        case .allowed: allowed
        case .places: AtlasSection(title: id != atlas.viewFor(id) ? "Other places in \(atlas.name(atlas.viewFor(id)))" : "Places in \(atlas.name(id))") { placesBody }
        case .short: short
        case .planted: planted
        case .climate: climate
        case .soil: soil
        case .land: land
        case .parts: parts
        case .rules: rules
        case .ava: ava
        case .gi: gi
        case .found: found
        case .none: AtlasSection(title: "What we have") { Text("No shape, rules or research for this place yet.").font(.atlasBody) }
        case .sources: sources
        }
    }

    private var bigNote: some View {
        Group {
            if f["large"].truthy {
                Text(Copy.bigNote(hasParts: f["parts"].truthy)).font(.atlasNote).italic().foregroundStyle(Palette.soft)
            }
        }
    }

    private func pairs(_ j: JSON) -> [(String, String)] { j.array.map { ($0[0].string ?? "", $0[1].string ?? "") } }

    private func chips(_ j: JSON) -> [(name: String, skin: String, count: Int?)] {
        j.array.map { x in
            if let s = x.string { return (s, "", nil) }
            return (x[0].string ?? "", x[1].string ?? "", x[2].int)
        }
    }

    // ---- sections

    /// What the words on its labels mean: the terms its region uses, for the benchmark places (terms in web/atlas.js).
    private var terms: some View {
        AtlasSection(title: "On the label") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(f["terms"].array.enumerated()), id: \.offset) { _, t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t[0].string ?? "").font(.atlasBody.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text(t[1].string ?? "").font(.atlasBody).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// What the wines taste like, for the study-list places (style in web/atlas.js); a place with none of its own shows its region's.
    private var style: some View {
        AtlasSection(title: "Wine style") {
            if let of = f["style"]["of"].string { SubCaption("Written for \(of) as a whole.") }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(f["style"]["notes"].strings, id: \.self) { t in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Palette.ink).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        Text(t).font(.text(14.5, relativeTo: .subheadline)).lineSpacing(2.5).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The few things a serious student must know, from the place's full Wikipedia article (keyfacts in web/atlas.js).
    private var keyfacts: some View {
        AtlasSection(title: "Key facts") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(f["keyfacts"].strings, id: \.self) { t in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Palette.ink).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        Text(t).font(.text(14.5, relativeTo: .subheadline)).lineSpacing(2.5).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The grapes most often allowed across its appellations, for a region with no plantings of its own.
    private var allowed: some View {
        let sm = f["summary"], n = sm["with_rules"].int ?? 0
        return AtlasSection(title: "Grapes most often allowed") {
            Text("In how many of its \(n) appellation\(n == 1 ? "" : "s") with rules:").font(.atlasNote).foregroundStyle(Palette.soft)
            Chips(items: chips(sm["grapes"]))
        }
    }

    /// The places inside it, or around it for a place with none of its own (renderPlaces in web/atlas.js).
    @ViewBuilder private var placesBody: some View {
        let sm = f["summary"]
        if sm.truthy && id == atlas.viewFor(id) {
            let kinds = sm["kinds"].array.map { plural($0[1].int ?? 0, $0[0].string ?? "") }.joined(separator: ", ")
            Text("\(fmt(sm["places"].double)) places in all\(kinds.isEmpty ? "" : ": " + kinds).").font(.text(13, relativeTo: .footnote)).foregroundStyle(Palette.soft)
        }
        PlacesHere(folded: false, titled: false)
    }

    private var short: some View {
        AtlasSection(title: "In short", note: "From our research") {
            ForEach(Array(f["research"]["sheet"].pairs.enumerated()), id: \.offset) { _, p in
                if let t = p.1.string, !t.isEmpty { Text(t).font(.atlasBody).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    private var planted: some View {
        let pl = f["planted"]
        let ha = pl["ha"].double ?? 1
        let names = pl["names"].strings
        let scope = pl["scope"].string ?? ""
        // around or parent: no figures for the place itself, only for the district around it
        let wide = scope == "around" || scope == "parent"
        let name = f["name"].string ?? ""
        let where_: String = {
            switch scope {
            case "country": return ""
            case "own": return "in " + names.joined(separator: " and ")
            case "within": return "across " + names.prefix(4).joined(separator: ", ") + (names.count > 4 ? " and \(names.count - 4) more" : "")
            default: return names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " and \(names.count - 3) more" : "")
            }
        }()
        let grapes = pl["grapes"].array
        let top = max(grapes.first?[1].double ?? 1, 1)
        let legal = pl["legal"].strings
        let other = grapes.first { $0[0].string == "Other" }
        let rows = grapes.enumerated().filter { _, g in g[0].string != "Other" && (g[1].double ?? 0) / ha >= 0.01 }   // a row under 1% would read "0%"
        let amountText = Units.area(ha)
        let year = pl["year"].int.map(String.init) ?? ""
        let older = pl["whites_older"].bool == true   // France's regional whites come from an earlier survey than its reds
        let amount = older ? Copy.whitesOlder(year) : "\(amountText) of wine grapes, \(year)."
        let caption = wide
            ? "No figures exist for \(name) alone. These are for \(where_), the wider area it sits in: \(amount)"
            : (older ? "Wine grapes\(where_.isEmpty ? "" : " " + where_): " + amount : "\(amountText) of wine grapes\(where_.isEmpty ? "" : " " + where_), \(year).") + (pl["any_name"].bool == true ? Copy.Rules.anyName : "")
        let key = wide ? ["Allowed in \(name)", "Not allowed in \(name)"] : ["Can carry the \(name) name", "Grown here, but sold under another name"]
        return AtlasSection(title: wide ? "Planted in the wider area" : "What is planted", note: "Share of vineyard area") {
            Text(caption + Copy.leftOut(pl["left"])).font(.atlasNote).foregroundStyle(Palette.soft)
            if !legal.isEmpty {
                FlowLayout(spacing: 14) {
                    HStack(spacing: 5) { Rectangle().fill(Palette.gold4[3]).frame(width: 14, height: 8); Text(key[0]) }
                    HStack(spacing: 5) { Rectangle().fill(Palette.grey4[3]).frame(width: 14, height: 8); Text(key[1]) }
                }
                .font(.atlasNote).foregroundStyle(Palette.soft)
            }
            VStack(spacing: 10) {
                ForEach(rows, id: \.offset) { i, g in
                    let status = legal.indices.contains(i) ? legal[i] : ""
                    let share = (g[1].double ?? 0) / ha * 100
                    HStack(spacing: 8) {
                        Circle().fill(g[2].string == "W" ? Palette.gold : g[2].string == "R" ? Palette.coral : Palette.landEdge).frame(width: 9, height: 9)
                        Text(g[0].string ?? "").font(.atlasBody).foregroundStyle(status == "no" ? Palette.soft : Palette.ink)
                            .frame(minWidth: 90, maxWidth: 160, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Palette.fill)
                                Rectangle().fill(status == "no" ? Palette.grey4[3] : status == "minor" ? Palette.gold4[2] : Palette.gold4[3])
                                    .frame(width: geo.size.width * min(1, max(0.01, (g[1].double ?? 0) / top)))
                            }
                        }
                        .frame(height: 10)
                        Text(share.rounded() >= 1 ? "\(Int(share.rounded()))%" : "<1%").font(.atlasNote).foregroundStyle(Palette.soft).frame(width: 36, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(status == "no" ? (wide ? "not allowed here" : "sold under another name") : status == "minor" ? "minor role" : "")
                    if status == "minor" {
                        Text("minor role").font(.atlasNote).foregroundStyle(Palette.soft).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            if let o = other { Text("Other grapes: \(Int(((o[1].double ?? 0) / ha * 100).rounded()))%").font(.atlasNote).foregroundStyle(Palette.soft) }
        }
    }

    private var climate: some View {
        let c = f["climate"]
        let south = (c["lat"].double ?? 0) < 0
        let (gi, gp) = Copy.segment(Copy.growingSeason, c["gst"].double ?? 0)
        let (wi, wp) = Copy.segment(Copy.winkler, c["gdd"].double ?? 0)
        let wk = f["winkler"]
        let reading = f["reading"]["climate"]
        return AtlasSection(title: "Climate", note: "Averages, 1970 to 2000") {
            FactGrid(facts: [
                Fact(label: "Growing season", value: Units.deg(c["gst"].double ?? 0), note: south ? "average, October to April" : "average, April to October"),
                Fact(label: "Heat", value: Units.heat(c["gdd"].double ?? 0), note: Units.heatNote),
                Fact(label: "Climate type", value: c["koppen_name"].string ?? c["koppen"].string ?? "", note: c["koppen"].string.map { "Köppen " + $0 + ", from a 1991 to 2020 map" } ?? ""),
            ])
            SubCaption("Growing season: \(gi >= 0 ? Copy.growingSeason[gi].0.lowercased() : "?")")
            ScaleBar(segments: Copy.growingSeason.map { ($0.0, Units.us(.temp) ? $0.3 : $0.4) }, index: gi, position: gp, label: "Growing season temperature class")
            SubCaption("Winkler region \(wk[0].string ?? "")")
            ScaleBar(segments: Copy.winkler.map { ($0.0, Units.us(.heat) ? $0.3 : $0.4) }, index: wi, position: wp, label: "Winkler region")
            if let t = wk[1].string, !t.isEmpty { Text(t).font(.atlasBody) }
            bigNote
            Reading(title: "What the climate means for the vines", points: pairs(reading))
            tempChart(c, south)
        }
    }

    private func tempChart(_ c: JSON, _ south: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SubCaption("Average temperature by month, \(Units.tU)")
            MonthsChart(values: c["tavg"].doubles.map(toF), shown: c["tavg"].doubles.map { Double(Units.tN($0)) }, unit: Units.tU, season: Palette.coral, base: Palette.monthTemp, south: south, labels: true)
        }
        .frame(maxWidth: 340, alignment: .leading)   // as .months in web/atlas.css
    }

    private var soil: some View {
        let so = f["soil"], rk = f["rocks"], rd = f["reading"]["soil"]
        let fams = rk["families"].array
        return AtlasSection(title: "Rock and soil") {
            if !fams.isEmpty {
                SubCaption("The rock beneath, from a geologic map: the main rock units, not each vineyard's soil")
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(fams.enumerated()), id: \.offset) { _, x in
                            let id = x[0].string ?? "", v = x[1].double ?? 0
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rk["names"][id].string ?? id).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                                Text(Copy.share(v)).font(.system(size: 10)).foregroundStyle(Palette.soft)   // words, not percentages: a few sample points
                            }
                            .padding(.horizontal, 6).padding(.vertical, 6)
                            .frame(width: max(30, g.size.width * v - 2), alignment: .leading)
                            .frame(maxHeight: .infinity)
                            .background(Palette.rock(id))
                        }
                    }
                }
                .frame(height: 44)
                if let t = rd["rock"].string { Text(t).font(.atlasBody).fixedSize(horizontal: false, vertical: true) }
            }
            if so.truthy {
                SubCaption("The soil, \(Units.soilDepth) down")
                FactGrid(facts: [
                    Fact(label: "Texture", value: so["texture"].string ?? ""),
                    Fact(label: "Clay, silt, sand", value: "\(so["clay"].int ?? 0), \(so["silt"].int ?? 0), \(so["sand"].int ?? 0)%"),
                    Fact(label: "pH", value: so["ph"].double.map { String(format: $0.rounded() == $0 ? "%.0f" : "%.1f", $0) } ?? "", note: so["ph_class"].string ?? ""),
                    Fact(label: "Stones", value: so["stones"].int.map { "\($0)%" } ?? "", note: "of the soil by volume"),
                ])
                if let t = rd["top"].string { Text(t).font(.atlasBody).fixedSize(horizontal: false, vertical: true) }
            }
            bigNote
        }
    }

    private var land: some View {
        let te = f["terrain"]
        let aspect = te["aspect"]
        let asp: [String: Double] = Dictionary(uniqueKeysWithValues: aspect.pairs.compactMap { k, v in v.double.map { (k, $0) } })
        let top = asp.max { $0.value < $1.value }
        let slope = te["slope"].double ?? 0
        let slopeText = slope.rounded() == slope ? String(format: "%.0f", slope) : String(format: "%.1f", slope)
        var facts = [Fact(label: "Elevation", value: Units.elev(te["elev"][1].double ?? 0), note: "most of it \(Units.elevRange(te["elev"][0].double ?? 0, te["elev"][2].double ?? 0))")]
        if aspect.truthy {
            facts.append(Fact(label: "Grade", value: "\(Int((tan(slope * Double.pi / 180) * 100).rounded()))%", note: "\(slopeText)° on average"))
        } else {
            facts.append(Fact(label: "Slope", value: "\(slopeText)°", note: "\(Int(((te["steep"].double ?? 0) * 100).rounded()))% steeper than 10°, \(Int(((te["flat"].double ?? 0) * 100).rounded()))% flat"))
        }
        if let t = top {
            facts.append(t.value < 0.3 ? Fact(label: "Slopes face", value: "Every way", note: "no main direction")
                                       : Fact(label: "Slopes face", value: Copy.directions[t.key] ?? t.key, note: "\(Int((t.value * 100).rounded()))% of sloping ground"))
        }
        return AtlasSection(title: "The land") {
            ViewThatFits {
                HStack(alignment: .center, spacing: 16) { FactGrid(facts: facts); if !asp.isEmpty { Rose(aspect: asp) } }
                VStack(alignment: .leading, spacing: 12) { FactGrid(facts: facts); if !asp.isEmpty { Rose(aspect: asp) } }
            }
            bigNote
            Reading(title: "What the land means for the vines", points: pairs(f["reading"]["land"]))
        }
    }

    private var parts: some View {
        let rows = f["parts"].array.sorted {
            let a = $0[7].double ?? 0, b = $1[7].double ?? 0
            return a != b ? a > b : atlas.score($0[0].string ?? "") > atlas.score($1[0].string ?? "")
        }
        let many = rows.count > 12 && !allParts
        return AtlasSection(title: "How its places compare") {
            SubCaption("\(f["depth"].int == 0 ? "A country is too big for one reading." : "Too big and varied for one reading.") Here is how the places inside it differ.")
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        ForEach(["Place", "Growing season", "Elevation", "Steep", "Main grape"], id: \.self) { Text($0).font(.atlasLabel).foregroundStyle(Palette.soft) }
                    }
                    ForEach(Array((many ? Array(rows.prefix(12)) : rows).enumerated()), id: \.offset) { _, r in
                        let id = r[0].string ?? ""
                        GridRow {
                            Button { nav.go(id) } label: {
                                HStack(spacing: 6) {
                                    Swatch(color: Palette.tone(atlas.tone(id)))
                                    Text(atlas.name(id)).font(.atlasNote.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain).foregroundStyle(Palette.teal)
                            Text(gstCell(r)).font(.atlasNote)
                            Text(elevCell(r[3])).font(.atlasNote)
                            Text(r[4].double.map { "\(Int(($0 * 100).rounded()))%" } ?? "").font(.atlasNote)
                            Text(r[6].string ?? "").font(.atlasNote)
                        }
                    }
                }
            }
            if many { Button("Show all \(rows.count)") { withAnimation { allParts = true } }.font(.atlasNote.weight(.semibold)) }
        }
    }


    private func gstCell(_ r: JSON) -> String {
        if case .array(let a) = r[1], a.count == 2 { return "\(Units.tN(a[0].double ?? 0)) to \(Units.deg(a[1].double ?? 0))" }
        if r[8].truthy { return "varies" }
        if let g = r[1].double { return Units.deg(g) + " " + (r[2].string ?? "") }
        return ""
    }

    private func elevCell(_ e: JSON) -> String {
        if case .array(let a) = e { return Units.elevRange(a[0].double ?? 0, a[2].double ?? 0) }
        if let m = e.double { return Units.elev(m) }
        return ""
    }

    private var rules: some View {
        let ru = f["rules"]
        let grapes = ru["grapes"].array
        let yhl = ru["yield_hl"].double, ykg = ru["yield_kg"].double
        let communes = ru["communes"].strings
        return AtlasSection(title: "Grape and vineyard rules", note: "Allowed grapes, not plantings") {
            if ru["province_list"].truthy {   // Italy's EU records: every grape the province approves, not this DOC's own blend (rules in web/atlas.js)
                Text("The EU record lists every grape approved in the province or region, not this wine\u{2019}s own blend rules.").font(.atlasNote).foregroundStyle(Palette.soft)
                DisclosureGroup("All \(grapes.count) grapes") { Chips(items: grapes.map { ($0[0].string ?? "", $0[1].string ?? "", nil) }) }.font(.atlasNote)
            } else if ru["long_list"].truthy {
                DisclosureGroup("The 2022 EU record allows \(grapes.count) grapes") { Chips(items: grapes.map { ($0[0].string ?? "", $0[1].string ?? "", nil) }) }.font(.atlasNote)
            } else if !ru["by_wine"].array.isEmpty {   // each wine's own roles (byWine in web/atlas.js)
                ForEach(Array(ru["by_wine"].array.enumerated()), id: \.offset) { _, w in
                    SubCaption(Copy.Rules.forWine(w[0].string ?? ""))
                    Chips(items: chips(w[1]))
                    if !w[2].array.isEmpty { Text("Also allowed, in smaller roles").font(.atlasNote).foregroundStyle(Palette.soft); Chips(items: chips(w[2])) }
                }
            } else {
                ForEach([("red", "Red grapes"), ("white", "White grapes"), ("pink", "Pink and grey grapes")], id: \.0) { sk, head in
                    let g = grapes.filter { $0[1].string == sk }
                    if !g.isEmpty { SubCaption(head); Chips(items: g.map { ($0[0].string ?? "", sk, nil) }) }
                }
                let un = grapes.filter { $0[1].string == nil || $0[1].string == "" }
                if !un.isEmpty { SubCaption("Grapes"); Chips(items: un.map { ($0[0].string ?? "", "", nil) }) }
                if (ru["cahier"].isNull || ru["roles_unread"].truthy) && grapes.count > 1 { Text(ru["cahier"].isNull ? Copy.Rules.noShares : Copy.Rules.noRoles).font(.atlasNote).foregroundStyle(Palette.soft) }
            }
            if !ru["grapes_other"].array.isEmpty && ru["by_wine"].array.isEmpty { SubCaption("Also allowed, in smaller roles"); Chips(items: chips(ru["grapes_other"])) }
            if !ru["grapes_trial"].array.isEmpty { SubCaption("On trial, to adapt to a changing climate"); Chips(items: chips(ru["grapes_trial"])) }
            ForEach([("limits", Copy.Rules.limitsHead), ("blend", Copy.Rules.blendHead)], id: \.0) { key, head in
                let limits = ru[key].strings
                if !limits.isEmpty {
                    SubCaption(head)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(limits, id: \.self) { l in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\u{2022}").foregroundStyle(Palette.soft)
                                Text(l).font(.atlasBody).foregroundStyle(Palette.ink)
                            }
                        }
                    }
                }
            }
            FactGrid(facts: [
                Fact(label: "Wine types", value: ru["types"].strings.joined(separator: ", ")),
                ru["yield_base"].string.map { Fact(label: "Base yield", value: $0, note: Copy.Rules.baseYield) }
                    ?? Fact(label: ru["yield_ceiling"].truthy ? "Yield ceiling" : "Yield limit", value: yhl.map { "\(fmt($0)) hl/ha" } ?? ykg.map { "\(fmt($0)) kg/ha" } ?? "",
                            note: ru["yield_ceiling"].truthy ? Copy.Rules.yieldCeiling : Copy.Rules.yieldLimit),
                Fact(label: "Recognised", value: ru["recognised"].double.map { String(Int($0)) } ?? "", note: Copy.Rules.recognised),
                Fact(label: "Fewest vines", value: ru["density"].double.map { "\(fmt($0)) per ha" } ?? ""),
                Fact(label: "Irrigation", value: ru["irrigation"].string ?? ""),
                Fact(label: "Communes", value: communes.isEmpty ? "" : fmt(Double(communes.count)), note: "in the 2022 EU record"),
            ])
            if !communes.isEmpty {
                DisclosureGroup("The communes") { Text(communes.joined(separator: ", ")).font(.atlasNote).frame(maxWidth: .infinity, alignment: .leading) }
                    .font(.atlasNote)
            }
        }
    }

    private var ava: some View {
        let av = f["ava"]
        let counties = av["counties"].strings
        return AtlasSection(title: "The AVA", note: "US rules name no grapes") {
            FactGrid(facts: [
                Fact(label: "In effect from", value: av["created"].string.map { String($0.prefix(4)) } ?? ""),
                Fact(label: "State", value: av["states"].strings.joined(separator: ", ")),
                Fact(label: "Counties", value: counties.isEmpty ? "" : fmt(Double(counties.count)), note: counties.prefix(6).joined(separator: ", ") + (counties.count > 6 ? "…" : "")),
            ])
            if !av["within"].strings.isEmpty { SubCaption("Inside"); Chips(items: av["within"].strings.map { ($0, "", nil) }) }
            if !av["overlaps"].strings.isEmpty { SubCaption("Partly inside"); Chips(items: av["overlaps"].strings.map { ($0, "", nil) }) }
            if !av["contains"].strings.isEmpty { SubCaption("Holds"); Chips(items: av["contains"].strings.map { ($0, "", nil) }) }
            if let u = av["cfr_url"].string, let url = URL(string: u) {
                Link("Its boundary in the CFR, § \(av["cfr"].string ?? "")", destination: url).font(.atlasNote)
            }
        }
    }

    private var gi: some View {
        let g = f["gi"]
        let type = g["type"].string ?? "GI"
        return AtlasSection(title: "The GI", note: "Australian GIs name no grapes") {
            FactGrid(facts: [
                Fact(label: "Type", value: capitalized(type), note: g["year"].int.map { "Registered \($0)" } ?? ""),
                g["vines_ha"].truthy
                    ? Fact(label: "Vineyards", value: Units.areaShort(g["vines_ha"].double ?? 0), note: "in \(Units.land(g["area_km2"].double ?? 0)) in all")
                    : Fact(label: "Area", value: Units.land(g["area_km2"].double ?? 0)),
            ])
            if let u = g["url"].string, let url = URL(string: u) { Link("Its entry at Wine Australia", destination: url).font(.atlasNote) }
        }
    }

    private var found: some View {
        let R = f["research"]
        let claims = R["claims"].array
        var topics: [String] = []
        for c in claims { let t = c["topic"].string ?? ""; if !topics.contains(t) { topics.append(t) } }
        return VStack(alignment: .leading) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(topics, id: \.self) { t in
                        SubCaption(capitalized(t))
                        ForEach(Array(claims.filter { $0["topic"].string == t }.enumerated()), id: \.offset) { _, x in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(x["claim"].string ?? "").font(.atlasBody).fixedSize(horizontal: false, vertical: true)
                                if let s = x["strength"].string, s != "Strong" {
                                    Text(s).font(.system(size: 11, weight: .bold)).padding(.horizontal, 6).background(Palette.goldTint)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("What we found").font(.atlasSection).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(claims.count) notes" + (R["read"].string.map { ", read " + $0 } ?? "")).font(.atlasNote).foregroundStyle(Palette.soft)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Palette.landEdge.opacity(0.6)).frame(height: 0.5) }
    }

    private var knownLine: String? {
        guard atlas.scored else { return nil }
        let kn = f["known"]
        if !kn.truthy { return "No Wikipedia article of its own." }
        let days = kn["days"].int ?? 60
        if let n = kn["articles"].int, n > 0 {
            var s = "Scored from \(fmt(Double(n))) Wikipedia article\(n == 1 ? "" : "s") on it and its places, \(fmt(kn["total"].double)) page views in the last \(days) days in all"
            if let b = kn["best"].string { s += ". Best known: \(atlas.name(b))" }
            s += "."
            if kn["langs"].isNull { s += " No article of its own." }
            return s
        }
        let langs = kn["langs"].int ?? 0
        return "Known: in \(langs) Wikipedia\(langs == 1 ? "" : "s"), \(fmt(kn["views"].double)) page views in the last \(days) days."
    }

    private var sources: some View {
        let src = f["sources"].array + f["research"]["sources"].array
        return AtlasSection(title: "Sources") {
            if let k = knownLine {
                VStack(alignment: .leading, spacing: 4) {
                    Text(k).font(.atlasNote).foregroundStyle(Palette.soft)
                    if let u = f["known"]["url"].string, let url = URL(string: u) { Link("Read about it on Wikipedia", destination: url).font(.atlasNote) }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(src.enumerated()), id: \.offset) { _, s in
                    let name = s["name"].string ?? ""
                    if let u = s["url"].string, let url = URL(string: u) {
                        Link(name, destination: url).font(.atlasNote).multilineTextAlignment(.leading)
                    } else {
                        Text(name).font(.atlasNote).foregroundStyle(Palette.soft)
                    }
                }
            }
        }
    }
}
