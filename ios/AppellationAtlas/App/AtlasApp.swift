import SwiftData
import SwiftUI

@main
struct AtlasApp: App {
    @State private var atlas: Atlas
    @State private var globe: Globe
    @State private var nav: Nav
    private let container = ModelContainer.atlas()

    init() {
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
                .onOpenURL { url in if url.scheme == "atlas", url.host() == "place" { nav.go(String(url.path().dropFirst())) } }
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
}
