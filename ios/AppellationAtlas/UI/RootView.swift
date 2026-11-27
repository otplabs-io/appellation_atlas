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

/// iPad: places in a sidebar, the globe in the middle, the place's page beside it. When the window is narrow (an iPad
/// held upright), the sidebar steps aside and the page beside the globe carries the places and the way back up, as on iPhone.
struct WideLayout: View {
    @State private var showInfo = true
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var searching = false
    // where the sidebar sits over the map, if it does, so the globe centers in the map left open beside it
    @State private var map: CGRect = .zero
    @State private var sidebarEdge: CGFloat = 0
    @State private var width: CGFloat = 0
    @Environment(Nav.self) private var nav
    @Environment(Atlas.self) private var atlas

    /// The sidebar shows beside the map only when the map keeps about 500 points between it and the page (320 + 440 + 500):
    /// a 13-inch iPad on its side. Narrower, the sidebar is hidden until asked for, and floats over the map when it is.
    static let narrowBelow: CGFloat = 1260

    /// How much of the map the sidebar covers. An edge not yet laid out, or one that would cover nearly all of the map,
    /// counts as none.
    private var sideCover: CGFloat {
        let c = sidebarEdge - map.minX
        return c > 0 && c < map.width * 0.9 ? c : 0
    }

    var body: some View {
        let narrow = width > 0 && width < Self.narrowBelow
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(searching: $searching)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxX } action: { sidebarEdge = $0 }
                .onDisappear { sidebarEdge = 0 }
        } detail: {
            ZStack(alignment: .topLeading) {
                GlobeView(topInset: 64, leadingInset: narrow ? 0 : sideCover)
                    .ignoresSafeArea(edges: .bottom)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { map = $0 }
                BackButton().padding(16)
                WhereAmIButton().padding(16).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .navigationTitle(atlas.name(nav.place))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showInfo.toggle() } label: { Label("Place details", systemImage: "sidebar.trailing") }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // on the whole split view, so the page is a full-height column beside the map, not a panel over a dimmed map
        .inspector(isPresented: $showInfo) {
            ScrollView { PlacePage(compact: narrow).padding(20) }
                .environment(\.startSearch, { columns = .all; searching = true })
                .inspectorColumnWidth(narrow ? 400 : 440)   // about an iPhone's width upright, so the page reads as it does there
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: narrow) {
            // the split view sets its own columns as it first appears, so this waits for it
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation { columns = narrow ? .detailOnly : .all }
        }
        .onChange(of: nav.place) { if narrow && columns != .detailOnly { withAnimation { columns = .detailOnly } } }
        .onboarding()
        .compareSheet()
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
