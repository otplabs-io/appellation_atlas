import Observation
import QuartzCore
import simd
import SwiftUI
import UIKit

/// How a label is set. Like a road map, each level of the hierarchy has its own type, so a glance tells a country
/// from a region from the places inside it.
struct LabelStyle: Equatable {
    enum Tone { case ink, soft, faint, water }
    enum Weight { case semibold, bold, heavy }
    let size: CGFloat
    let weight: Weight
    let kern: CGFloat
    let caps: Bool
    let tone: Tone
    var italic = false

    var uiFont: UIFont { .systemFont(ofSize: size, weight: weight == .heavy ? .heavy : weight == .bold ? .bold : .semibold) }
    var font: Font { .system(size: size, weight: weight == .heavy ? .heavy : weight == .bold ? .bold : .semibold) }
    func text(_ s: String) -> String { caps ? s.uppercased() : s }
    func width(_ s: String) -> CGFloat { (text(s) as NSString).size(withAttributes: [.font: uiFont, .kern: kern]).width }

    /// Countries around the view, for bearings.
    static let country = LabelStyle(size: 10, weight: .bold, kern: 1.2, caps: true, tone: .soft)
    /// The regions beside this one, Piedmont next to Tuscany: the level above, in quiet capitals.
    static let neighbour = LabelStyle(size: 10.5, weight: .semibold, kern: 1, caps: true, tone: .soft)
    /// A place whose own places show inside it: named like a state, spaced and faint, so its parts read over it.
    static let container = LabelStyle(size: 12.5, weight: .heavy, kern: 1.6, caps: true, tone: .faint)
    /// Rivers and lakes, in italic water blue, like a road map's.
    static let water = LabelStyle(size: 11, weight: .semibold, kern: 0, caps: false, tone: .water, italic: true)
    /// Towns, for bearings: quieter than places and rivers.
    static let town = LabelStyle(size: 11, weight: .semibold, kern: 0, caps: false, tone: .soft)
    /// The places inside a place, shown as you zoom toward it: the level below, small and grey.
    static let inside = LabelStyle(size: 11, weight: .semibold, kern: 0, caps: false, tone: .soft)
    /// This view's own places, bigger as they are better known.
    static func place(tier: Int) -> LabelStyle {
        LabelStyle(size: [12, 12, 13, 14, 15][max(0, min(4, tier))], weight: .bold, kern: 0, caps: false, tone: .ink)
    }
}

/// A label placed on the globe.
struct MapLabel: Identifiable {
    enum Kind { case place, country, neighbour, inside, water, town }
    let id: String
    let text: String
    let point: CGPoint
    let anchor: UnitPoint
    let kind: Kind
    let style: LabelStyle
    /// Where the words sit on screen, so a tap on them picks the place they name.
    let box: CGRect
    /// Degrees the words turn, to run along a river.
    var angle: Double = 0
    /// A town's own spot, drawn as a small dot beside its name.
    var dot: CGPoint? = nil
}

/// A dot for a place too small to tap.
struct MapDot: Identifiable {
    let id: String
    let point: CGPoint
}

/// Runs a step on every screen refresh until it returns false.
final class Ticker: NSObject {
    private var link: CADisplayLink?
    private var step: ((CFTimeInterval) -> Bool)?

    func run(_ step: @escaping (CFTimeInterval) -> Bool) {
        stop()
        self.step = step
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        if step?(l.targetTimestamp) == false { stop() }
    }

    func stop() { link?.invalidate(); link = nil; step = nil }
}

/// The globe: where it is turned, what it shows, and how it moves. The behavior follows web/atlas.js.
@Observable
final class Globe {
    let atlas: Atlas
    /// Where the globe opens, and how much of it to fit (the same as the website).
    static let start = (lon: -33.56, lat: 18.13, ex: 0.83775, ey: 0.9314)

