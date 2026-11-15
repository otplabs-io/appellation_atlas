import Observation
import QuartzCore
import SwiftUI
import UIKit

/// A label placed on the globe.
struct MapLabel: Identifiable {
    enum Kind { case place, country }
    let id: String
    let text: String
    let point: CGPoint
    let anchor: UnitPoint
    let kind: Kind
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
    private(set) var range: (Double, Double) = (0, 0)
    private(set) var busy = false
    /// Changes each time the globe settles into a new place, for a light haptic tap.
    private(set) var arrivals = 0
    /// Called when the globe picks a place: a tap, or zooming far enough into one.
    @ObservationIgnored var onPick: (String) -> Void = { _ in }
    @ObservationIgnored private let ticker = Ticker()
    @ObservationIgnored private var want = "world"
    @ObservationIgnored private var going = false
    @ObservationIgnored private var gesture: (cam: Camera, anchor: CGPoint, geo: V2?)?
    @ObservationIgnored private var drag = CGSize.zero
    @ObservationIgnored private var pinch = 1.0
    @ObservationIgnored var reduceMotion = false

    init(atlas: Atlas, opening: String = "world") {
        self.atlas = atlas
        want = opening
    }

    // ---- layout

    var center: CGPoint { CGPoint(x: size.width / 2, y: (size.height - bottomInset) / 2) }
    var fitSize: CGSize { CGSize(width: size.width, height: max(200, size.height - bottomInset)) }
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

    func resized(_ s: CGSize, bottom: CGFloat) {
        guard s.width > 0, s.height > 0 else { return }
        let first = size == .zero
        size = s
        bottomInset = bottom
        if first { Task { await show(want) } }
        else if let v = view, !busy { cam = camFor(v); relabel() }
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
        Palette.shade(benchmark: atlas.isBenchmark(id), tier: atlas.tier(id, range: range))
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
            guard let v = atlas.view(atlas.viewFor(target)) ?? atlas.view("world") else { break }
            let par = v.parent.flatMap { atlas.view($0) }
            leaf = target != v.id && target != "world" ? target : nil
            if view == nil {
                view = v; parent = par
                let b = camFor(v)
                worldOpacity = needsWorld(b, v) ? 1 : 0
                restyle()
                if v.id == "world" && !reduceMotion { await intro(b) } else { cam = b }
            } else if view!.id != v.id {
                await fly(v, par)
            } else if cam.R > camFor(v).R * 1.03 && leaf == nil {
                await glide(camFor(v))
            }
            if want == target { break }
        }
        restyle()
        relabel()
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

    private func fly(_ v: MapView, _ par: MapView?) async {
        let old = view.map { ($0, parent) }
        let a = cam, b = camFor(v)
        view = v; parent = par; outgoing = old; fadeIn = 0
        restyle(); labels = []; dots = []
        let wa = worldOpacity, wb: Double = needsWorld(b, v) ? 1 : 0
        worldOpacity = max(wa, 0.001)
        let dl = shortest(a.lon, b.lon)
        let zr = abs(log(b.R / a.R))
        let ms = reduceMotion ? 250 : min(1900, 900 + zr * 160)
        busy = true
        await animate(ms) { [self] k in
            let e = Globe.ease(k)
            cam = reduceMotion ? b : lerp(a, b, e, dl)
            fadeIn = min(1, max(0, (e - 0.15) / 0.6))
            worldOpacity = max(0.001, wa + (wb - wa) * e)
        }
        outgoing = nil; cam = b; worldOpacity = wb; fadeIn = 1; busy = false
        arrivals += 1
    }

    private func intro(_ b: Camera) async {
        let a = Camera(lon: b.lon + 300, lat: b.lat - 20, R: b.R * 0.05)
        busy = true; appear = 0
        await animate(3600) { [self] k in
            let z = Globe.ease(min(1, k * 1.15)), sp = 1 - pow(1 - k, 3)
            cam = Camera(lon: a.lon + (b.lon - a.lon) * sp, lat: a.lat + (b.lat - a.lat) * sp, R: exp(log(a.R) + (log(b.R) - log(a.R)) * z))
            appear = min(1, k * 5)
        }
        cam = b; appear = 1; busy = false
    }

