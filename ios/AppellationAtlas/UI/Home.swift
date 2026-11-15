import simd
import SwiftUI

extension EnvironmentValues {
    /// Puts the cursor in the search field (the sheet's on iPhone).
    @Entry var startSearch: () -> Void = {}
}

/// The first page: what the globe shows, where to start, and how to read it.
struct HomePage: View {
    let compact: Bool
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @Environment(\.startSearch) private var startSearch
    @AppStorage("onboarded") private var onboarded = false

    /// The classics to start with: well known, and each a different look.
    static let classics = ["france/burgundy", "france/bordeaux", "france/champagne", "italy/barolo", "spain/rioja", "germany/mosel",
                           "portugal/douro", "hungary/tokaj", "united-states/napa-valley", "australia/barossa-valley",
                           "new-zealand/marlborough", "argentina/mendoza"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Copy.homeTitle).font(.atlasTitle).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                Text(Copy.worldCount(atlas.places.count)).font(.atlasBody).foregroundStyle(Palette.soft)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: 10) {
                if compact { Tile(icon: "magnifyingglass", title: "Search", action: startSearch) }
                Tile(icon: "dice", title: "Surprise me") { surprise() }
                Tile(icon: "hand.tap", title: "How it works") { onboarded = false }
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start with a classic").font(.atlasSection).foregroundStyle(Palette.ink)
                    Text("Benchmark regions the WSET Diploma teaches first.").font(.atlasNote).foregroundStyle(Palette.soft)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Self.classics.filter { atlas.places[$0] != nil }, id: \.self) { id in
                            Button { nav.go(id) } label: { ClassicCard(id: id) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }

            MapKey()
            SavedList()
            PlacesHere(folded: !compact)
            AboutButton().font(.atlasNote)
        }
    }

    private func surprise() {
        let pool = atlas.places.values.filter { $0.benchmark && $0.parent != "world" && atlas.geo[$0.id]?.source != nil }
        if let p = pool.randomElement() { nav.go(p.id) }
    }
}

/// A big friendly button with an icon over a word.
struct Tile: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(Palette.teal)
                Text(title).font(.caption.weight(.bold)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// A classic region as a card: its own shape, its name and its country.
struct ClassicCard: View {
    let id: String
    @Environment(Atlas.self) private var atlas

    var body: some View {
        let p = atlas.places[id]
        VStack(alignment: .leading, spacing: 8) {
            PlaceShape(polys: atlas.shape(id), fill: Palette.gold4[3], edge: Palette.gold4[4])
                .frame(height: 92)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 1) {
                Text(p?.name ?? id).font(.subheadline.weight(.heavy)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(atlas.name(String(id.split(separator: "/").first ?? ""))).font(.atlasNote).foregroundStyle(Palette.soft).lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 138)
        .background(LinearGradient(colors: [Palette.goldTint, Palette.fill], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p?.name ?? id), \(atlas.name(String(id.split(separator: "/").first ?? "")))")
        .accessibilityAddTraits(.isButton)
    }
}

/// A place's outline, drawn from straight above it and fitted to the space.
struct PlaceShape: View {
    let polys: [Poly]
    var fill: Color
    var edge: Color

    var body: some View {
        Canvas { ctx, size in
            guard !polys.isEmpty else { return }
            var sum = V3.zero
            for p in polys { sum += p.center }
            let c = simd_length(sum) > 0 ? sum / simd_length(sum) : polys[0].center
            let reach = polys.map { acos(max(-1, min(1, simd_dot($0.center, c)))) + $0.radius }.max() ?? 0.1
            let lon = atan2(c.y, c.x) * 180 / .pi, lat = asin(max(-1, min(1, c.z))) * 180 / .pi
            let R = min(size.width, size.height) / 2 * 0.92 / sin(min(.pi / 2, max(0.0005, reach)))
            let P = Projector(Camera(lon: lon, lat: lat, R: R), center: CGPoint(x: size.width / 2, y: size.height / 2),
                              diagonal: hypot(size.width, size.height) * 4)
            var path = P.path(polys)
            // then fit what was drawn to the space exactly, whatever stray islands set the first guess
            let bb = path.boundingRect
            if !bb.isNull, bb.width > 0, bb.height > 0 {
                let k = min(size.width / bb.width, size.height / bb.height) * 0.94
                path = path.applying(CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
                    .scaledBy(x: k, y: k).translatedBy(x: -bb.midX, y: -bb.midY))
            }
            ctx.fill(path, with: .color(fill))
            ctx.stroke(path, with: .color(edge), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// How to read the colors on the map.
struct MapKey: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reading the map").font(.atlasSection).foregroundStyle(Palette.ink)
            HStack(spacing: 18) { row(Palette.gold4, "Benchmark"); row(Palette.grey4, "Emerging") }
            ForEach(Copy.worldIntro, id: \.self) { Text($0).font(.atlasNote).foregroundStyle(Palette.soft) }
        }
        .padding(14)
        .background(Palette.fill.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ ramp: [Color], _ name: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) { ForEach(1..<5, id: \.self) { ramp[$0].frame(width: 14, height: 22) } }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.landEdge, lineWidth: 0.5))
                .accessibilityHidden(true)
            Text(name).font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
        }
    }
}
