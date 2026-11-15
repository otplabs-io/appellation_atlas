import SwiftUI

/// The globe, drawn natively. It flies between places, turns and zooms under the fingers, carries on after a flick,
/// and taps pick a place.
struct GlobeView: View {
    @Environment(Globe.self) private var globe
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var bottomInset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            // Read everything the canvas draws here, so any change to it redraws the canvas.
            let frame = Frame(cam: globe.cam, view: globe.view?.id, parent: globe.parent?.id, leaf: globe.leaf, out: globe.outgoing?.view.id,
                              fade: globe.fadeIn, world: globe.worldOpacity, labels: globe.labels.count, dots: globe.dots.count, low: globe.range.0, high: globe.range.1)
            Canvas(rendersAsynchronously: false) { ctx, size in
                _ = frame
                draw(&ctx, size)
            }
            .opacity(globe.appear)
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { globe.dragChanged(start: $0.startLocation, translation: $0.translation) }
                        .onEnded { globe.dragEnded(velocity: $0.velocity) },
                    MagnifyGesture()
                        .onChanged { globe.pinchChanged(scale: $0.magnification, anchor: $0.startLocation) }
                        .onEnded { _ in globe.pinchEnded() }))
            .gesture(
                ExclusiveGesture(
                    SpatialTapGesture(count: 2).onEnded { _ in globe.zoomOut() },
                    SpatialTapGesture().onEnded { v in if let id = globe.hit(v.location) { globe.onPick(id) } }))
            .onAppear {
                globe.reduceMotion = reduceMotion
                globe.resized(geo.size, bottom: bottomInset)
            }
            .onChange(of: geo.size) { _, s in globe.resized(s, bottom: bottomInset) }
            .onChange(of: bottomInset) { _, b in globe.resized(geo.size, bottom: b) }
            .accessibilityElement()
            .accessibilityLabel("Globe of the world's wine places")
            .accessibilityHint("Showing \(globe.atlas.name(globe.leaf ?? globe.view?.id ?? "world")). Pick a place from the list to go to it.")
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
        let t = globe.atlas.tier(id, range: globe.range)
        if t == 0 { return Palette.gold4[0] }
        return globe.atlas.isBenchmark(id) ? Palette.gold4[max(2, t)] : Palette.grey4[max(2, t)]
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
        // the chosen place last, so places that share its boundary do not cover it
        let ordered = isCurrent && globe.leaf != nil ? v.items.filter { $0.id != globe.leaf } + v.items.filter { $0.id == globe.leaf } : v.items
        for it in ordered {
            let path = P.path(it.polys)
            if path.isEmpty { continue }
            let tier = globe.atlas.tier(it.id, range: globe.range)
            let fill: Color = isCurrent && globe.leaf == it.id ? Palette.target : Palette.shade(benchmark: globe.atlas.isBenchmark(it.id), tier: tier)
            ctx.fill(path, with: .color(fill))
            ctx.stroke(path, with: .color(tier == 0 ? Palette.landEdge : Palette.regionStroke), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        }
    }

    private func label(_ ctx: inout GraphicsContext, _ l: MapLabel) {
        let text: Text
        switch l.kind {
        case .place: text = Text(l.text).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ink)
        case .country: text = Text(l.text).font(.system(size: 10, weight: .bold)).kerning(0.8).foregroundStyle(Palette.soft)
        }
        let r = ctx.resolve(text)
        var halo = ctx
        halo.addFilter(.shadow(color: Palette.halo, radius: 1.2))
        halo.addFilter(.shadow(color: Palette.halo, radius: 1.2))
        halo.addFilter(.shadow(color: Palette.halo, radius: 1.2))
        halo.draw(r, at: l.point, anchor: l.anchor)
    }
}

/// What one drawn frame depends on.
private struct Frame: Equatable {
    let cam: Camera
    let view: String?, parent: String?, leaf: String?, out: String?
    let fade: Double, world: Double
    let labels: Int, dots: Int
    let low: Double, high: Double
}