    var size: CGSize = .zero
    /// Space covered at the bottom (the place sheet on iPhone), so the globe centers in what is left.
    var bottomInset: CGFloat = 0
    /// Space at the top kept clear of labels: the status bar and the buttons under it.
    var topInset: CGFloat = 0
    /// Space covered at the sides (the iPad's sidebar and place panel), so the globe centers between them.
    var leftInset: CGFloat = 0
    var rightInset: CGFloat = 0
    /// The width of the map left open between the sides.
    var openWidth: CGFloat { max(1, size.width - leftInset - rightInset) }
    var cam = Camera(lon: Globe.start.lon, lat: Globe.start.lat, R: 120)
    private(set) var view: MapView?
    private(set) var parent: MapView?
    private(set) var leaf: String?
    /// The view flying out, faded as the new one comes in.
    private(set) var outgoing: (view: MapView, parent: MapView?)?
    private(set) var fadeIn: Double = 1
    private(set) var worldOpacity: Double = 1
    private(set) var appear: Double = 1
    private(set) var labels: [MapLabel] = []
    private(set) var dots: [MapDot] = []
    /// The places big enough on screen to show what is inside them, with the views that hold their parts.
    private(set) var previews: [MapView] = []
    private(set) var range: (Double, Double) = (0, 0)
    private(set) var busy = false
    /// Changes each time the globe settles into a new place, for a light haptic tap.
    private(set) var arrivals = 0
    /// Called when the globe picks a place: a tap, or zooming far enough into one.
    @ObservationIgnored var onPick: (String) -> Void = { _ in }
    @ObservationIgnored private let ticker = Ticker()
    @ObservationIgnored private var want = "world"
    @ObservationIgnored private var going = false
    /// Set when the finger picks a place on the map: the globe then changes level where it is, without moving.
    @ObservationIgnored private var keepFor: String?
    @ObservationIgnored private var gesture: (cam: Camera, anchor: CGPoint, geo: V2?)?
    @ObservationIgnored private var drag = CGSize.zero
    @ObservationIgnored private var pinch = 1.0
    @ObservationIgnored var reduceMotion = false

    init(atlas: Atlas, opening: String = "world") {
        self.atlas = atlas
        want = opening
    }

    // ---- layout

    var center: CGPoint { CGPoint(x: leftInset + openWidth / 2, y: (size.height - bottomInset) / 2) }
    var fitSize: CGSize { CGSize(width: max(200, openWidth), height: max(200, size.height - bottomInset)) }
    var projector: Projector { projector(cam) }
    func projector(_ c: Camera) -> Projector { Projector(c, center: center, diagonal: hypot(size.width, size.height)) }

    func camFor(_ v: MapView) -> Camera {
        let W = fitSize.width, H = fitSize.height
        if v.id == "world" {
            let s = Globe.start
            return Camera(lon: s.lon, lat: s.lat, R: min(W / 2 / s.ex, H / 2 / s.ey) * 0.94)
        }
        return Camera(lon: v.center.x, lat: v.center.y, R: min(W / 2 / v.half.x, H / 2 / v.half.y) * 0.9)
    }

    @ObservationIgnored private var oldBase: Double?

    func resized(_ s: CGSize, bottom: CGFloat, left: CGFloat = 0, right: CGFloat = 0) {
        guard s.width > 0, s.height > 0 else { return }
        if oldBase == nil, let v = view { oldBase = camFor(v).R }
        let first = size == .zero
        size = s
        bottomInset = bottom
        leftInset = max(0, left); rightInset = max(0, right)
        if first { Task { await show(want) } }
        else if let v = view, !busy {
            // keep where the globe is turned and how far in it is, only fitted to the new space
            let old = oldBase ?? camFor(v).R
            cam.R *= camFor(v).R / old
            relabel()
        }
        oldBase = view.map { camFor($0).R }
    }

    // ---- what is drawn

    var showsWorld: Bool { worldOpacity > 0.001 }

    /// The world layer is needed when the view's box does not cover the screen.
    func needsWorld(_ c: Camera, _ v: MapView) -> Bool {
        guard let box = v.box, box.count == 4 else { return true }
        let P = projector(c)
        let W = size.width, H = size.height
        for (X, Y) in [(0.0, 0.0), (W, 0), (0, H), (W, H), (W / 2, 0), (W / 2, H), (0, H / 2), (W, H / 2)] {
            guard let q = P.geo(at: CGPoint(x: X, y: Y)) else { continue }
            var lo = q.x
            while lo < box[0] - 180 { lo += 360 }
            while lo > box[0] + 180 { lo -= 360 }
            if lo < box[0] || lo > box[2] || q.y < box[1] || q.y > box[3] { return true }
        }
        return false
    }

    func shade(_ id: String) -> Color {
        Palette.tone(atlas.tone(id))
    }

    // ---- moving between places

    private func restyle() {
        guard let v = view else { return }
        range = atlas.range(v.items.map(\.id))
    }

