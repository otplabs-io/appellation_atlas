import SwiftUI

/// The kinds of figure the person can show in US or metric units (UNIT_KINDS in atlas.js).
enum UnitKind: String, CaseIterable { case temp, heat, rain, elev, dist, area }

/// Units, one choice per kind, saved on the device. A kind the person has not set follows the device's region.
/// Mirrors the unit formatters in atlas.js: change one, change the other.
enum Units {
    static let key = "units"

    /// "us" or "m" for each kind the person set, as "temp=us,heat=m".
    static func saved(_ s: String = UserDefaults.standard.string(forKey: key) ?? "") -> [UnitKind: String] {
        var out: [UnitKind: String] = [:]
        for part in s.split(separator: ",") {
            let kv = part.split(separator: "=").map(String.init)
            if kv.count == 2, let k = UnitKind(rawValue: kv[0]), kv[1] == "us" || kv[1] == "m" { out[k] = kv[1] }
        }
        return out
    }

    static var regionDefault: String { Locale.current.measurementSystem == .us ? "us" : "m" }

    static func value(_ k: UnitKind, _ s: String? = nil) -> String {
        (s.map { saved($0) } ?? saved())[k] ?? regionDefault
    }

    static func us(_ k: UnitKind) -> Bool { value(k) == "us" }

    /// Figures inside place text arrive marked with both wordings, ⟦kind|US|metric⟧ (src/units.py). This keeps one
    /// (unitText in atlas.js).
    static func text(_ s: String) -> String {
        guard s.contains("⟦") else { return s }
        var out = "", rest = Substring(s)
        while let open = rest.firstIndex(of: "⟦"), let close = rest[open...].firstIndex(of: "⟧") {
            out += rest[..<open]
            let parts = rest[rest.index(after: open)..<close].split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3, let k = UnitKind(rawValue: String(parts[0])) { out += us(k) ? parts[1] : parts[2] } else { out += rest[open...close] }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    /// Sets one kind, or every kind when k is nil, and returns the string to save.
    static func setting(_ k: UnitKind?, to v: String, in s: String) -> String {
        var all = Dictionary(uniqueKeysWithValues: UnitKind.allCases.map { ($0, value($0, s)) })
        for x in k.map({ [$0] }) ?? UnitKind.allCases { all[x] = v }
        return UnitKind.allCases.map { "\($0.rawValue)=\(all[$0]!)" }.joined(separator: ",")
    }

    // Formatters

    static func tN(_ c: Double) -> Int { Int((us(.temp) ? toF(c) : c).rounded()) }
    static var tU: String { us(.temp) ? "°F" : "°C" }
    static func deg(_ c: Double) -> String { "\(tN(c))\(tU)" }
    /// "59°F" when both ends round the same, else "57 to 61°F".
    static func degRange(_ a: Double, _ b: Double) -> String { tN(a) == tN(b) ? deg(a) : "\(tN(a)) to \(tN(b))\(tU)" }

    static func heat(_ gdd: Double) -> String { "\(fmt(((us(.heat) ? gdd * 1.8 : gdd) / 10).rounded() * 10)) degree days" }
    static var heatNote: String { us(.heat) ? "°F, above 50°F" : "°C, above 10°C" }

    static func elN(_ m: Double) -> String { us(.elev) ? fmt(feet(m)) : fmt((m / 5).rounded() * 5) }
    static var elU: String { us(.elev) ? "ft" : "m" }
    static func elev(_ m: Double) -> String { "\(elN(m)) \(elU)" }
    static func elevRange(_ a: Double, _ b: Double) -> String { "\(elN(a)) to \(elN(b)) \(elU)" }
    static var soilDepth: String { us(.elev) ? "1 to 2 feet" : "30 to 60 cm" }

    static func area(_ ha: Double) -> String { us(.area) ? "\(fmt(ha * 2.471)) acres" : "\(fmt(ha)) hectares" }
    static func areaShort(_ ha: Double) -> String { us(.area) ? "\(fmt(ha * 2.471)) acres" : "\(fmt(ha)) ha" }
    static func land(_ km2: Double) -> String { us(.area) ? "\(fmt(km2 * 0.3861)) square miles" : "\(fmt(km2)) km²" }
}

/// Chooses the units: the whole system at once, or each kind on its own (openUnits in atlas.js).
struct UnitsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Units.key) private var saved = ""

    private let rows: [(UnitKind, String, String, String)] = [
        (.temp, "Temperature", "°F", "°C"), (.heat, "Heat", "°F days", "°C days"), (.rain, "Rainfall", "in", "mm"),
        (.elev, "Elevation", "ft", "m"), (.dist, "Distance", "mi", "km"), (.area, "Area", "acres", "ha"),
    ]

    private var system: String {
        let v = Set(UnitKind.allCases.map { Units.value($0, saved) })
        return v.count == 1 ? v.first! : "custom"
    }

    private func example(_ k: UnitKind) -> String {
        _ = saved
        switch k {
        case .temp: return "Burgundy's growing season: \(Units.deg(14.8))"
        case .heat: return "Burgundy: \(Units.heat(1064))"
        case .rain: return "Shown in \(Units.us(.rain) ? "inches" : "millimeters")"
        case .elev: return "Heights and lengths in \(Units.us(.elev) ? "feet" : "meters")"
        case .dist: return "Shown in \(Units.us(.dist) ? "miles" : "kilometers")"
        case .area: return "Shown in \(Units.us(.area) ? "acres" : "hectares")"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Measurement system", selection: Binding(get: { system }, set: { v in if v != "custom" { saved = Units.setting(nil, to: v, in: saved) } })) {
                        Text("US").tag("us")
                        Text("Metric").tag("m")
                        if system == "custom" { Text("Custom").tag("custom") }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach(rows, id: \.0) { k, name, a, b in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(name).font(.atlasBody.weight(.bold))
                                Text(example(k)).font(.atlasNote).foregroundStyle(Palette.soft)
                            }
                            Spacer(minLength: 8)
                            Picker(name, selection: Binding(get: { Units.value(k, saved) }, set: { saved = Units.setting(k, to: $0, in: saved) })) {
                                Text(a).tag("us")
                                Text(b).tag("m")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                    }
                } footer: {
                    Text("At first the Atlas follows your device's region. Figures set by law stay as the rules state them, like yields in hectoliters per hectare.")
                }
            }
            .navigationTitle("Units")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Opens Units.
struct UnitsButton: View {
    @State private var open = false
    var body: some View {
        Button { open = true } label: { Label("Units", systemImage: "ruler") }
            .sheet(isPresented: $open) { UnitsView() }
    }
}
