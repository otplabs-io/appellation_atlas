import SwiftUI
import UIKit

/// The globe, drawn natively. It flies between places, turns and zooms under the fingers, carries on after a flick,
/// and taps pick a place.
struct GlobeView: View {
    @Environment(Globe.self) private var globe
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MapFilter.key) private var mapFilter = MapFilter.all.rawValue   // so the globe redraws when the filter changes
    var bottomInset: CGFloat = 0
    var topInset: CGFloat = 0
    /// Space covered at the sides, as by an iPad sidebar floating over the map, so the globe centers in what is left.
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0

    var body: some View {
        let _ = mapFilter
        GeometryReader { geo in
            // Read everything the canvas draws here, so any change to it redraws the canvas.
            let frame = Frame(cam: globe.cam, view: globe.view?.id, parent: globe.parent?.id, leaf: globe.leaf, out: globe.outgoing?.view.id,
                              fade: globe.fadeIn, world: globe.worldOpacity, labels: globe.labels.count, dots: globe.dots.count, low: globe.range.0, high: globe.range.1,
                              previews: globe.previews.map(\.id))
            Canvas(rendersAsynchronously: false) { ctx, size in
                _ = frame
                draw(&ctx, size)
            }
            .opacity(globe.appear)
            .contentShape(Rectangle())
            .gesture(GlobeTouches(globe: globe))
            .gesture(
                ExclusiveGesture(
                    SpatialTapGesture(count: 2).onEnded { v in globe.zoomIn(at: v.location) },
                    SpatialTapGesture().onEnded { v in globe.tap(at: v.location) }))
            .onAppear {
                globe.reduceMotion = reduceMotion
                globe.topInset = topInset
                globe.resized(geo.size, bottom: bottomInset, left: leadingInset, right: trailingInset)
            }
            .onChange(of: geo.size) { _, s in globe.resized(s, bottom: bottomInset, left: leadingInset, right: trailingInset) }
            .onChange(of: [bottomInset, leadingInset, trailingInset]) { _, _ in globe.resized(geo.size, bottom: bottomInset, left: leadingInset, right: trailingInset) }
            .onChange(of: topInset) { _, t in globe.topInset = t; globe.relabel() }
            .accessibilityElement()
            .accessibilityLabel("Globe of the world's wine places")
            .accessibilityHint("Showing \(globe.atlas.name(globe.leaf ?? globe.view?.id ?? "world")). Tap a place to open it, double-tap to zoom in, or pick a place from the list.")
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let P = globe.projector
        let R = P.R, cx = P.cx, cy = P.cy
        let disc = Path(ellipseIn: CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R))
        ctx.fill(disc, with: .radialGradient(Gradient(colors: [Palette.oceanHigh, Palette.ocean]),
                                              center: CGPoint(x: cx - 0.16 * R, y: cy - 0.24 * R), startRadius: 0, endRadius: 1.24 * R))
        if R < min(size.width, size.height) * 2.5 {
            ctx.stroke(P.graticule(), with: .color(Palette.graticule.opacity(0.55)), lineWidth: 0.7)
        }
        if globe.showsWorld {
            var w = ctx
            w.opacity = globe.worldOpacity
            var land = Path()
            for c in globe.atlas.countries { for p in c.polys { P.add(p, to: &land) } }
            w.fill(land, with: .color(Palette.land))
            w.stroke(land, with: .color(Palette.landEdge), style: StrokeStyle(lineWidth: 0.6, lineJoin: .round))
        }
        if let out = globe.outgoing {
            var o = ctx
            o.opacity = 1 - globe.fadeIn
            layer(&o, P, out.view, out.parent)
        }
        if let v = globe.view {
            var n = ctx
            n.opacity = globe.outgoing == nil ? 1 : globe.fadeIn
            layer(&n, P, v, globe.parent)
        }
        // the parts of a place big enough to show them: thin lines inside it, a hint of the level below
        for pv in globe.previews {
            var inner = Path()
            for it in pv.items { for p in it.polys { P.add(p, to: &inner) } }
            ctx.stroke(inner, with: .color(Palette.regionStroke.opacity(0.9)), style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
        }
        for d in globe.dots {
            let r: CGFloat = 6
            let c = Path(ellipseIn: CGRect(x: d.point.x - r, y: d.point.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(c, with: .color(globe.leaf == d.id ? Palette.target : dotShade(d.id)))
            ctx.stroke(c, with: .color(Palette.regionStroke), lineWidth: 2)
        }
        for l in globe.labels { label(&ctx, l) }
        ctx.stroke(disc, with: .color(Palette.landEdge), lineWidth: 1)
    }

    private func dotShade(_ id: String) -> Color {
        globe.atlas.mapShade(id)
    }

    /// A view's layers: the land near it, its neighbours, the place itself, its places.
    private func layer(_ ctx: inout GraphicsContext, _ P: Projector, _ v: MapView, _ par: MapView?) {
        if !v.context.isEmpty {
            var land = Path()
            for polys in v.context { for p in polys { P.add(p, to: &land) } }
            ctx.fill(land, with: .color(Palette.land))
            ctx.stroke(land, with: .color(Palette.landEdge), style: StrokeStyle(lineWidth: 0.6, lineJoin: .round))
        }
        if let par {
            var sib = Path()
            for it in par.items where it.id != v.id { for p in it.polys { P.add(p, to: &sib) } }
            ctx.fill(sib, with: .color(Palette.sibling))
            ctx.stroke(sib, with: .color(Palette.landEdge), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        }
        if !v.outline.isEmpty {
            let o = P.path(v.outline)
            if v.id != "world" { ctx.fill(o, with: .color(Palette.gold4[0])) }
            ctx.stroke(o, with: .color(Palette.teal), style: StrokeStyle(lineWidth: 1.6, dash: [5, 3]))
        }
        let isCurrent = globe.view?.id == v.id
        // biggest first (the items come sorted), so the places inside a big one stay visible over it
        var picked: Path?
        for it in v.items {
            let path = P.path(it.polys)
            if path.isEmpty { continue }
            ctx.fill(path, with: .color(globe.atlas.mapShade(it.id)))
            ctx.stroke(path, with: .color(Palette.regionStroke), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            if isCurrent && globe.leaf == it.id { picked = path }
        }
        // the chosen place's edge over everything, so its whole extent shows even where smaller places cover it
        if let picked {
            // tinted over everything, not painted: a big one (Toscana IGT) still shows the places inside it
            ctx.fill(picked, with: .color(Palette.target.opacity(0.3)))
            ctx.stroke(picked, with: .color(Palette.regionStroke), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            ctx.stroke(picked, with: .color(Palette.target), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }
        // the rivers and lakes the pages name, over the places so they show
        if !v.water.isEmpty {
            var lakes = Path()
            for w in v.water where w.lake { for p in w.polys { P.add(p, to: &lakes) } }
            ctx.fill(lakes, with: .color(Palette.lake))
            ctx.stroke(lakes, with: .color(Palette.river), style: StrokeStyle(lineWidth: 0.8, lineJoin: .round))
            var rivers = Path()
            for w in v.water where !w.lake { rivers.addPath(P.lines(w.lines)) }
            ctx.stroke(rivers, with: .color(Palette.paper.opacity(0.9)), style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))   // a pale edge, so a river reads across the deepest gold
            ctx.stroke(rivers, with: .color(Palette.river), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func label(_ ctx: inout GraphicsContext, _ l: MapLabel) {
        let st = l.style
        if l.kind == .place && l.id == globe.leaf {   // the chosen place's name, set on a pill so it reads at a glance
            let r = ctx.resolve(Text(l.text).font(st.font).foregroundStyle(Color.white))
            let sz = r.measure(in: CGSize(width: 1000, height: 100))
            let x = l.point.x - sz.width * l.anchor.x, y = l.point.y - sz.height * l.anchor.y
            let pill = Path(roundedRect: CGRect(x: x - 7, y: y - 3, width: sz.width + 14, height: sz.height + 6), cornerRadius: (sz.height + 6) / 2)
            ctx.fill(pill, with: .color(Palette.target))
            ctx.stroke(pill, with: .color(Palette.regionStroke), lineWidth: 1.5)
            ctx.draw(r, at: l.point, anchor: l.anchor)
            return
        }
        if let d = l.dot {   // a town's spot
            let c = Path(ellipseIn: CGRect(x: d.x - 2.6, y: d.y - 2.6, width: 5.2, height: 5.2))
            ctx.fill(c, with: .color(Palette.soft))
            ctx.stroke(c, with: .color(Palette.paper), lineWidth: 1)
        }
        let color: Color = switch st.tone {
        case .ink: Palette.ink
        case .soft: Palette.soft
        case .faint: Palette.ink.opacity(0.5)
        case .water: Palette.riverInk
        }
        let r = ctx.resolve(Text(l.text).font(st.italic ? st.font.italic() : st.font).kerning(st.kern).foregroundStyle(color))
        var halo = ctx
        let blur: CGFloat = st.tone == .ink ? 1.2 : 1
        for _ in 0..<3 { halo.addFilter(.shadow(color: Palette.halo, radius: blur)) }
        if l.angle != 0 {   // a river's name runs along it
            halo.translateBy(x: l.point.x, y: l.point.y)
            halo.rotate(by: .degrees(l.angle))
            halo.draw(r, at: .zero, anchor: l.anchor)
        } else {
            halo.draw(r, at: l.point, anchor: l.anchor)
        }
    }
}

/// What one drawn frame depends on.
private struct Frame: Equatable {
    let cam: Camera
    let view: String?, parent: String?, leaf: String?, out: String?
    let fade: Double, world: Double
    let labels: Int, dots: Int
    let low: Double, high: Double
    let previews: [String]
}

/// Every finger on the globe, the way the website hears pointers: the midpoint of the fingers, the space between the
/// first two, and how many there are. SwiftUI's drag follows only the first finger, which pinned that finger's spot
/// in place during a pinch instead of the spot between the fingers.
struct GlobeTouches: UIGestureRecognizerRepresentable {
    let globe: Globe

    func makeUIGestureRecognizer(context: Context) -> Fingers { Fingers() }

    func handleUIGestureRecognizerAction(_ r: Fingers, context: Context) {
        switch r.state {
        case .began, .changed:
            globe.touchesMoved(to: context.converter.localLocation, spread: r.spread, fingers: r.touches.count, time: r.time)
        case .ended, .cancelled:
            globe.touchesEnded(time: r.time)
        default: break
        }
    }

    /// Starts once a finger has moved a few points, so taps still reach the tap gestures, and ends when the last
    /// finger lifts.
    final class Fingers: UIGestureRecognizer {
        private(set) var touches: [UITouch] = []
        private(set) var time: TimeInterval = 0
        /// Where each finger landed, to tell a drag from a tap.
        private var landed: [UITouch: CGPoint] = [:]

        /// How far apart the first two fingers are, in points.
        var spread: Double? {
            guard touches.count > 1, let v = view else { return nil }
            let a = touches[0].location(in: v), b = touches[1].location(in: v)
            return hypot(a.x - b.x, a.y - b.y)
        }

        override func location(in v: UIView?) -> CGPoint {
            guard !touches.isEmpty else { return .zero }
            let ps = touches.map { $0.location(in: v) }
            return CGPoint(x: ps.map(\.x).reduce(0, +) / CGFloat(ps.count), y: ps.map(\.y).reduce(0, +) / CGFloat(ps.count))
        }

        override func touchesBegan(_ ts: Set<UITouch>, with e: UIEvent) {
            touches += ts.filter { !touches.contains($0) }
            time = e.timestamp
            for t in ts { landed[t] = t.location(in: view) }
            if state == .began || state == .changed { state = .changed }
        }

        override func touchesMoved(_ ts: Set<UITouch>, with e: UIEvent) {
            time = e.timestamp
            if state == .possible {
                if touches.contains(where: { t in landed[t].map { p in let q = t.location(in: view); return hypot(q.x - p.x, q.y - p.y) >= 3 } ?? false }) {
                    state = .began
                }
            } else if state == .began || state == .changed { state = .changed }
        }

        override func touchesEnded(_ ts: Set<UITouch>, with e: UIEvent) { lift(ts, e, cancelled: false) }
        override func touchesCancelled(_ ts: Set<UITouch>, with e: UIEvent) { lift(ts, e, cancelled: true) }

        private func lift(_ ts: Set<UITouch>, _ e: UIEvent, cancelled: Bool) {
            touches.removeAll { ts.contains($0) }
            for t in ts { landed[t] = nil }
            time = e.timestamp
            let on = state == .began || state == .changed
            if touches.isEmpty { state = on ? (cancelled ? .cancelled : .ended) : .failed }
            else if on { state = .changed }
        }

        override func reset() { super.reset(); touches = []; landed = [:] }
    }
}
