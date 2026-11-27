import SwiftData
import simd
import SwiftUI

extension EnvironmentValues {
    /// Puts the cursor in the search field (the sheet's on iPhone).
    @Entry var startSearch: () -> Void = {}
}

/// Home: search, the map filter and your saved places, in the card at the bottom of a phone or the panel at the
/// left of an iPad (the side panel in web/index.html). Further down, the often compared pairs and the classics.
struct HomeCard: View {
    var wide = false
    var onFocus: (Bool) -> Void = { _ in }
    @State private var query = ""
    @FocusState private var focused: Bool
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @AppStorage("onboarded") private var onboarded = false
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]

    /// The classics to start with: well known, and each a different look.
    static let classics = ["france/burgundy", "france/bordeaux", "france/champagne", "italy/barolo", "spain/rioja", "germany/mosel",
                           "portugal/douro", "hungary/tokaj", "united-states/napa-valley", "australia/barossa-valley",
                           "new-zealand/marlborough", "argentina/mendoza"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if wide {
                HStack {
                    Text("Appellation Atlas").font(.display(20, .heavy, relativeTo: .title3)).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                    Spacer()
                    SettingsButton(size: 40, plain: true)
                }
            }
            DSearchBox(query: $query, focused: $focused, height: wide ? 46 : 48)
            if query.isEmpty && !focused {
                MapFilterPicker()
                savedGrid
                if wide || saved.isEmpty { OftenComparedList(count: wide ? 3 : 2) }
                if !wide { more }
                else {
                    HStack(spacing: 4) {
                        AboutButton(plain: true)
                        Text("·").foregroundStyle(Palette.soft)
                        Button("How it works") { onboarded = false }
                    }
                    .font(.text(12, .bold, relativeTo: .caption)).foregroundStyle(Palette.teal)
                }
            } else {
                SearchResults(query: $query) { query = ""; focused = false }
            }
        }
        .onChange(of: focused) { _, f in onFocus(f) }
    }

    /// Your saved places, two to a row, and a way to compare two of them.
    @ViewBuilder private var savedGrid: some View {
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Saved").font(.display(15, .bold, relativeTo: .headline)).foregroundStyle(Palette.ink)
                    Spacer()
                    if !wide { Button("Compare two") { nav.compare = CompareRoute() }.font(.text(13, .heavy, relativeTo: .footnote)).foregroundStyle(Palette.teal) }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                    ForEach(saved.filter { atlas.places[$0.placeID] != nil }) { s in
                        Button { nav.go(s.placeID) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Rectangle().fill(Palette.tone(atlas.tone(s.placeID))).frame(width: 12, height: 12)
                                    Text(atlas.name(s.placeID)).font(.text(wide ? 14 : 15, .heavy, relativeTo: .subheadline)).foregroundStyle(Palette.ink).lineLimit(1)
                                }
                                let sub = [atlas.kind(s.placeID), atlas.places[s.placeID]?.country ?? ""].filter { !$0.isEmpty && $0 != atlas.name(s.placeID) }.joined(separator: ", ")
                                Text(sub.isEmpty ? " " : sub).font(.text(12, relativeTo: .caption)).foregroundStyle(Palette.soft).lineLimit(1)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBox(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Under the card on a phone, seen when it is pulled up.
    private var more: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !saved.isEmpty { OftenComparedList() }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start with a classic").font(.display(15, .bold, relativeTo: .headline)).foregroundStyle(Palette.ink)
                    Text("The benchmark regions to learn first.").font(.atlasNote).foregroundStyle(Palette.soft)
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
            HStack(spacing: 10) {
                Tile(icon: "dice", title: "Surprise me") { surprise() }
                Tile(icon: "hand.tap", title: "How it works") { onboarded = false }
                Tile(icon: "info.circle", title: "About") { nav.about = true }
            }
            FeedbackLink(name: "Home", id: "world")
        }
        .padding(.top, 10)
    }

    private func surprise() {
        let pool = atlas.places.values.filter { atlas.isBenchmark($0.id) && $0.parent != "world" && atlas.geo[$0.id]?.source != nil }
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

/// The feedback button at the bottom of every tray, as on the website.
struct FeedbackLink: View {
    let name: String
    let id: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Copy.feedbackPrompt).font(.atlasNote).foregroundStyle(Palette.soft)
            if let url = Copy.feedbackURL(name: name, id: id) {
                Link(Copy.feedbackButton, destination: url)
                    .font(.atlasNote).buttonStyle(.bordered).buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
