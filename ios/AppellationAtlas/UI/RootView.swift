import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var width
    @Environment(Globe.self) private var globe
    @Environment(Nav.self) private var nav

    var body: some View {
        Group {
            if width == .regular { WideLayout() } else { CompactLayout() }
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

/// iPhone: the globe fills the screen and the place sits in a sheet over it, as in Maps.
struct CompactLayout: View {
    @State private var detent: PresentationDetent = UserDefaults.standard.string(forKey: "sheet") == "large" ? .large : .height(Self.peek)
    static let peek: CGFloat = 230

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                // labels keep clear of the status bar and the buttons under it
                GlobeView(bottomInset: Self.peek, topInset: g.safeAreaInsets.top + 56)
                    .ignoresSafeArea()
                BackButton()
                    .padding(.leading, 16)
                    .padding(.top, 4)
                WhereAmIButton()
                    .padding(.trailing, 16)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .sheet(isPresented: .constant(true)) {
            PlaceSheet(detent: $detent)
                .presentationDetents([.height(Self.peek), .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationContentInteraction(.scrolls)
                .interactiveDismissDisabled()
        }
    }
}

/// iPad: places in a sidebar, the globe in the middle, the place's page beside it.
struct WideLayout: View {
    @State private var showInfo = true
    @Environment(Nav.self) private var nav
    @Environment(Atlas.self) private var atlas

    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            ZStack(alignment: .topLeading) {
                GlobeView(topInset: 64)
                    .ignoresSafeArea(edges: .bottom)
                BackButton().padding(16)
                WhereAmIButton().padding(16).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .navigationTitle(atlas.name(nav.place))
            .navigationBarTitleDisplayMode(.inline)
            .inspector(isPresented: $showInfo) {
                ScrollView { PlacePage(compact: false).padding(20) }
                    .inspectorColumnWidth(min: 340, ideal: 440, max: 600)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showInfo.toggle() } label: { Label("Place details", systemImage: "sidebar.trailing") }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onboarding()
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
                Label(to, systemImage: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Back to \(to)")
        }
    }
}