    /// Shows a place: flies to its view, or marks it on the view it shares with its siblings.
    func show(_ p: String) async {
        want = p
        guard size != .zero, !going else { return }
        going = true
        defer { going = false }
        while true {
            let target = want
            let keep = keepFor == target
            keepFor = nil
            guard let v = atlas.view(atlas.viewFor(target)) ?? atlas.view("world") else { break }
            let par = v.parent.flatMap { atlas.view($0) }
            let hadLeaf = leaf != nil
            leaf = target != v.id && target != "world" ? target : nil
            if view == nil {
                view = v; parent = par
                let b = camFor(v)
                worldOpacity = needsWorld(b, v) ? 1 : 0
                restyle()
                if v.id == "world" && !reduceMotion { await intro(b) } else { cam = b }
            } else if view!.id != v.id {
                // picked on the map, close enough already: stay put and just change level
                await fly(v, par, to: keep && cam.R >= camFor(v).R * Globe.openAt ? cam : nil)
            } else if cam.R > camFor(v).R * 1.03 && leaf == nil && !hadLeaf {   // back to the view from a link, not just a place let go
                await glide(camFor(v))
            }
            if want == target { break }
        }
        restyle()
        if let lf = leaf, let it = view?.items.first(where: { $0.id == lf }) { await focus(it) }
        relabel()
        oldBase = view.map { camFor($0).R }
    }

    /// Brings a picked place into sight when it is out of sight, as from search: centered, and big enough to see
    /// when it is small. A place already in sight, as one tapped on the map, stays where it is.
    private func focus(_ it: MapItem) async {
        guard !it.polys.isEmpty else { return }
        let bb = projector.path(it.polys).boundingRect
        let open = CGRect(x: leftInset, y: topInset, width: openWidth, height: max(1, size.height - bottomInset - topInset))
        if !bb.isNull, !bb.isEmpty, bb.intersects(open) { return }
        let s = bb.isNull ? 1 : max(bb.width, bb.height)
        let want = min(fitSize.width, fitSize.height - topInset) * 0.45
        let R = clampR(cam.R * min(8, max(1, want / max(1, s))))   // in, never out
        var sum = V3.zero
        for p in it.polys { sum += p.center }
        guard simd_length(sum) > 0 else { return }
        let c = sum / simd_length(sum)
        await glide(Camera(lon: atan2(c.y, c.x) * 180 / .pi, lat: asin(max(-1, min(1, c.z))) * 180 / .pi, R: R))
    }

    private static func ease(_ k: Double) -> Double { k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2 }