    private func glide(_ b: Camera, ms: Double = 500, ease: Bool = true) async {
        let a = cam, dl = shortest(a.lon, b.lon)
        busy = true; labels = []; dots = []
        await animate(reduceMotion ? 1 : ms) { [self] k in
            let e = ease ? Globe.ease(k) : 1 - pow(1 - k, 3)
            cam = lerp(a, b, e, dl)
            if let v = view, v.id != "world" { worldOpacity = needsWorld(cam, v) ? 1 : 0 }
        }
        cam = b; busy = false
        relabel()
    }

    // ---- gestures

    private var baseR: Double { view.map { camFor($0).R } ?? cam.R }
    var zoomed: Bool { cam.R > baseR * 1.03 }

    private func clampR(_ R: Double) -> Double {
        let b = baseR, w = view?.id == "world"
        return min(b * (w ? 14 : 8), max(b * (w ? 0.8 : 0.5), R))
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
        look(g.geo, at: s, R: clampR(g.cam.R * pinch), from: g.cam)
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

    func pinchEnded() { if drag == .zero { endGesture(velocity: .zero) } }

    func dragEnded(velocity: CGSize) { endGesture(velocity: velocity) }

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
        if v.id != "world" && cam.R < b.R * 0.75 { zoomOut(); return }
        if cam.R > b.R * 1.03, await deeper() { return }
        guard !busy, view?.id == v.id else { return }
        if cam.R < b.R {
            await glide(v.id == "world" ? Camera(lon: cam.lon, lat: max(-60, min(70, cam.lat)), R: b.R) : b)
        } else {
            relabel()
        }
    }

    /// The place that fills most of the screen, near the middle, when it clearly leads and has its own map.
    private func deeper() async -> Bool {
        guard let v = view else { return false }
        let P = projector, W = size.width, H = size.height, hd = hypot(W, H) / 2
        var scored: [(MapItem, Double, Double)] = []
        for it in v.items {
            let bb = P.path(it.polys).boundingRect
            if bb.isNull || bb.isEmpty { continue }
            let x0 = max(0, bb.minX), x1 = min(W, bb.maxX), y0 = max(0, bb.minY), y1 = min(H, bb.maxY)
            if x1 <= x0 || y1 <= y0 { continue }
            let a = (x1 - x0) * (y1 - y0) / (W * H)
            let d = hypot((x0 + x1) / 2 - W / 2, (y0 + y1) / 2 - H / 2) / hd
            scored.append((it, a, a * (1 - d * 0.8)))
        }
        scored.sort { $0.2 > $1.2 }
        guard let (best, area, sc) = scored.first, area >= 0.2, scored.count < 2 || scored[1].2 * 1.3 <= sc else { return false }
        if atlas.viewFor(best.id) != best.id {
            if area > 0.45 { onPick(best.id); return true }
            return false
        }
        guard let cv = atlas.view(best.id), cam.R >= camFor(cv).R * 0.6 else { return false }
        onPick(best.id)
        return true
    }

    /// Out one level: from a place to its view, or from a view to its parent.
    func zoomOut() {
        guard !busy, let v = view else { return }
        if leaf != nil { onPick(v.id); return }
        if v.id == "world" { if zoomed { Task { await glide(camFor(v)) } }; return }
        onPick(v.parent ?? "world")
    }

    /// What a tap lands on: a place's shape, or the nearest dot or label point within a fingertip.
    func hit(_ p: CGPoint) -> String? {
        guard let v = view, !busy else { return nil }
        let P = projector
        for it in v.items.reversed() where P.path(it.polys).contains(p, eoFill: false) { return it.id }
        var best: String?, bd = 24.0
        for d in dots { let k = hypot(d.point.x - p.x, d.point.y - p.y); if k < bd { bd = k; best = d.id } }
        if best != nil { return best }
        for it in v.items {
            guard let l = it.label, let s = P.screen(lon: l.x, lat: l.y) else { continue }
            let k = hypot(s.x - p.x, s.y - p.y)
            if k < bd { bd = k; best = it.id }
        }
        return best
    }

