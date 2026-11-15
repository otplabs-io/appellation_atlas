import Foundation
import Observation

/// A place as places.json lists it.
struct Place: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let parent: String
    let score: Double
    let kind: String
    let country: String
    let also: [String]
    let benchmark: Bool
}

/// Where a place sits on the map, from geo/index.json.
struct GeoEntry: Sendable {
    let parent: String
    let hasView: Bool
    let source: String?
    let depth: Int
}

/// One place drawn on a map view.
struct MapItem: Identifiable {
    let id: String
    let name: String
    let polys: [Poly]
    let label: V2?
    /// How far the place reaches from its middle, as an angle: a measure of its size.
    var size: Double { polys.map(\.radius).max() ?? 0 }
}

/// A drawn view of one place and the places inside it, from geo/views/<id>.json.
struct MapView {
    let id: String
    let name: String
    let parent: String?
    let center: V2
    let half: V2
    let box: [Double]?
    let context: [[Poly]]
    let outline: [Poly]
    let items: [MapItem]
}

struct WorldCountry {
    let name: String
    let polys: [Poly]
    let label: V2?
}

/// Everything the Atlas knows, read from the data copied into the app from the website's public/ folder.
@Observable
final class Atlas {
    let places: [String: Place]
    let geo: [String: GeoEntry]
    let countries: [WorldCountry]
    /// True when the places carry Wikipedia scores.
    let scored: Bool
    let children: [String: [String]]
    /// The countries that are Benchmark regions, by name, as the world map names them.
    let benchmarkCountries: Set<String>
    @ObservationIgnored private let countryIDs: [String: String]
    @ObservationIgnored private let root: URL
    @ObservationIgnored private var viewCache: [String: MapView] = [:]
    @ObservationIgnored private var factCache: [String: JSON] = [:]
    @ObservationIgnored private let searchIndex: [(id: String, folded: String)]

    static func load() -> Atlas {
        guard let url = Bundle.main.url(forResource: "Atlas", withExtension: nil) else {
            fatalError("The app has no Atlas data. Build it with Xcode, which copies ../public into the app.")
        }
        return Atlas(root: url)
    }

