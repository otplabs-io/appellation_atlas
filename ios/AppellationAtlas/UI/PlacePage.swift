import SwiftUI

/// iPhone: the sheet over the globe, with search at the top. The search field is part of the page, so it scrolls with it.
struct PlaceSheet: View {
    @Binding var detent: PresentationDetent
    @State private var query = ""
    @FocusState private var searching: Bool
    @Environment(Nav.self) private var nav

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SearchField(query: $query, focused: $searching).padding(.top, 20).id("top")
                    if query.isEmpty && !searching {
                        PlacePage(compact: true).padding(.top, 16)
                    } else {
                        SearchResults(query: $query) { query = ""; searching = false }.padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: searching) { _, s in if s { withAnimation { detent = .large } } }
            .onChange(of: nav.place) { reader.scrollTo("top", anchor: .top) }
        }
        .environment(\.startSearch, { searching = true })
        .onboarding()
    }
}

/// The search field: a magnifier, the words, and a way to clear them or stop.
struct SearchField: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.soft)
                TextField("Search a country, region or appellation", text: $query)
                    .focused(focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.soft) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear the search")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Palette.fill, in: Capsule())
            if focused.wrappedValue {
                Button("Cancel") { query = ""; focused.wrappedValue = false }.font(.subheadline.weight(.semibold))
            }
        }
        .animation(.snappy, value: focused.wrappedValue)
    }
}

/// iPad: search and the places to go to, beside the globe.
struct Sidebar: View {
    /// Set from the page beside the globe to put the cursor in the search field.
    @Binding var searching: Bool
    @State private var query = ""
    @FocusState private var focused: Bool
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
                    SearchResults(query: $query) { query = "" }
                }
            }
            .padding(16)
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search places")
        .searchFocused($focused)
        .task(id: searching) {
            guard searching else { return }
            try? await Task.sleep(for: .milliseconds(350))   // once the sidebar has slid in
            focused = true; searching = false
        }
        .navigationTitle("Wine Atlas")
        .toolbar { ToolbarItem(placement: .bottomBar) { AboutButton() } }
    }
}

struct SearchResults: View {
    @Binding var query: String
    var done: () -> Void = {}
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav

    var body: some View {
        let hits = atlas.search(query)
        LazyVStack(alignment: .leading, spacing: 0) {
            if hits.isEmpty && !query.isEmpty {
                Text(query.count < 2 ? "Type at least two letters." : "No place by that name.").font(.atlasBody).foregroundStyle(Palette.soft).padding(.vertical, 12)
            }
            ForEach(hits) { p in
                Button {
                    nav.go(p.id); done()
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
        if id == "world" {
            HomePage(compact: compact).id(id)
        } else {
            // long-press any words on the page to select and copy them
            page(id, f, leaf).textSelection(.enabled)
        }
    }

    private func page(_ id: String, _ f: JSON?, _ leaf: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaceHeader(id: id, facts: f)
            if let b = f?["blurb"]["text"].string, !b.isEmpty {   // what the place is known for (blurb in web/atlas.js)
                Text(b).font(.atlasBody).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
            }
            SaveButton(placeID: id)
            if compact { Crumbs() }
            if compact && !leaf { PlacesHere(folded: false) }
            if let f { PlaceInfo(f: f, range: globe.range) } else { ProgressView() }
            if compact && leaf { PlacesHere(folded: true) }
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
                    Text((atlas.isBenchmark(id) ? Copy.level(atlas.level).on : Copy.level(atlas.level).off).uppercased())
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
        let bench = here.filter { atlas.isBenchmark($0.id) }, emerging = here.filter { !atlas.isBenchmark($0.id) }
        let cap = bench.isEmpty ? 30 : 12
        let shown = showAll ? emerging : Array(emerging.prefix(cap))
        let title = vid == "world" ? "Countries" : "Places in \(atlas.name(vid))"
        if !here.isEmpty {
            let list = VStack(alignment: .leading, spacing: 10) {
                if !bench.isEmpty { group(Copy.level(atlas.level).ons, bench, count: bench.count, range: range) }
                if !shown.isEmpty { group(Copy.level(atlas.level).offs, shown, count: emerging.count, range: range) }
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
                            Swatch(color: Palette.shade(benchmark: atlas.isBenchmark(p.id), tier: atlas.tier(p.id, range: range)))
                            Text(p.name).font(.system(size: 13, weight: .heavy))
                            if atlas.geo[p.id]?.source == nil { Text("no map").font(.system(size: 11)).foregroundStyle(Palette.soft) }
                        }
                        .foregroundStyle(nav.place == p.id ? Color.white : Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(nav.place == p.id ? Palette.target : Palette.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.name), \(atlas.isBenchmark(p.id) ? Copy.level(atlas.level).on : Copy.level(atlas.level).off)")
                }
            }
        }
    }
}
