import SwiftUI

/// iPhone: the sheet over the globe. At home it is the search card; on a place, the place's page.
struct PlaceSheet: View {
    @Binding var detent: PresentationDetent
    @Environment(Nav.self) private var nav

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                Group {
                    if nav.place == "world" {
                        HomeCard { f in if f { withAnimation { detent = .large } } }
                            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 30)
                    } else {
                        PlaceInfo(compact: true).padding(.bottom, 40)
                    }
                }
                .id("top")
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: nav.place) { reader.scrollTo("top", anchor: .top) }
        }
        .onboarding()
        .compareCover()
        .settingsCover()
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

/// The places on this view: Essential benchmarks, then Benchmarks, then Inside a benchmark, then More in (the view), with the rest behind Show all.
struct PlacesHere: View {
    let folded: Bool
    var titled = true
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @State private var showAll = false
    @State private var open = false

    var body: some View {
        let vid = atlas.viewFor(nav.place)
        let here = atlas.placesIn(vid)
        let range = atlas.range(here.map(\.id))
        let ess = here.filter { atlas.tone($0.id) == .essential }, bench = here.filter { atlas.tone($0.id) == .benchmark }
        let inner = here.filter { atlas.tone($0.id) == .inside }, others = here.filter { atlas.tone($0.id) == .other }
        let gold = !ess.isEmpty || !bench.isEmpty || !inner.isEmpty
        let cap = gold ? 12 : 30
        let shown = showAll ? others : Array(others.prefix(cap))
        let title = vid == "world" ? "Countries" : "Places in \(atlas.name(vid))"
        if !here.isEmpty {
            let list = VStack(alignment: .leading, spacing: 10) {
                if !ess.isEmpty { group(Copy.tone(.essential).many, ess, count: ess.count, range: range) }
                if !bench.isEmpty { group(ess.isEmpty ? Copy.tone(.benchmark).many : "Other benchmarks", bench, count: bench.count, range: range) }
                if !inner.isEmpty { group(Copy.tone(.inside).many, inner, count: inner.count, range: range) }
                if !shown.isEmpty { group(!gold ? nil : Copy.moreIn(vid, atlas.name(vid)), shown, count: others.count, range: range) }   // no heading when nothing here is gold
                if others.count > shown.count {
                    Button("Show all \(others.count)") { withAnimation { showAll = true } }.font(.atlasNote.weight(.semibold))
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
                    if titled { Text(title).font(.atlasSection).foregroundStyle(Palette.ink) }
                    list
                }
                .onChange(of: vid) { showAll = false }
            }
        }
    }

    private func group(_ head: String?, _ list: [Place], count: Int, range: (Double, Double)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let head {
                HStack(spacing: 6) {
                    Text(head.uppercased()).font(.atlasLabel).kerning(0.6).foregroundStyle(Palette.soft)
                    Text("\(count)").font(.atlasNote).foregroundStyle(Palette.soft)
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(list) { p in
                    Button { nav.go(p.id) } label: {
                        HStack(spacing: 6) {
                            Swatch(color: Palette.tone(atlas.tone(p.id)))
                            Text(p.name).font(.system(size: 13, weight: .heavy))
                            if atlas.geo[p.id]?.source == nil { Text("no map").font(.system(size: 11)).foregroundStyle(Palette.soft) }
                        }
                        .foregroundStyle(nav.place == p.id ? Color.white : Palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(nav.place == p.id ? Palette.target : Palette.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.name), \(Copy.tone(atlas.tone(p.id)).one)")
                }
            }
        }
    }
}
