import CoreGraphics
import Foundation
import SwiftUI
import simd

// The globe's math, ported from web/atlas.js so both draw the same map: an orthographic globe, polygons cut at the
// horizon and closed along its edge, and the same culling.

typealias V3 = SIMD3<Double>
typealias V2 = SIMD2<Double>
let RAD = Double.pi / 180

func unitVector(lon: Double, lat: Double) -> V3 {
    let l = lon * RAD, p = lat * RAD
    return V3(cos(p) * cos(l), cos(p) * sin(l), sin(p))
}

/// One polygon: its rings as unit vectors, its center and how far its farthest point lies from it.
struct Poly: Sendable {
    let rings: [[V3]]
    let center: V3
    let radius: Double
}

/// Polygons as the data stores them: [[[lon, lat, lon, lat, ...], hole...], ...].
func preparePolys(_ json: JSON) -> [Poly] {
    json.array.map { poly in
        var sum = V3.zero
        let rings: [[V3]] = poly.array.map { ring in
            let a = ring.doubles
            var pts: [V3] = []
            pts.reserveCapacity(a.count / 2)
            var k = 0
            while k + 1 < a.count {
                let v = unitVector(lon: a[k], lat: a[k + 1])
                pts.append(v)
                sum += v
                k += 2
            }
            return pts
        }
        let len = simd_length(sum)
        let c = len > 0 ? sum / len : V3(1, 0, 0)
        var m = 1.0
        for r in rings { for p in r { m = min(m, simd_dot(p, c)) } }
        return Poly(rings: rings, center: c, radius: acos(max(-1, min(1, m))))
    }
}

/// An open line (a river): its points as unit vectors, with a center and reach to skip it when out of sight.
struct Line: Sendable {
    let points: [V3]
    let center: V3
    let radius: Double
}

/// Lines as the data stores them: [[lon, lat, lon, lat, ...], ...].
func prepareLines(_ json: JSON) -> [Line] {
    json.array.map { line in
        let a = line.doubles
        var pts: [V3] = []
        pts.reserveCapacity(a.count / 2)
        var sum = V3.zero
        var k = 0
        while k + 1 < a.count {
            let v = unitVector(lon: a[k], lat: a[k + 1])
            pts.append(v); sum += v
            k += 2
        }
        let len = simd_length(sum)
        let c = len > 0 ? sum / len : V3(1, 0, 0)
        var m = 1.0
        for p in pts { m = min(m, simd_dot(p, c)) }
        return Line(points: pts, center: c, radius: acos(max(-1, min(1, m))))
    }
}

/// Where the globe is turned to, and how big it is drawn (its radius in points).
struct Camera: Equatable, Sendable {
    var lon: Double
    var lat: Double
    var R: Double
}

/// Projects the globe for one camera onto a canvas. `cx, cy` is the globe's center on screen.
struct Projector {
    let e: V3, n: V3, v: V3
    let R: Double, cx: Double, cy: Double
    let l0: Double, c0: Double, s0: Double
    let viewAngle: Double

    init(_ cam: Camera, center: CGPoint, diagonal: Double) {
        let l = cam.lon * RAD, p = cam.lat * RAD
        e = V3(-sin(l), cos(l), 0)
        n = V3(-sin(p) * cos(l), -sin(p) * sin(l), cos(p))
        v = V3(cos(p) * cos(l), cos(p) * sin(l), sin(p))
        R = cam.R; cx = center.x; cy = center.y
        l0 = l; c0 = cos(p); s0 = sin(p)
        let hd = diagonal / 2
        viewAngle = hd >= cam.R ? Double.pi / 2 : asin(hd / cam.R) + 0.01
    }

