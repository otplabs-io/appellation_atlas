import SwiftUI

/// Design D: the map fills the screen and the panels float over it, as on the website.
struct RootView: View {
    @Environment(Globe.self) private var globe
    @Environment(Nav.self) private var nav

    var body: some View {
        GeometryReader { g in
            // panels each side of the map need room: an iPad on its side (an upright iPad gets the phone's layout)
            if g.size.width >= 1150 { WideLayout() } else { CompactLayout() }
        }
        .tint(Palette.teal)
        .sensoryFeedback(.selection, trigger: nav.place)
        .sensoryFeedback(.impact(weight: .light), trigger: globe.arrivals)
        .onAppear {
            globe.onPick = { [nav] id in nav.go(id) }
            if nav.place.hasPrefix("lookup:") {
                let v = nav.place.dropFirst(7).split(separator: ",").compactMap { Double($0) }
                nav.go(WhereAmI.place(at: v[0], v[1], in: globe.atlas) ?? "world")
            }
        }
        .onChange(of: nav.place) { _, p in Task { await globe.show(p) } }
    }
}

/// iPhone (and a narrow iPad window): the globe fills the screen. At home a card at the bottom holds search and the
/// filter; a place opens in a sheet over its map, as in Maps.
struct CompactLayout: View {
    @Environment(Nav.self) private var nav
    @State private var detent: PresentationDetent = Self.start
    static let homePeek: CGFloat = 272
    static let placePeek: CGFloat = 432
    private static var start: PresentationDetent {
        UserDefaults.standard.string(forKey: "sheet") == "large" ? .large : (UserDefaults.standard.string(forKey: "place") ?? "world") == "world" ? .height(homePeek) : .height(placePeek)
    }

    var body: some View {
        let home = nav.place == "world"
        GeometryReader { g in
            ZStack(alignment: .top) {
                GlobeView(bottomInset: home ? Self.homePeek - 40 : Self.placePeek - 60, topInset: g.safeAreaInsets.top + 60)
                    .ignoresSafeArea()
                if home {
                    // the globe fades into the ground behind the card
                    LinearGradient(colors: [Palette.ground.opacity(0), Palette.ground], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4))
                        .frame(height: 324).frame(maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea().allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Appellation Atlas").font(.display(15, .heavy, relativeTo: .headline)).foregroundStyle(Palette.ink)
                                .padding(.horizontal, 14).padding(.vertical, 10).glassPill(22)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            HStack(spacing: 8) { SettingsButton(); WhereAmIButton() }
                        }
                        MapKeyD()
                    }
                    .padding(.horizontal, 16).padding(.top, 10)
                } else {
                    HStack {
                        BackButton()
                        Spacer()
                        WhereAmIButton(size: 44)
                    }
                    .padding(.horizontal, 16).padding(.top, 10)
                }
            }
        }
        .background(Palette.ground)
        .sheet(isPresented: .constant(true)) {
            PlaceSheet(detent: $detent)
                .presentationDetents([.height(Self.homePeek), .height(Self.placePeek), .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(Self.placePeek)))
                .presentationContentInteraction(.scrolls)
                .presentationCornerRadius(30)
                .presentationBackground(Palette.paper.opacity(0.97))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .onChange(of: home) { _, h in withAnimation { detent = .height(h ? Self.homePeek : Self.placePeek) } }
    }
}

/// iPad: the search panel on the left, the place's panel on the right, the map between and under them.
struct WideLayout: View {
    @Environment(Nav.self) private var nav
    @Environment(Atlas.self) private var atlas
    @State private var sideHeight: CGFloat = 400
    static let side: CGFloat = 372
    static let panel: CGFloat = 420

    var body: some View {
        let home = nav.place == "world"
        GeometryReader { g in
            let left = 16 + Self.side, right = home ? 0 : Self.panel + 32
            ZStack(alignment: .topLeading) {
                GlobeView(topInset: 64, leadingInset: left, trailingInset: right)
                    .ignoresSafeArea()
                // the search panel: as tall as what it holds, and no taller than the screen
                ScrollView {
                    HomeCard(wide: true)
                        .padding(16)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sideHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: Self.side, height: min(sideHeight, g.size.height - 32))
                .glassPanel(28)
                .padding(16)
                // over the map: the way back, Where am I and the key
                BackButton().padding(.leading, left - 12).padding(.top, 16)
                WhereAmIButton(size: 44)
                    .padding(.top, 16).padding(.trailing, right + 16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                MapKeyD(row: true)
                    .fixedSize()
                    .frame(width: max(0, g.size.width - left - right), height: g.size.height - 16, alignment: .bottom)
                    .offset(x: left)
                if !home {
                    ScrollView { PlaceInfo(compact: false) }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(width: Self.panel)
                        .frame(maxHeight: .infinity)
                        .glassPanel(28)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: home)
        }
        .background(Palette.ground)
        .onboarding()
        .compareCover()
        .settingsCover()
    }
}

/// Out one level, labeled with where it goes.
struct BackButton: View {
    @Environment(Globe.self) private var globe
    @Environment(Atlas.self) private var atlas

    var body: some View {
        if let v = globe.view, v.id != "world" || globe.leaf != nil {
            let to = globe.leaf != nil ? v.name : v.parent == nil || v.parent == "world" ? "The world" : atlas.name(v.parent!)
            Button { globe.zoomOut() } label: {
                HStack(spacing: 6) {
                    BackChevron()
                    Text(to).font(.text(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Palette.ink).lineLimit(1)
                }
                .padding(.leading, 12).padding(.trailing, 16).frame(height: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassPill(22)
            .accessibilityLabel("Back to \(to)")
        }
    }
}