    // ---- labels, placed so none overlap, best known first

    func relabel() {
        guard let v = view, size != .zero else { labels = []; dots = []; return }
        let P = projector, W = size.width, H = size.height
        let fs: CGFloat = 13
        let font = UIFont.systemFont(ofSize: fs, weight: .bold)
        var placed: [CGRect] = []
        var outL: [MapLabel] = [], outD: [MapDot] = []
        func free(_ b: CGRect) -> Bool {
            if b.minX < 2 || b.maxX > W - 2 || b.minY < 2 || b.maxY > H - 2 - bottomInset { return false }
            return !placed.contains { b.insetBy(dx: 2, dy: 2).intersects($0) }
        }
        let live = v.items.filter { !$0.polys.isEmpty }.sorted {
            let a = leaf == $0.id ? 1 : 0, b = leaf == $1.id ? 1 : 0
            return a != b ? a > b : atlas.score($0.id) > atlas.score($1.id)
        }
        var points: [String: CGPoint] = [:]
        var dotted: Set<String> = []
        for it in live {
            guard let l = it.label, let s = P.screen(lon: l.x, lat: l.y) else { continue }
            points[it.id] = s
            let bb = P.path(it.polys).boundingRect
            if v.id != "world" && (bb.isNull || max(bb.width, bb.height) < 16) {
                dotted.insert(it.id)
                outD.append(MapDot(id: it.id, point: s))
                placed.append(CGRect(x: s.x - 5, y: s.y - 5, width: 10, height: 10))
            }
        }
        for (n, it) in live.enumerated() {
            guard let s = points[it.id] else { continue }
            let w = (it.name as NSString).size(withAttributes: [.font: font]).width + 8, h = fs * 1.25
            let x = s.x, y = s.y
            // anchor points to try, in order: (x, baseline y, horizontal anchor 0 left, 0.5 middle, 1 right)
            var tries: [(CGFloat, CGFloat, CGFloat)] = dotted.contains(it.id)
                ? [(x + 10, y + 4, 0), (x - 10, y + 4, 1), (x, y - 11, 0.5), (x, y + h + 8, 0.5)]
                : [(x, y + fs * 0.35, 0.5), (x, y - 8, 0.5), (x, y + h + 4, 0.5), (x + 12, y + fs * 0.35, 0), (x - 12, y + fs * 0.35, 1),
                   (x + 8, y - 8, 0), (x - 8, y - 8, 1), (x + 8, y + h + 4, 0), (x - 8, y + h + 4, 1)]
            let force = n == 0
            if force { tries.append((x, y + fs * 0.35, 0.5)) }
            for (k, t) in tries.enumerated() {
                let box = CGRect(x: t.0 - w * t.2, y: t.1 - h, width: w, height: h * 1.25)
                if !(force && k == tries.count - 1) && !free(box) { continue }
                placed.append(box)
                outL.append(MapLabel(id: it.id, text: it.name, point: CGPoint(x: t.0, y: t.1), anchor: UnitPoint(x: t.2, y: 0.8), kind: .place))
                break
            }
        }
        if v.id != "world" {   // the countries around, for bearings
            let own = atlas.places[String(v.id.split(separator: "/").first ?? "")]?.name
            let cf = UIFont.systemFont(ofSize: 10, weight: .bold)
            for c in atlas.countries where c.name != own {
                guard let l = c.label, let s = P.screen(lon: l.x, lat: l.y) else { continue }
                let t = c.name.uppercased()
                let w = (t as NSString).size(withAttributes: [.font: cf, .kern: 0.8]).width
                let box = CGRect(x: s.x - w / 2, y: s.y - 10, width: w, height: 13)
                if !free(box) { continue }
                placed.append(box)
                outL.append(MapLabel(id: "c:" + c.name, text: t, point: s, anchor: UnitPoint(x: 0.5, y: 0.8), kind: .country))
            }
        }
        labels = outL
        dots = outD
    }
}