    /// Runs an animation from 0 to 1 over a duration, calling step on each frame.
    private func animate(_ ms: Double, _ step: @escaping (Double) -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            var t0: CFTimeInterval?
            ticker.run { t in
                if t0 == nil { t0 = t }
                let k = min(1, (t - t0!) * 1000 / ms)
                step(k)
                if k >= 1 { done.resume(); return false }
                return true
            }
        }
    }

    private func lerp(_ a: Camera, _ b: Camera, _ e: Double, _ dl: Double, zoom: Double? = nil) -> Camera {
        let z = zoom ?? e
        return Camera(lon: a.lon + dl * e, lat: a.lat + (b.lat - a.lat) * e, R: exp(log(a.R) + (log(b.R) - log(a.R)) * z))
    }

    private func shortest(_ a: Double, _ b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    private func fly(_ v: MapView, _ par: MapView?, to fixed: Camera? = nil) async {
        let old = view.map { ($0, parent) }
        let a = cam, b = fixed ?? camFor(v), base = camFor(v).R
        view = v; parent = par; outgoing = old; fadeIn = 0
        restyle(); labels = []; dots = []; previews = []
        let wa = worldOpacity, wb: Double = needsWorld(b, v) ? 1 : 0
        worldOpacity = max(wa, 0.001)
        let dl = shortest(a.lon, b.lon)
        let zr = abs(log(b.R / a.R))
        let ms = reduceMotion || fixed != nil ? 350 : min(1900, 900 + zr * 160)
        busy = true
        // turn and zoom together, on one easing; between two places far apart and both close up, rise toward the whole globe in the middle of the flight
        let rad = Double.pi / 180, R0 = min(fitSize.width, fitSize.height) / 2 * 0.9, lo = min(a.R, b.R)
        let ang = acos(min(1, sin(a.lat * rad) * sin(b.lat * rad) + cos(a.lat * rad) * cos(b.lat * rad) * cos(dl * rad))) / rad
        let dip = lo > R0 * 1.5 && ang > 15 ? log(lo / R0) * min(1, ang / 60) : 0
        await animate(ms) { [self] k in
            let e = Globe.ease(k)
            var c = lerp(a, b, e, dl, zoom: e)
            c.R *= exp(-dip * sin(Double.pi * k))
            cam = reduceMotion ? b : c
            fadeIn = min(1, max(0, (e - 0.15) / 0.6))
            worldOpacity = max(0.001, wa + (wb - wa) * e)
        }
        outgoing = nil; cam = refit(b, base); worldOpacity = wb; fadeIn = 1; busy = false
        arrivals += 1
    }

    private func intro(_ b: Camera) async {
        let a = Camera(lon: b.lon + 300, lat: b.lat - 20, R: b.R * 0.05), base = baseR
        busy = true; appear = 0
        await animate(3600) { [self] k in
            let z = Globe.ease(min(1, k * 1.15)), sp = 1 - pow(1 - k, 3)
            cam = Camera(lon: a.lon + (b.lon - a.lon) * sp, lat: a.lat + (b.lat - a.lat) * sp, R: exp(log(a.R) + (log(b.R) - log(a.R)) * z))
            appear = min(1, k * 5)
        }
        cam = refit(b, base); appear = 1; busy = false
    }

    /// A flight's end, fitted to the space as it is now: the panels beside the map can settle while the globe moves.
    private func refit(_ b: Camera, _ base: Double) -> Camera {
        var c = b
        if base > 0 { c.R *= baseR / base }
        return c
    }

    private func glide(_ b: Camera, ms: Double = 500, ease: Bool = true) async {
        let a = cam, dl = shortest(a.lon, b.lon), base = baseR
        busy = true; labels = []; dots = []
        await animate(reduceMotion ? 1 : ms) { [self] k in
            let e = ease ? Globe.ease(k) : 1 - pow(1 - k, 3)
            cam = lerp(a, b, e, dl)
            if let v = view, v.id != "world" { worldOpacity = needsWorld(cam, v) ? 1 : 0 }
        }
        cam = refit(b, base); busy = false
        relabel()
    }

    // ---- gestures

    private var baseR: Double { view.map { camFor($0).R } ?? cam.R }
    /// A tapped place keeps the camera once the globe is this close to its own map; pinching out below `leaveAt` of the
    /// view's own size goes up a level. The gap between them keeps a level from flipping back and forth.
    static let openAt = 0.85, leaveAt = 0.7
    var zoomed: Bool { cam.R > baseR * 1.03 }

    /// How far in or out the globe may go. A gesture that starts beyond the limits (just after changing level) can
    /// go back toward them but never jumps to them.
    private func clampR(_ R: Double, from r0: Double? = nil) -> Double {
        let b = baseR, w = view?.id == "world"
        let hi = max(b * (w ? 14 : 8), r0 ?? 0), lo = min(b * (w ? 0.8 : 0.4), r0 ?? .infinity)
        return min(hi, max(lo, R))
    }

    /// Turns the globe so a point keeps the same place under the finger, at a new size.
    private func look(_ geo: V2?, at s: CGPoint, R: Double, from c0: Camera) {
        var c: V2?
        if let g = geo {
            let P = projector(Camera(lon: g.x, lat: g.y, R: R))
            c = P.unproject(x: (P.cx - s.x) / R, y: (s.y - P.cy) / R)
        }
        let to = c ?? V2(c0.lon, c0.lat)
        cam = Camera(lon: to.x, lat: max(-80, min(80, to.y)), R: R)
        if let v = view, v.id != "world" { worldOpacity = needsWorld(cam, v) ? 1 : 0 }
    }

    private func beginGesture(at anchor: CGPoint) {
        if gesture == nil {
            ticker.stop(); busy = false
            gesture = (cam, anchor, projector.geo(at: anchor))
            drag = .zero; pinch = 1
            labels = []; dots = []
        }
    }

    private func applyGesture() {
        guard let g = gesture else { return }
        let s = CGPoint(x: g.anchor.x + drag.width, y: g.anchor.y + drag.height)
        look(g.geo, at: s, R: clampR(g.cam.R * pinch, from: g.cam.R), from: g.cam)
    }

    func dragChanged(start: CGPoint, translation: CGSize) {
        guard !going else { return }
        beginGesture(at: start)
        drag = translation
        applyGesture()
    }

    func pinchChanged(scale: Double, anchor: CGPoint) {
        guard !going else { return }
        beginGesture(at: anchor)
        pinch = scale
        applyGesture()
    }

    /// How fast the finger was moving when the drag let go, for the flick that follows.
    @ObservationIgnored private var flick = CGSize.zero

    func dragEnded(velocity: CGSize) { flick = velocity }

    /// Every finger is off the glass. Called once both gestures are over, whether they ended or were cancelled, so a
    /// pinch always settles (and changes level) and the next gesture always starts fresh.
    func touchesEnded() {
        let v = flick
        flick = .zero
        endGesture(velocity: v)
    }

    /// Lets a flick carry on and slow down, then settles the globe the way the website does.
    private func endGesture(velocity: CGSize) {
        guard let g = gesture else { return }
        gesture = nil
        let speed = hypot(velocity.width, velocity.height)
        if speed > 250, !reduceMotion {
            let carry = 0.22
            let s = CGPoint(x: g.anchor.x + drag.width + velocity.width * carry, y: g.anchor.y + drag.height + velocity.height * carry)
            let from = cam
            look(g.geo, at: s, R: cam.R, from: g.cam)
            let to = cam
            cam = from
            Task {
                await glide(to, ms: min(900, 300 + speed * 0.25), ease: false)
                await settle()
            }
        } else {
            Task { await settle() }
        }
    }

    private func settle() async {
        guard !busy, let v = view else { return }
        let b = camFor(v)
        if v.id != "world" && cam.R < b.R * Globe.leaveAt {   // pinched out: up a level, where the globe is
            pickInPlace(v.parent ?? "world"); return
        }
        relabel()   // the globe stays where the finger left it, at every level: a place opens only when tapped
    }

    /// Picks a place from the map itself, so the globe changes level where it is rather than flying.
    private func pickInPlace(_ id: String) {
        keepFor = id
        onPick(id)
    }

    /// Twice as close, keeping the tapped spot under the finger.
    func zoomIn(at p: CGPoint) {
        guard !busy, !going, gesture == nil else { return }
        let geo = projector.geo(at: p)
        let from = cam
        look(geo, at: p, R: clampR(cam.R * 2.2, from: cam.R), from: cam)
        let to = cam
        cam = from
        Task {
            await glide(to, ms: 380)
            await settle()
        }
    }

    /// A tap: picks what is under the finger, or lets go of the place already picked.
    func tap(at p: CGPoint) {
        guard let id = hit(p) else { return }
        pickInPlace(id == leaf ? (view?.id ?? "world") : id)
    }

    /// Out one level: from a place to its view, or from a view to its parent.
    func zoomOut() {
        guard !busy, let v = view else { return }
        if leaf != nil { onPick(v.id); return }
        if v.id == "world" { if zoomed { Task { await glide(camFor(v)) } }; return }
        onPick(v.parent ?? "world")
    }

    /// What a tap lands on. The words of a label first, since they name their place. Then the smallest shape under the
    /// finger, then a dot or a label point within a fingertip. Off this view (turned over to France from Tuscany), the
    /// place there at the same level as this one.
    func hit(_ p: CGPoint) -> String? {
        guard let v = view, !busy else { return nil }
        let P = projector
        if let l = labels.first(where: { $0.kind != .water && $0.kind != .town && $0.box.insetBy(dx: -6, dy: -6).contains(p) }) {
            if l.kind != .country { return l.id }
            if let c = atlas.country(named: String(l.id.dropFirst(2))) { return c }
        }
        for it in v.items.reversed() where P.path(it.polys).contains(p, eoFill: false) { return it.id }
        var best: String?, bd = 24.0
        for d in dots { let k = hypot(d.point.x - p.x, d.point.y - p.y); if k < bd { bd = k; best = d.id } }
        if best != nil { return best }
        for it in v.items {
            guard let l = it.label, let s = P.screen(lon: l.x, lat: l.y) else { continue }
            let k = hypot(s.x - p.x, s.y - p.y)
            if k < bd { bd = k; best = it.id }
        }
        if best != nil { return best }
        guard let g = P.geo(at: p) else { return nil }
        let chain = WhereAmI.chain(at: g.x, g.y, in: atlas)
        if chain.isEmpty { return nil }
        let level = max(1, atlas.chain(v.id).count)   // Tuscany is level 2: pick a level-2 place, such as Burgundy
        let pick = chain[min(level, chain.count) - 1]
        return pick == v.id ? nil : pick
    }

    // ---- labels, placed so none overlap, best known first

    func relabel() {
        guard let v = view, size != .zero else { labels = []; dots = []; previews = []; return }
        let P = projector, W = size.width, H = size.height, L = leftInset, Rt = W - rightInset, openW = openWidth
        var placed: [CGRect] = []
        var outL: [MapLabel] = [], outD: [MapDot] = []
        func free(_ b: CGRect) -> Bool {
            if b.minX < L + 2 || b.maxX > Rt - 2 || b.minY < max(2, topInset) || b.maxY > H - 2 - bottomInset { return false }
            return !placed.contains { b.insetBy(dx: 2, dy: 2).intersects($0) }
        }
        /// Tries spots around a point, in order, and keeps the first that is free (or the last, when forced).
        @discardableResult
        func put(_ id: String, _ name: String, at tries: [(CGFloat, CGFloat, CGFloat)], kind: MapLabel.Kind, style st: LabelStyle, force: Bool = false) -> Bool {
            let w = st.width(name) + 8, h = st.size * 1.25
            for (k, t) in tries.enumerated() {
                let box = CGRect(x: t.0 - w * t.2, y: t.1 - h, width: w, height: h * 1.25)
                if !(force && k == tries.count - 1) && !free(box) { continue }
                placed.append(box)
                outL.append(MapLabel(id: id, text: st.text(name), point: CGPoint(x: t.0, y: t.1), anchor: UnitPoint(x: t.2, y: 0.8), kind: kind, style: st, box: box))
                return true
            }
            return false
        }
        func around(_ x: CGFloat, _ y: CGFloat, _ fs: CGFloat) -> [(CGFloat, CGFloat, CGFloat)] {
            let h = fs * 1.25
            return [(x, y + fs * 0.35, 0.5), (x, y - 8, 0.5), (x, y + h + 4, 0.5), (x + 12, y + fs * 0.35, 0), (x - 12, y + fs * 0.35, 1),
                    (x + 8, y - 8, 0), (x - 8, y - 8, 1), (x + 8, y + h + 4, 0), (x - 8, y + h + 4, 1)]
        }

        // Like a road map, a name waits until its place is big enough on screen for how well known it is: the classics
        // straight away, the lesser places as you zoom toward them. A Benchmark place counts one step better known.
        let shownH = max(1, H - topInset - bottomInset)
        func needs(_ id: String, _ r: (Double, Double)) -> CGFloat {
            let t = atlas.tier(id, range: r) + (atlas.isBenchmark(id) ? 1 : 0)
            return [150, 110, 70, 36, 0][min(4, t)]
        }
        // and the screen holds only so many names: about one for each 16,000 square points of open map
        var budget = max(6, Int(openW * shownH / 16_000))

        let live = v.items.filter { !$0.polys.isEmpty }.sorted {
            let a = leaf == $0.id ? 1 : 0, b = leaf == $1.id ? 1 : 0
            return a != b ? a > b : atlas.score($0.id) > atlas.score($1.id)
        }
        var points: [String: CGPoint] = [:], boxes: [String: CGRect] = [:]
        var dotted: Set<String> = []
        for it in live {
            guard let l = it.label, let s = P.screen(lon: l.x, lat: l.y) else { continue }
            points[it.id] = s
            let bb = P.path(it.polys).boundingRect
            boxes[it.id] = bb
            if v.id != "world" && (bb.isNull || max(bb.width, bb.height) < 16) {
                dotted.insert(it.id)
                outD.append(MapDot(id: it.id, point: s))
                placed.append(CGRect(x: s.x - 5, y: s.y - 5, width: 10, height: 10))
            }
        }

        // Zoomed in, a place with its own map that spans a good part of the screen shows the places inside it.
        let zoomedIn = cam.R > baseR * 1.25
        var open: [MapView] = []
        if zoomedIn {
            for it in live where it.id != leaf && atlas.geo[it.id]?.hasView == true {
                guard let bb = boxes[it.id], !bb.isNull, max(bb.width, bb.height) >= min(openW, shownH) * 0.5,
                      bb.intersects(CGRect(x: L, y: topInset, width: openW, height: H - topInset - bottomInset)),
                      let cv = atlas.view(it.id), !cv.items.isEmpty else { continue }
                open.append(cv)
            }
        }
        let openIDs = Set(open.map(\.id))

        // 1. this view's places, best known first; a place showing its parts is named like a state
        let range = self.range
        for (n, it) in live.enumerated() {
            guard let s = points[it.id] else { continue }
            let picked = leaf == it.id || n == 0
            if !picked {
                guard budget > 0, let bb = boxes[it.id], max(bb.width, bb.height) >= needs(it.id, range) else { continue }
            }
            let st = openIDs.contains(it.id) ? LabelStyle.container : LabelStyle.place(tier: atlas.tier(it.id, range: range))
            let fs = st.size, h = fs * 1.25
            let x = s.x, y = s.y
            let tries: [(CGFloat, CGFloat, CGFloat)]
            if leaf == it.id && !dotted.contains(it.id), let bb = boxes[it.id] {   // the picked place's name above its shape
                tries = [(bb.midX, bb.minY - 8, 0.5), (bb.midX, bb.maxY + h + 8, 0.5), (x, y + fs * 0.35, 0.5)]
            } else if dotted.contains(it.id) {
                tries = [(x + 10, y + 4, 0), (x - 10, y + 4, 1), (x, y - 11, 0.5), (x, y + h + 8, 0.5)]
            } else {
                tries = around(x, y, fs) + (n == 0 ? [(x, y + fs * 0.35, 0.5)] : [])
            }
            if put(it.id, it.name, at: tries, kind: .place, style: st, force: n == 0) { budget -= 1 }
        }

        // 2. inside the open places, their own places, half a dozen at most each, best known first, by the same rule
        for cv in open {
            let r = atlas.range(cv.items.map(\.id))
            let inner = cv.items.filter { $0.label != nil }.sorted { atlas.score($0.id) > atlas.score($1.id) }.prefix(6)
            for it in inner {
                guard budget > 0, let l = it.label, let s = P.screen(lon: l.x, lat: l.y) else { continue }
                let bb = P.path(it.polys).boundingRect
                guard !bb.isNull, max(bb.width, bb.height) >= needs(it.id, r) + 20 else { continue }
                if put(it.id, it.name, at: around(s.x, s.y, LabelStyle.inside.size), kind: .inside, style: .inside) { budget -= 1 }
            }
        }

        // 3. the regions beside this one (those with maps of their own), named in whatever part of them is on screen
        if let par = parent {
            let shownArea = CGRect(x: L, y: topInset, width: openW, height: H - topInset - bottomInset)
            let st = LabelStyle.neighbour
            let near = par.items.filter { $0.id != v.id && atlas.geo[$0.id]?.hasView == true }.sorted { atlas.score($0.id) > atlas.score($1.id) }
            // a neighbour that overlaps this place (Sonoma Coast around Russian River Valley) is named only outside it
            let ownShape = v.outline.isEmpty ? nil : P.path(v.outline)
            var shownNear = 0
            for it in near where shownNear < 4 {
                let shape = P.path(it.polys)
                let seen = shape.boundingRect.intersection(shownArea)
                guard !seen.isNull, seen.width > st.width(it.name) + 16, seen.height > 24 else { continue }
                // its own label point when on screen, else spots across the part in view; only spots inside the shape
                var spots: [CGPoint] = []
                if let l = it.label, let s = P.screen(lon: l.x, lat: l.y), seen.insetBy(dx: 20, dy: 10).contains(s) { spots.append(s) }
                for fy in [0.5, 0.3, 0.7, 0.15, 0.85] { for fx in [0.5, 0.3, 0.7] {
                    spots.append(CGPoint(x: seen.minX + seen.width * fx, y: seen.minY + seen.height * fy))
                } }
                let inside = spots.filter { shape.contains($0, eoFill: false) && !(ownShape?.contains($0, eoFill: false) ?? false) }
                    .map { ($0.x, $0.y + 4, CGFloat(0.5)) }
                if !inside.isEmpty, put(it.id, it.name, at: inside, kind: .neighbour, style: st) { shownNear += 1 }
            }
        }

        // 4. river and lake names, after the places': along the stretch nearest the middle of the map, or across the lake (labels in web/atlas.js)
        let mid = CGPoint(x: L + openW / 2, y: topInset + shownH / 2)
        for w in v.water {
            var tries: [(CGPoint, Double)] = []
            if w.lake {
                if w.anchor.count >= 2, let s = P.screen(lon: w.anchor[0], lat: w.anchor[1]) { tries.append((s, 0)) }
            } else {
                for l in w.lines {
                    let pts: [CGPoint?] = l.points.map { let q = P.project($0); return q.z < 0 ? nil : P.screen(q.x, q.y) }
                    var last: CGPoint? = nil
                    for i in pts.indices {
                        guard let p = pts[i], p.x >= L + 30, p.x <= Rt - 30, p.y >= topInset + 16, p.y <= H - bottomInset - 16 else { continue }
                        if let q = last, hypot(p.x - q.x, p.y - q.y) < 24 { continue }
                        func near(_ k: Int) -> Bool { guard let q = pts[k] else { return false }; return hypot(q.x - p.x, q.y - p.y) < 22 }
                        var a = i, b = i   // the river's heading over about 40 points
                        while a > 0 && near(a - 1) { a -= 1 }
                        while b < pts.count - 1 && near(b + 1) { b += 1 }
                        if a == i && i > 0 && pts[i - 1] != nil { a = i - 1 }
                        if b == i && i < pts.count - 1 && pts[i + 1] != nil { b = i + 1 }
                        guard a != b, let pa = pts[a], let pb = pts[b] else { continue }
                        var ang = atan2(pb.y - pa.y, pb.x - pa.x) * 180 / .pi
                        if ang > 90 { ang -= 180 }
                        if ang < -90 { ang += 180 }
                        tries.append((p, ang)); last = p
                    }
                }
            }
            tries.sort { hypot($0.0.x - mid.x, $0.0.y - mid.y) < hypot($1.0.x - mid.x, $1.0.y - mid.y) }
            let st = LabelStyle.water, wd = st.width(w.name), h = st.size * 1.2
            for (s, ang) in tries.prefix(60) {
                let a = ang * .pi / 180
                let hw = (abs(cos(a)) * wd + abs(sin(a)) * h) / 2, hh = (abs(sin(a)) * wd + abs(cos(a)) * h) / 2
                let box = CGRect(x: s.x - hw, y: s.y - hh, width: 2 * hw, height: 2 * hh)
                guard free(box) else { continue }
                placed.append(box)
                outL.append(MapLabel(id: "w:" + w.name, text: w.name, point: s, anchor: UnitPoint(x: 0.5, y: 0.5), kind: .water, style: st, box: box, angle: ang))
                break
            }
        }

        // 4b. a few towns, for bearings: a dot and the name beside it, wherever there is room (web/atlas.js)
        for t in v.cities {
            guard let s = P.screen(lon: t.lon, lat: t.lat), s.x >= L + 8, s.x <= Rt - 8, s.y >= topInset + 8, s.y <= H - bottomInset - 8 else { continue }
            let st = LabelStyle.town, w = st.width(t.name), h: CGFloat = 12
            let dotBox = CGRect(x: s.x - 3, y: s.y - 3, width: 6, height: 6)
            guard free(dotBox) else { continue }
            for (X, Y, a) in [(s.x + 6, s.y + 4, CGFloat(0)), (s.x - 6, s.y + 4, 1), (s.x, s.y - 7, 0.5), (s.x, s.y + 15, 0.5)] {
                let x0 = X - w * a
                let box = CGRect(x: x0 - 2, y: Y - h + 2, width: w + 4, height: h + 1)
                guard free(box) else { continue }
                placed.append(box); placed.append(dotBox)
                outL.append(MapLabel(id: "t:" + t.name, text: t.name, point: CGPoint(x: X, y: Y), anchor: UnitPoint(x: a, y: 0.8), kind: .town, style: st, box: box, dot: s))
                break
            }
        }

        // 5. the countries around, for bearings
        if v.id != "world" {
            let own = atlas.places[String(v.id.split(separator: "/").first ?? "")]?.name
            let shown = Set(outL.map(\.id))
            for c in atlas.countries where c.name != own {
                guard let l = c.label, let s = P.screen(lon: l.x, lat: l.y) else { continue }
                if let id = atlas.country(named: c.name), shown.contains(id) { continue }
                put("c:" + c.name, c.name, at: [(s.x, s.y + 4, 0.5)], kind: .country, style: .country)
            }
        }
        labels = outL
        dots = outD
        previews = open
    }
}
