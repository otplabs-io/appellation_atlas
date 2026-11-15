import CoreLocation
import simd
import Observation
import SwiftUI

/// Finds the wine place you are standing in, from your location and the boundaries in the app. Nothing leaves the
/// phone: the lookup runs on the shapes the app already carries.
@Observable
final class WhereAmI: NSObject, CLLocationManagerDelegate {
    enum State: Equatable { case idle, locating, found(String), outside, denied, failed }

    private(set) var state: State = .idle
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var atlas: Atlas?
    @ObservationIgnored private var done: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func locate(in atlas: Atlas, then go: @escaping (String) -> Void) {
        self.atlas = atlas
        done = go
        switch manager.authorizationStatus {
        case .denied, .restricted: state = .denied
        case .notDetermined: state = .locating; manager.requestWhenInUseAuthorization()
        default: state = .locating; manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let status = m.authorizationStatus
        Task { @MainActor in
            guard self.state == .locating else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.state = .denied
            default: break
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in self.found(lon: c.longitude, lat: c.latitude) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.state = .failed }
    }

    private func found(lon: Double, lat: Double) {
        guard let atlas else { return }
        if let id = WhereAmI.place(at: lon, lat, in: atlas) {
            state = .found(id)
            done?(id)
        } else {
            state = .outside
        }
    }

    func dismiss() { state = .idle }

    /// The smallest place on the map holding a point, going down view by view from the world.
    static func place(at lon: Double, _ lat: Double, in atlas: Atlas) -> String? { chain(at: lon, lat, in: atlas).last }

    /// The places holding a point, from its country down to the smallest.
    static func chain(at lon: Double, _ lat: Double, in atlas: Atlas) -> [String] {
        // Seen from straight above the point, a shape holds it when its drawing holds the middle of the canvas.
        let P = Projector(Camera(lon: lon, lat: lat, R: 1_000_000), center: .zero, diagonal: 0)
        func holds(_ polys: [Poly]) -> Bool {
            var path = Path()
            for p in polys where acos(max(-1, min(1, simd_dot(p.center, P.v)))) - p.radius < Double.pi / 2 { P.add(p, to: &path) }
            return path.contains(.zero, eoFill: false)
        }
        var out: [String] = []
        var viewID = "world"
        for _ in 0..<12 {
            guard let v = atlas.view(viewID) else { break }
            let hits = v.items.filter { holds($0.polys) }
            guard !hits.isEmpty else { break }
            // where shapes overlap (grand crus drawn by whole commune), the smallest one, unless they are the same shape
            let hit = hits.min { a, b in (a.polys.map(\.radius).max() ?? 0) < (b.polys.map(\.radius).max() ?? 0) }!
            let same = hits.filter { abs(($0.polys.map(\.radius).max() ?? 0) - (hit.polys.map(\.radius).max() ?? 0)) < 1e-9 }
            if same.count > 1 { if viewID == "world" { out.append(hit.id) }; break }
            out.append(hit.id)
            guard atlas.geo[hit.id]?.hasView == true, hit.id != viewID else { break }
            viewID = hit.id
        }
        return out
    }
}

/// The locate button on the globe, and what it found.
struct WhereAmIButton: View {
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav
    @State private var finder = WhereAmI()

    var body: some View {
        Button {
            finder.locate(in: atlas) { nav.go($0) }
        } label: {
            Group {
                if finder.state == .locating { ProgressView() } else { Image(systemName: "location.fill") }
            }
            .frame(width: 22, height: 22)
            .padding(11)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Where am I")
        .accessibilityHint("Shows the wine place you are standing in")
        .alert(title, isPresented: Binding(get: { message != nil }, set: { if !$0 { finder.dismiss() } })) {
            Button("OK", role: .cancel) { finder.dismiss() }
        } message: {
            Text(message ?? "")
        }
    }

    private var title: String {
        switch finder.state {
        case .outside: "Not in a wine place"
        case .denied: "Location is off"
        default: "Couldn't find you"
        }
    }

    private var message: String? {
        switch finder.state {
        case .outside: "You're not inside any place in the Atlas right now."
        case .denied: "To find the place you're standing in, allow Atlas to use your location in Settings."
        case .failed: "Your location isn't available right now. Try again in a moment."
        default: nil
        }
    }
}
