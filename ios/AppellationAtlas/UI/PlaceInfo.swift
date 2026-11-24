import SwiftUI

/// What is known about a place, in the website's order: what the place is, then what grows there, then why it grows
/// there, then the law, then the notes. Every sentence comes from the data, as on the website.
struct PlaceInfo: View {
    let f: JSON
    let range: (Double, Double)
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @State private var allParts = false

    private enum Key: String, CaseIterable {
        case keyfacts, style, terms, glance, short, planted, climate, soil, land, parts, rules, ava, gi, found, none, sources
        var jump: String? {
            switch self {
            case .style: "Style"
            case .terms: "Labeling"
            case .planted: "Planted"
            case .climate: "Climate"
            case .soil: "Rock and soil"
            case .land: "Land"
            case .parts: "Compare"
            case .rules: "Vineyard"
            case .ava: "AVA"
            case .gi: "GI"
            case .found: "Notes"
            default: nil
            }
        }
    }

    private var present: [Key] {
        var k: [Key] = []
        if !f["keyfacts"].array.isEmpty { k.append(.keyfacts) }
        if !f["style"]["notes"].array.isEmpty { k.append(.style) }
        if !f["terms"].array.isEmpty { k.append(.terms) }
        if f["summary"].truthy { k.append(.glance) }
        if f["research"]["sheet"].truthy { k.append(.short) }
        if !f["planted"]["grapes"].array.isEmpty { k.append(.planted) }
        if f["climate"].truthy { k.append(.climate) }
        if f["soil"].truthy || f["rocks"].truthy { k.append(.soil) }
        if f["terrain"].truthy { k.append(.land) }
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
        let keys = present
        let jumps = keys.filter { $0.jump != nil }
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                if jumps.count >= 3 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(jumps, id: \.self) { k in
                                Button(k.jump!) { withAnimation { proxy.scrollTo(k, anchor: .top) } }
                                    .font(.system(size: 13, weight: .heavy))
                                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                ForEach(keys, id: \.self) { k in section(k).id(k) }
                FeedbackLink(name: f["name"].string ?? "", id: f["id"].string ?? "").padding(.top, 8)
            }
            // For screenshots: run with -section climate to open the page at that section.
            .task {
                guard let s = UserDefaults.standard.string(forKey: "section"), let k = Key(rawValue: s), keys.contains(k) else { return }
                try? await Task.sleep(for: .seconds(1))
                proxy.scrollTo(k, anchor: .top)
            }
        }
    }

    @ViewBuilder private func section(_ k: Key) -> some View {
        switch k {
        case .keyfacts: keyfacts
        case .style: style
        case .terms: terms
        case .glance: glance
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
        AtlasSection(title: "Labeling rules") {
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
                        Circle().fill(Palette.teal).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        Text(t).font(.atlasBody).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
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
                        Circle().fill(Palette.teal).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        Text(t).font(.atlasBody).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var glance: some View {
        let sm = f["summary"]
        let kinds = sm["kinds"].array.map { plural($0[1].int ?? 0, $0[0].string ?? "") }.joined(separator: ", ")
        return AtlasSection(title: "At a glance") {
            FactGrid(facts: [
                Fact(label: "Places inside", value: fmt(sm["places"].double), note: kinds),
                Fact(label: "Growing season", value: sm["gst"].truthy ? Self.range(toF(sm["gst"][0].double ?? 0), toF(sm["gst"][1].double ?? 0)) : "", note: "average temperature across its places"),
            ])
            if !sm["grapes"].array.isEmpty && !f["planted"].truthy {
                let n = sm["with_rules"].int ?? 0
                SubCaption("The grapes most often allowed, and in how many of its \(n) appellation\(n == 1 ? "" : "s") with rules:")
                Chips(items: chips(sm["grapes"]))
            }
        }
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
        let acres = fmt(ha * 2.471)
        let year = pl["year"].int.map(String.init) ?? ""
        let older = pl["whites_older"].bool == true   // France's regional whites come from an earlier survey than its reds
        let amount = older ? Copy.whitesOlder(year) : "\(acres) acres of wine grapes, \(year)."
        let caption = wide
            ? "No figures exist for \(name) alone. These are for \(where_), the wider area it sits in: \(amount)"
            : (older ? "Wine grapes\(where_.isEmpty ? "" : " " + where_): " + amount : "\(acres) acres of wine grapes\(where_.isEmpty ? "" : " " + where_), \(year).") + (pl["any_name"].bool == true ? Copy.Rules.anyName : "")
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
                Fact(label: "Growing season", value: "\(Int(toF(c["gst"].double ?? 0).rounded()))°F", note: south ? "average, October to April" : "average, April to October"),
                Fact(label: "Heat", value: "\(fmt(((c["gdd"].double ?? 0) * 1.8 / 10).rounded() * 10)) degree days", note: "°F, above 50°F"),
                Fact(label: "Climate type", value: c["koppen_name"].string ?? c["koppen"].string ?? "", note: c["koppen"].string.map { "Köppen " + $0 + ", from a 1991 to 2020 map" } ?? ""),
            ])
            SubCaption("Growing season: \(gi >= 0 ? Copy.growingSeason[gi].0.lowercased() : "?")")
            ScaleBar(segments: Copy.growingSeason.map { ($0.0, $0.3) }, index: gi, position: gp, label: "Growing season temperature class")
            SubCaption("Winkler region \(wk[0].string ?? "")")
            ScaleBar(segments: Copy.winkler.map { ($0.0, $0.3) }, index: wi, position: wp, label: "Winkler region")
            if let t = wk[1].string, !t.isEmpty { Text(t).font(.atlasBody) }
            bigNote
            Reading(title: "What the climate means for the vines", points: pairs(reading))
            tempChart(c, south)
        }
    }

    private func tempChart(_ c: JSON, _ south: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SubCaption("Average temperature by month, °F")
            MonthsChart(values: c["tavg"].doubles.map(toF), unit: "°F", season: Palette.coral, base: Palette.monthTemp, south: south, labels: true)
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
                SubCaption("The soil, 1 to 2 feet down")
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
        var facts = [Fact(label: "Elevation", value: "\(fmt(feet(te["elev"][1].double ?? 0))) ft", note: "most of it \(fmt(feet(te["elev"][0].double ?? 0))) to \(fmt(feet(te["elev"][2].double ?? 0))) ft")]
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

    /// "59°F" when both ends round the same, else "57 to 61°F".
    static func range(_ lo: Double, _ hi: Double) -> String {
        let a = Int(lo.rounded()), b = Int(hi.rounded())
        return a == b ? "\(a)°F" : "\(a) to \(b)°F"
    }

    private func gstCell(_ r: JSON) -> String {
        if case .array(let a) = r[1], a.count == 2 { return "\(Int(toF(a[0].double ?? 0).rounded())) to \(Int(toF(a[1].double ?? 0).rounded()))°F" }
        if r[8].truthy { return "varies" }
        if let g = r[1].double { return "\(Int(toF(g).rounded()))°F " + (r[2].string ?? "") }
        return ""
    }

    private func elevCell(_ e: JSON) -> String {
        if case .array(let a) = e { return "\(fmt(feet(a[0].double ?? 0))) to \(fmt(feet(a[2].double ?? 0))) ft" }
        if let m = e.double { return "\(fmt(feet(m))) ft" }
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
                    ? Fact(label: "Vineyards", value: "\(fmt(g["vines_ha"].double)) ha", note: "in \(fmt(g["area_km2"].double)) km² in all")
                    : Fact(label: "Area", value: "\(fmt(g["area_km2"].double)) km²"),
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
