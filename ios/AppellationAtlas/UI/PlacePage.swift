import SwiftUI

/// iPhone: the sheet over the globe, with search at the top.
struct PlaceSheet: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if query.isEmpty {
                    PlacePage(compact: true).padding(.horizontal, 20).padding(.bottom, 40)
                } else {
                    SearchResults(query: $query).padding(.horizontal, 20)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search a country, region or appellation")
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// iPad: search and the places to go to, beside the globe.
struct Sidebar: View {
    @State private var query = ""
    @Environment(Nav.self) private var nav
    @Environment(Atlas.self) private var atlas

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if query.isEmpty {
                    SavedList()
                    Crumbs()
                    PlacesHere(folded: false)
                } else {
                    SearchResults(query: $query)
                }
            }
            .padding(16)
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search places")
        .navigationTitle("Atlas")
        .toolbar { ToolbarItem(placement: .bottomBar) { AboutButton() } }
    }
}

struct SearchResults: View {
    @Binding var query: String
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        let hits = atlas.search(query)
        LazyVStack(alignment: .leading, spacing: 0) {
            if hits.isEmpty {
                Text(query.count < 2 ? "Type at least two letters." : "No place by that name.").font(.atlasBody).foregroundStyle(Palette.soft).padding(.vertical, 12)
            }
            ForEach(hits) { p in
                Button {
                    nav.go(p.id); query = ""; dismissSearch()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text([p.kind, p.country].filter { !$0.isEmpty }.joined(separator: ", ")).font(.atlasNote).foregroundStyle(Palette.soft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}

/// A place's whole page: who it is, where it sits, the places inside it, then what is known.
struct PlacePage: View {
    let compact: Bool
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @Environment(Globe.self) private var globe

    var body: some View {
        let id = nav.place
        let f = id == "world" ? nil : atlas.facts(id)
        let leaf = id != atlas.viewFor(id)
        VStack(alignment: .leading, spacing: 12) {
            PlaceHeader(id: id, facts: f).padding(.top, compact ? 16 : 0)
            if id != "world" { SaveButton(placeID: id) }
            if compact && id != "world" { Crumbs() }
            if id == "world" {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Copy.worldCount(atlas.places.count))
                    ForEach(Copy.worldIntro, id: \.self) { Text($0) }
                }
                .font(.atlasBody).foregroundStyle(Palette.ink)
                if compact { SavedList(); PlacesHere(folded: false) }
                AboutButton().font(.atlasNote).padding(.top, 8)
            } else {
                if compact && !leaf { PlacesHere(folded: false) }
                if let f { PlaceInfo(f: f, range: globe.range) } else { ProgressView() }
                if compact && leaf { PlacesHere(folded: true) }
            }
        }
        .id(id)
    }
}

struct PlaceHeader: View {
    let id: String
    let facts: JSON?
    @Environment(Atlas.self) private var atlas

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if id == "world" {
                Text("The world").font(.atlasTitle).foregroundStyle(Palette.ink)
            } else {
                HStack(spacing: 6) {
                    let kind = kindText
                    if !kind.isEmpty { Text(kind.uppercased()).font(.atlasEyebrow).kerning(1.2).foregroundStyle(Palette.coralText) }
                    Text(atlas.isBenchmark(id) ? "BENCHMARK REGION" : "EMERGING REGION")
                        .font(.atlasEyebrow).kerning(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(atlas.isBenchmark(id) ? Palette.gold4[2] : Palette.grey4[2], in: RoundedRectangle(cornerRadius: 2))
                        .foregroundStyle(Palette.ink)
                }
                Text(atlas.name(id)).font(.atlasTitle).foregroundStyle(Palette.ink).minimumScaleFactor(0.5).lineLimit(3)
                if let also = facts?["also"].strings, !also.isEmpty {
                    Text("Also " + also.joined(separator: ", ")).font(.atlasNote).foregroundStyle(Palette.soft)
                }
                if let s = facts?["shape"].string, let note = Copy.shapeNote[s] {
                    Text(note).font(.atlasNote).foregroundStyle(Palette.soft)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var kindText: String {
        guard let f = facts else { return "" }
        let kinds = f["kind"].strings
        if !kinds.isEmpty { return kinds.map(capitalized).joined(separator: " and ") }
        if f["depth"].int == 0 { return "Country" }
        return f["shape"].string == "Eurostat LAU, the commune it is named for" ? "Commune" : "Region"
    }
}

/// The way back up: the world, then each place down to this one.
struct Crumbs: View {
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav

    var body: some View {
        let chain = ["world"] + atlas.chain(atlas.viewFor(nav.place)) + (nav.place != atlas.viewFor(nav.place) ? [nav.place] : [])
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(chain.enumerated()), id: \.offset) { k, id in
                    if k > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.soft) }
                    if k == chain.count - 1 {
                        Text(atlas.name(id)).font(.atlasNote.weight(.bold)).foregroundStyle(Palette.ink)
                    } else {
                        Button(atlas.name(id)) { nav.go(id) }.font(.atlasNote).foregroundStyle(Palette.teal)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Where this place sits")
    }
}

/// The places on this view: Benchmark regions first, then Emerging ones, with the rest behind Show all.
struct PlacesHere: View {
    let folded: Bool
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @State private var showAll = false
    @State private var open = false

    var body: some View {
        let vid = atlas.viewFor(nav.place)
        let here = atlas.placesIn(vid)
        let range = atlas.range(here.map(\.id))
        let bench = here.filter(\.benchmark), emerging = here.filter { !$0.benchmark }
        let cap = bench.isEmpty ? 30 : 12
        let shown = showAll ? emerging : Array(emerging.prefix(cap))
        let title = vid == "world" ? "Countries" : "Places in \(atlas.name(vid))"
        if !here.isEmpty {
            let list = VStack(alignment: .leading, spacing: 10) {
                if !bench.isEmpty { group("Benchmark regions", bench, count: bench.count, range: range) }
                if !shown.isEmpty { group("Emerging regions", shown, count: emerging.count, range: range) }
                if emerging.count > shown.count {
                    Button("Show all \(emerging.count)") { withAnimation { showAll = true } }.font(.atlasNote.weight(.semibold))
                }
            }
            if folded {
                DisclosureGroup(isExpanded: $open) { list.padding(.top, 8) } label: {
                    HStack {
                        Text("Other places in \(atlas.name(vid))").font(.atlasSection).foregroundStyle(Palette.ink)
                        Text("\(here.count)").font(.atlasNote).foregroundStyle(Palette.soft)
                    }
                }
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.atlasSection).foregroundStyle(Palette.ink)
                    list
                }
                .onChange(of: vid) { showAll = false }
            }
        }
    }

    private func group(_ head: String, _ list: [Place], count: Int, range: (Double, Double)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(head.uppercased()).font(.atlasLabel).kerning(0.6).foregroundStyle(Palette.soft)
                Text("\(count)").font(.atlasNote).foregroundStyle(Palette.soft)
            }
            FlowLayout(spacing: 6) {
                ForEach(list) { p in
                    Button { nav.go(p.id) } label: {
                        HStack(spacing: 6) {
                            Swatch(color: Palette.shade(benchmark: p.benchmark, tier: atlas.tier(p.id, range: range)))
                            Text(p.name).font(.system(size: 13, weight: .heavy))
                            if atlas.geo[p.id]?.source == nil { Text("no map").font(.system(size: 11)).foregroundStyle(Palette.soft) }
                        }
                        .foregroundStyle(nav.place == p.id ? Color.white : Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(nav.place == p.id ? Palette.target : Palette.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.name), \(p.benchmark ? "Benchmark" : "Emerging") region")
                }
            }
        }
    }
}
