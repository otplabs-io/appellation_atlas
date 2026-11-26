import Charts
import SwiftUI

/// Lays out views in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > 0 && x + d.width > width { y += row + spacing; x = 0; row = 0 }
            x += d.width + spacing
            row = max(row, d.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + d.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(d))
            x += d.width + spacing
            row = max(row, d.height)
        }
    }
}

/// A titled section of a place's page.
struct AtlasSection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.atlasSection).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                if let note { Text(note).font(.atlasNote).foregroundStyle(Palette.soft).multilineTextAlignment(.trailing) }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 30).padding(.bottom, 24)
        // a band across the whole card between sections, so each one reads as its own block
        .overlay(alignment: .top) { Rectangle().fill(Palette.fill).frame(height: 8).padding(.horizontal, -20) }
    }
}

struct Fact: Identifiable {
    let label: String
    let value: String
    var note: String = ""
    var id: String { label }
}

/// Figures in a grid: a small label, the value, a note under it.
struct FactGrid: View {
    let facts: [Fact]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 20, alignment: .topLeading)], alignment: .leading, spacing: 22) {
            ForEach(facts.filter { !$0.value.isEmpty }) { f in
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.label.uppercased()).font(.atlasLabel).kerning(0.6).foregroundStyle(Palette.soft)
                    Text(f.value).font(.atlasValue).foregroundStyle(Palette.ink)
                    if !f.note.isEmpty { Text(f.note).font(.atlasNote).foregroundStyle(Palette.soft) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A small caption above a part of a section.
struct SubCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.atlasNote).foregroundStyle(Palette.soft).padding(.top, 8) }
}

/// Grapes or names as chips, colored down the left edge by skin.
struct Chips: View {
    let items: [(name: String, skin: String, count: Int?)]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, c in
                HStack(spacing: 6) {
                    Text(c.name).font(.atlasBody)
                    if let n = c.count { Text("\(n)").font(.atlasNote.weight(.semibold)).foregroundStyle(Palette.soft) }
                }
                .padding(.horizontal, 9).frame(minHeight: 28)
                .background(Palette.fill)
                .overlay(alignment: .leading) { Rectangle().fill(skinColor(c.skin)).frame(width: 4) }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    private func skinColor(_ s: String) -> Color {
        switch s {
        case "red": Palette.red
        case "white": Palette.gold
        case "pink": Palette.pink
        default: Palette.landEdge
        }
    }
}

/// A row of categories, with the place's one lit and marked.
struct ScaleBar: View {
    let segments: [(String, String)]
    let index: Int
    let position: Double
    let label: String

    var body: some View {
        GeometryReader { g in
            let w = g.size.width / CGFloat(segments.count)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { k, s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.0).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                            if w > 64 { Text(s.1).font(.system(size: 9.5)).lineLimit(2) }
                        }
                        .foregroundStyle(k == index ? Palette.ink : Palette.soft)
                        .padding(.horizontal, 4).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(k == index ? Palette.gold4[3] : Palette.fill)
                    }
                }
                if index >= 0 {
                    Triangle().fill(Palette.ink).frame(width: 12, height: 7)
                        .offset(x: (CGFloat(index) + CGFloat(max(0.04, min(0.96, position)))) * w - 6, y: -6)
                }
            }
        }
        .frame(height: 48)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(index >= 0 ? segments[index].0 : "")
    }
}

nonisolated struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath() }
    }
}

/// Twelve monthly bars with the growing season colored.
struct MonthsChart: View {
    let values: [Double]
    var shown: [Double]? = nil   // the numbers to print, when the bars are drawn from other values (heights from °F, so the shape is the same in °C)
    let unit: String
    let season: Color
    let base: Color
    let south: Bool
    var labels = false   // each bar's value on top, as on the website's temperature chart

    var body: some View {
        let gs: Set<Int> = south ? [9, 10, 11, 0, 1, 2, 3] : [3, 4, 5, 6, 7, 8, 9]
        let letters = Array("JFMAMJJASOND")
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            BarMark(x: .value("Month", "\(i)"), y: .value(unit, v))
                .foregroundStyle(gs.contains(i) ? season : base)
                .accessibilityLabel(Calendar(identifier: .gregorian).monthSymbols[i])
                .accessibilityValue("\(Int((shown?[i] ?? v).rounded())) \(unit)")
                .annotation(position: .top, spacing: 2) {
                    if labels { Text("\(Int((shown?[i] ?? v).rounded()))").font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.ink) }
                }
        }
        .chartXAxis {
            AxisMarks(values: (0..<12).map { "\($0)" }) { v in
                AxisValueLabel { Text(String(letters[Int(v.as(String.self) ?? "0") ?? 0])).font(.system(size: 9)) }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: labels ? 84 : 70)
    }
}

/// Which way the slopes face: eight petals, longest where most of the ground faces.
struct Rose: View {
    let aspect: [String: Double]

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100, c = CGPoint(x: size.width / 2, y: size.height / 2)
            let top = max(aspect.values.max() ?? 1, 0.0001)
            for (k, d) in Copy.compass.enumerated() {
                let r = (8 + (aspect[d] ?? 0) / top * 30) * s
                let a1 = (Double(k) * 45 - 20) * Double.pi / 180, a2 = (Double(k) * 45 + 20) * Double.pi / 180
                var p = Path()
                p.move(to: c)
                p.addArc(center: c, radius: r, startAngle: .radians(a1 - Double.pi / 2), endAngle: .radians(a2 - Double.pi / 2), clockwise: false)
                p.closeSubpath()
                ctx.fill(p, with: .color(Palette.gold4[3]))
                ctx.stroke(p, with: .color(Palette.regionStroke), lineWidth: 1)
            }
            for (t, x, y) in [("N", 0.0, -42.0), ("S", 0, 45), ("E", 45, 1), ("W", -45, 1)] {
                ctx.draw(Text(t).font(.system(size: 10)).foregroundStyle(Palette.soft), at: CGPoint(x: c.x + x * s, y: c.y + y * s))
            }
        }
        .frame(width: 120, height: 120)
        .accessibilityLabel("Which way the slopes face")
    }
}

/// What the numbers above mean for the vines: short labelled points, set apart in a panel.
struct Reading: View {
    let title: String
    let points: [(String, String)]

    var body: some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title.uppercased()).font(.atlasLabel).kerning(0.6).foregroundStyle(Palette.soft)
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.0).font(.atlasLabel).foregroundStyle(Palette.ink)
                        Text(p.1).font(.atlasBody).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            .padding(.top, 4)
        }
    }
}

struct Swatch: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 16, height: 11)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Palette.landEdge, lineWidth: 0.5))
    }
}
