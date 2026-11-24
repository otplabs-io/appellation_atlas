import simd
import SwiftUI

extension View {
    /// Shows the welcome pages until they have been seen once. How it works on the home page shows them again.
    func onboarding() -> some View { modifier(OnboardingCover()) }
}

private struct OnboardingCover: ViewModifier {
    @AppStorage("onboarded") private var onboarded = false

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            Onboarding { onboarded = true }
        }
    }
}

/// Four short pages: what the Atlas is, how to read its colors, how to move around, and what is yours to keep.
struct Onboarding: View {
    let finish: () -> Void
    @State private var page = 0
    @Environment(Atlas.self) private var atlas
    private let count = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < count - 1 {
                    Button("Skip", action: finish).font(.subheadline.weight(.semibold)).padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .frame(height: 44)

            TabView(selection: $page) {
                welcome.tag(0)
                colors.tag(1)
                moving.tag(2)
                yours.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule().fill(i == page ? Palette.teal : Palette.landEdge).frame(width: i == page ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy, value: page)
            .accessibilityElement()
            .accessibilityLabel("Page \(page + 1) of \(count)")
            .padding(.bottom, 18)

            Button {
                if page < count - 1 { withAnimation { page += 1 } } else { finish() }
            } label: {
                Text(page < count - 1 ? "Next" : "Start exploring")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.teal)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Palette.paper.ignoresSafeArea())
    }

    // ---- pages

    private var welcome: some View {
        Page(title: "Every wine place on one globe",
             text: "\(fmt(Double(atlas.places.count))) countries, regions and appellations, from Bordeaux to the Barossa, with what grows there, its climate, its rock and its land. It all lives on your phone and works offline.") {
            SpinningGlobe().frame(width: 230, height: 230)
        }
    }

    private var colors: some View {
        Page(title: "Gold for the classics",
             text: "Benchmark regions, in gold, are the classic places to learn first. Grey marks every other place. A deeper shade means the place is better known. The Atlas is not affiliated with any wine school.") {
            VStack(alignment: .leading, spacing: 14) {
                ramp(Palette.gold4, "Benchmark")
                ramp(Palette.grey4, "Other")
                HStack(spacing: 6) {
                    Text("Less known"); Image(systemName: "arrow.right"); Text("Better known")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.soft)
                .fixedSize()
            }
        }
    }

    private var moving: some View {
        Page(title: "Find your way", text: nil) {
            VStack(alignment: .leading, spacing: 16) {
                hint("hand.tap.fill", "Tap a place or its name", "It opens, and its page shows below. Tap it again to let go.")
                hint("hand.draw.fill", "Drag to turn the globe", "Turn anywhere, even off the place you have open, and tap what you find.")
                hint("arrow.up.left.and.arrow.down.right", "Pinch to zoom", "Pinch out far enough and you go up a level, from Tuscany to Italy.")
                hint("plus.magnifyingglass", "Double-tap to zoom in", "Right where you tap. Keep going and the place opens.")
                hint("rectangle.bottomhalf.inset.filled", "Pull the card up", "For the climate, the rock and soil, the land and the rules.")
            }
            .padding(.horizontal, 4)
        }
    }

    private var yours: some View {
        Page(title: "Make it yours", text: nil) {
            VStack(alignment: .leading, spacing: 16) {
                hint("star.fill", "Save places", "Add your own notes. They sync to your other devices through iCloud.")
                hint("location.fill", "Where am I", "The arrow at the top right finds the wine place you are standing in.")
                hint("square.grid.2x2.fill", "Place of the day", "Add the widget to your Home Screen for a new place each day.")
                hint("magnifyingglass", "Search", "Any country, region or appellation, by any of its names.")
            }
            .padding(.horizontal, 4)
        }
    }

    // ---- parts

    private func ramp(_ shades: [Color], _ name: String) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) { ForEach(1..<5, id: \.self) { shades[$0].frame(width: 36, height: 34) } }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.landEdge, lineWidth: 0.5))
            Text(name).font(.headline).foregroundStyle(Palette.ink).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private func hint(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.teal)
                .frame(width: 44, height: 44)
                .background(Palette.fill, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(text).font(.subheadline).foregroundStyle(Palette.soft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One onboarding page: a picture, a title and a few words.
private struct Page<Art: View>: View {
    let title: String
    let text: String?
    @ViewBuilder let art: Art

    private var heading: some View {
        Text(title).font(.largeTitle.weight(.heavy)).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }

    var body: some View {
        GeometryReader { g in
        ScrollView {
            VStack(spacing: 24) {
                // a picture page leads with the picture; a list page leads with its title
                if text == nil { heading }
                art.frame(maxWidth: .infinity).padding(.top, text == nil ? 0 : 12)
                if let text {
                    VStack(spacing: 10) {
                        heading
                        Text(text).font(.body).foregroundStyle(Palette.soft).multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, minHeight: g.size.height)   // centered on the page when it fits
        }
        .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// A small globe turning slowly, with the wine countries in gold.
struct SpinningGlobe: View {
    @Environment(Atlas.self) private var atlas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { t in
            Canvas { ctx, size in
                let R = min(size.width, size.height) / 2 * 0.96
                let lon = reduceMotion ? 10 : (t.date.timeIntervalSinceReferenceDate * 9).truncatingRemainder(dividingBy: 360)
                let P = Projector(Camera(lon: lon, lat: 22, R: R), center: CGPoint(x: size.width / 2, y: size.height / 2),
                                  diagonal: hypot(size.width, size.height))
                let disc = Path(ellipseIn: CGRect(x: P.cx - R, y: P.cy - R, width: 2 * R, height: 2 * R))
                ctx.fill(disc, with: .radialGradient(Gradient(colors: [Palette.oceanHigh, Palette.ocean]),
                                                      center: CGPoint(x: P.cx - 0.2 * R, y: P.cy - 0.3 * R), startRadius: 0, endRadius: 1.3 * R))
                ctx.stroke(P.graticule(), with: .color(Palette.graticule.opacity(0.6)), lineWidth: 0.6)
                let gold = atlas.benchmarkCountries
                var land = Path(), wine = Path()
                for c in atlas.countries {
                    for p in c.polys { if gold.contains(c.name) { P.add(p, to: &wine) } else { P.add(p, to: &land) } }
                }
                ctx.fill(land, with: .color(Palette.land))
                ctx.fill(wine, with: .color(Palette.gold4[3]))
                ctx.stroke(land, with: .color(Palette.landEdge), lineWidth: 0.4)
                ctx.stroke(wine, with: .color(Palette.gold4[4]), lineWidth: 0.5)
                ctx.stroke(disc, with: .color(Palette.landEdge), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}