    @inline(__always) func project(_ q: V3) -> V3 { V3(simd_dot(q, e), simd_dot(q, n), simd_dot(q, v)) }
    @inline(__always) func screen(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: cx + R * x, y: cy - R * y) }

    func screen(lon: Double, lat: Double) -> CGPoint? {
        let q = project(unitVector(lon: lon, lat: lat))
        return q.z < 0 ? nil : screen(q.x, q.y)
    }

    /// The longitude and latitude under a screen point, or nil off the globe.
    func geo(at s: CGPoint) -> V2? { unproject(x: (s.x - cx) / R, y: (cy - s.y) / R) }

    func unproject(x: Double, y: Double) -> V2? {
        let r = hypot(x, y)
        if r > 1 { return nil }
        let c = asin(r), sc = sin(c), cc = cos(c)
        let lon = (l0 + atan2(x * sc, r * cc * c0 - y * sc * s0)) / RAD
        let lat = asin(cc * s0 + (r > 0 ? y * sc * c0 / r : 0)) / RAD
        return V2(lon, lat)
    }

    /// Adds a polygon to a path, or returns false when it is out of sight or too small to see.
    @discardableResult
    func add(_ poly: Poly, to path: inout Path) -> Bool {
        let dist = acos(max(-1, min(1, simd_dot(poly.center, v))))
        if dist - poly.radius > viewAngle || sin(min(poly.radius, 1.5)) * R < 0.35 { return false }
        let projected = poly.rings.map { $0.map(project) }
        let rings: [[V2]] = dist + poly.radius > Double.pi / 2 - 1e-4
            ? clipAtHorizon(projected, reach: poly.radius)
            : projected.map { $0.map { V2($0.x, $0.y) } }
        var any = false
        for r in rings where r.count > 2 {
            path.move(to: screen(r[0].x, r[0].y))
            for q in r.dropFirst() { path.addLine(to: screen(q.x, q.y)) }
            path.closeSubpath()
            any = true
        }
        return any
    }

    func path(_ polys: [Poly]) -> Path {
        var p = Path()
        for poly in polys { add(poly, to: &p) }
        return p
    }

    /// Open lines, broken at the horizon, with points under a point apart dropped (lineD in web/atlas.js).
    func lines(_ ls: [Line]) -> Path {
        var d = Path()
        for l in ls {
            if acos(max(-1, min(1, simd_dot(l.center, v)))) - l.radius > viewAngle { continue }
            var on = false
            var last = CGPoint.zero
            for (i, p) in l.points.enumerated() {
                let q = project(p)
                if q.z < 0 { on = false; continue }
                let s = screen(q.x, q.y)
                if on && i < l.points.count - 1 && abs(s.x - last.x) + abs(s.y - last.y) < 1 { continue }
                if on { d.addLine(to: s) } else { d.move(to: s) }
                last = s; on = true
            }
        }
        return d
    }

    /// Lines of longitude and latitude every 15 degrees.
    func graticule() -> Path {
        var d = Path()
        func line(_ pts: [(Double, Double)]) {
            var on = false
            for (lo, la) in pts {
                let q = project(unitVector(lon: lo, lat: la))
                if q.z < 0 { on = false; continue }
                let s = screen(q.x, q.y)
                if on { d.addLine(to: s) } else { d.move(to: s) }
                on = true
            }
        }
        for lo in stride(from: -180.0, to: 180, by: 15) { line(stride(from: -80.0, through: 80, by: 4).map { (lo, $0) }) }
        for la in stride(from: -75.0, through: 75, by: 15) { line(stride(from: -180.0, through: 180, by: 4).map { ($0, la) }) }
        return d
    }
}

/// Cuts rings at the horizon and closes them along the globe's edge. Outer rings run counterclockwise.
/// `reach` is how far the polygon spreads from its center: one smaller than a hemisphere never needs an edge arc
/// most of the way round. Such an arc comes from a coast that dips just behind the edge and back, where the two
/// crossings land a hair out of order, and drawing it would paint the whole globe for a frame.
func clipAtHorizon(_ rings: [[V3]], reach: Double = .pi) -> [[V2]] {
    var out: [[V2]] = []
    var segs: [[V2]] = []
    func cross(_ a: V3, _ b: V3) -> V2 {
        let t = a.z / (a.z - b.z)
        let x = a.x + t * (b.x - a.x), y = a.y + t * (b.y - a.y)
        let L = max(hypot(x, y), 1e-12)
        return V2(x / L, y / L)
    }
    for r in rings {
        let n = r.count
        var vis = 0
        for p in r where p.z >= 0 { vis += 1 }
        if vis == n { out.append(r.map { V2($0.x, $0.y) }); continue }
        if vis == 0 { continue }
        var s = 0
        while !(r[s].z >= 0 && r[(s - 1 + n) % n].z < 0) { s += 1 }
        var cur: [V2]? = [cross(r[(s - 1 + n) % n], r[s])]
        for k in 0..<n {
            let a = r[(s + k) % n], b = r[(s + k + 1) % n]
            if a.z >= 0 {
                cur?.append(V2(a.x, a.y))
                if b.z < 0, var c = cur { c.append(cross(a, b)); segs.append(c); cur = nil }
            } else if b.z >= 0 {
                cur = [cross(a, b)]
            }
        }
    }
    struct Seg { var p: [V2]; var a0: Double; var a1: Double; var used = false }
    var sg = segs.compactMap { p -> Seg? in
        guard let f = p.first, let l = p.last else { return nil }
        return Seg(p: p, a0: atan2(f.y, f.x), a1: atan2(l.y, l.x))
    }
    let tau = 2 * Double.pi
    for i0 in sg.indices {
        if sg[i0].used { continue }
        var ring: [V2] = []
        var s = i0
        for _ in 0..<400 {
            sg[s].used = true
            ring += sg[s].p
            var best = -1, bd = 9.0
            for t in sg.indices where !sg[t].used || t == i0 {
                var d = (sg[t].a0 - sg[s].a1).truncatingRemainder(dividingBy: tau)
                if d < 0 { d += tau }
                if d > tau - 0.1 && reach < 1.4 { d = 0 }   // a hair out of order, not the long way round
                if d < bd { bd = d; best = t }
            }
            let steps = Int(ceil(bd / 0.06))
            if steps > 1 {
                for k in 1..<steps {
                    let a = sg[s].a1 + bd * Double(k) / Double(steps)
                    ring.append(V2(cos(a), sin(a)))
                }
            }
            if best < 0 || best == i0 { break }
            s = best
        }
        out.append(ring)
    }
    return out
}
