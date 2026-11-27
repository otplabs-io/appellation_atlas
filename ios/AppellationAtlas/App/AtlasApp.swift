import SwiftData
import SwiftUI

@main
struct AtlasApp: App {
    @State private var atlas: Atlas
    @State private var globe: Globe
    @State private var nav: Nav
    private let container = ModelContainer.atlas()

    init() {
        DFont.register()
        let a = Atlas.load()
        _atlas = State(initialValue: a)
        let n = Nav()
        _nav = State(initialValue: n)
        _globe = State(initialValue: Globe(atlas: a, opening: n.place))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(atlas)
                .environment(globe)
                .environment(nav)
                .onOpenURL { url in nav.open(url) }
        }
        .modelContainer(container)
    }
}

/// The place being shown. The globe and the place pages both follow it, as the website follows its URL.
@Observable
final class Nav {
    /// A place to open at launch, for testing: run with the argument -place france/burgundy.
    var place = UserDefaults.standard.string(forKey: "place") ?? "world"

    init() {
        // For testing Where am I without moving: run with -lookup "lon,lat".
        if let q = UserDefaults.standard.string(forKey: "lookup") {
            let v = q.split(separator: ",").compactMap { Double($0) }
            if v.count == 2 { place = "lookup:\(v[0]),\(v[1])" }
        }
    }

    func go(_ id: String) { place = id.isEmpty ? "world" : id }

    /// Two places side by side, or the often compared pairs, on a page over the map (CompareCover).
    var compare: CompareRoute?
    /// Settings, on a page over the map (SettingsCover).
    var settings = false
    /// About the Atlas, in a sheet.
    var about = false

    /// atlas://place/<id>, atlas://compare/<a>/vs/<b> and atlas://pairs: the links the website's App Store banner hands over.
    func open(_ url: URL) {
        guard url.scheme == "atlas" else { return }
        let path = String(url.path().dropFirst())
        switch url.host() {
        case "place": go(path)
        case "compare":
            let parts = path.components(separatedBy: "/vs/")
            compare = CompareRoute(a: parts.first.flatMap { $0.isEmpty ? nil : $0 }, b: parts.count > 1 ? parts[1] : nil)
        case "pairs": compare = CompareRoute(pairs: true)
        default: break
        }
    }
}