    init(root: URL) {
        self.root = root
        var pl: [String: Place] = [:]
        for (id, x) in (JSON.readFast(root.appending(path: "places.json")) ?? .null)["places"].pairs {
            pl[id] = Place(id: id, name: x[0].string ?? id, parent: x[1].string ?? "world", score: x[2].double ?? -1,
                           kind: x[3].string ?? "", country: x[4].string ?? "", also: x[5].strings, benchmark: x[6].truthy)
        }
        places = pl
        var g: [String: GeoEntry] = [:]
        var kids: [String: [String]] = [:]
        for (id, x) in (JSON.readFast(root.appending(path: "geo/index.json")) ?? .null)["places"].pairs {
            let parent = x["parent"].string ?? "world"
            g[id] = GeoEntry(parent: parent, hasView: x["view"].truthy, source: x["source"].string, depth: x["depth"].int ?? 0)
            kids[parent, default: []].append(id)
        }
        geo = g
        children = kids
        countries = (JSON.readFast(root.appending(path: "geo/world.json")) ?? .null)["countries"].array.map {
            WorldCountry(name: $0["n"].string ?? "", polys: preparePolys($0["p"]), label: Atlas.point($0["l"]))
        }
        scored = pl.values.contains { $0.score >= 0 }
        countryIDs = Dictionary(pl.values.filter { $0.parent == "world" }.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
        benchmarkCountries = Set(pl.values.filter { $0.parent == "world" && $0.benchmark }.map(\.name))
        searchIndex = pl.values.map { p in (p.id, Atlas.fold(([p.name] + p.also).joined(separator: " "))) }
    }

    static func point(_ j: JSON) -> V2? {
        guard let x = j[0].double, let y = j[1].double else { return nil }
        return V2(x, y)
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
    }

    private func file(_ id: String) -> String { id.replacingOccurrences(of: "/", with: "__") + ".json" }

    func name(_ id: String) -> String { id == "world" ? "The world" : places[id]?.name ?? id }
    func score(_ id: String) -> Double { places[id]?.score ?? -1 }
    func isBenchmark(_ id: String) -> Bool { places[id]?.benchmark ?? false }
    func kind(_ id: String) -> String { places[id]?.kind ?? "" }

    func view(_ id: String) -> MapView? {
        if let v = viewCache[id] { return v }
        guard let j = JSON.readFast(root.appending(path: "geo/views/" + file(id))) else { return nil }
        let v = MapView(
            id: j["id"].string ?? id, name: j["name"].string ?? id, parent: j["parent"].string,
            center: Atlas.point(j["center"]) ?? V2(0, 0), half: Atlas.point(j["half"]) ?? V2(1, 1),
            box: j["box"].isNull ? nil : j["box"].doubles,
            context: j["ctx"].array.map { preparePolys($0["p"]) },
            outline: preparePolys(j["outline"]),
            items: j["items"].array.map {
                MapItem(id: $0["id"].string ?? "", name: $0["name"].string ?? "", polys: preparePolys($0["p"]), label: Atlas.point($0["l"]))
            }
            // biggest first, so a small place inside a big one (Brunello inside Toscana IGT) is drawn over it and tapped first
            .sorted { $0.size > $1.size })
        viewCache[id] = v
        return v
    }

    /// A place's shape: its own view's outline, or how the view it sits on draws it.
    func shape(_ id: String) -> [Poly] {
        if geo[id]?.hasView == true, let v = view(id), !v.outline.isEmpty { return v.outline }
        if let v = view(viewFor(id)), let it = v.items.first(where: { $0.id == id }) { return it.polys }
        if let p = places[id], let c = countries.first(where: { $0.name == p.name }) { return c.polys }
        return []
    }

    /// The place a country on the world map stands for.
    func country(named name: String) -> String? { countryIDs[name] }

    func facts(_ id: String) -> JSON? {
        if let f = factCache[id] { return f }
        guard let f = JSON.read(root.appending(path: "facts/" + file(id))) else { return nil }
        factCache[id] = f
        return f
    }

    /// The view a place is drawn on: its own, or its nearest ancestor's.
    func viewFor(_ p: String) -> String {
        var id = p
        while id != "world", let g = geo[id], !g.hasView { id = g.parent }
        if id != "world" && geo[id] == nil { return "world" }
        return id
    }

    /// The places from the world down to this one, not counting the world.
    func chain(_ id: String) -> [String] {
        var out: [String] = []
        var cur = id
        while cur != "world", let g = geo[cur] { out.insert(cur, at: 0); cur = g.parent }
        return out
    }

    /// The places on a view, best known first.
    func placesIn(_ viewID: String) -> [Place] {
        (children[viewID] ?? []).compactMap { places[$0] }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// The same matching as the website's search: every word folded, names that start with it first, then the best known.
    func search(_ text: String, limit: Int = 30) -> [Place] {
        let t = Atlas.fold(text.trimmingCharacters(in: .whitespaces))
        guard t.count >= 2 else { return [] }
        return searchIndex.filter { $0.folded.contains(t) }
            .compactMap { m in places[m.id].map { (p: $0, starts: m.folded.hasPrefix(t)) } }
            .sorted { $0.starts != $1.starts ? $0.starts : $0.p.score > $1.p.score }
            .prefix(limit).map(\.p)
    }

    // ---- shading: a place's shade, against the others on the same view (as the website does)

    func range(_ ids: [String]) -> (Double, Double) {
        let v = ids.map(score).filter { $0 >= 0 }
        return v.isEmpty ? (0, 0) : (v.min()!, v.max()!)
    }

    /// 0 for no score, 1 to 4 from least to best known.
    func tier(_ id: String, range r: (Double, Double)) -> Int {
        let s = score(id)
        if s < 0 { return 0 }
        let lo = min(r.0, r.1 - 20)
        let t = (s - lo) / (r.1 - lo)
        return t >= 0.85 ? 4 : t >= 0.6 ? 3 : t >= 0.35 ? 2 : 1
    }
}
