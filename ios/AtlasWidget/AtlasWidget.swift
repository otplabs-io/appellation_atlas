import SwiftUI
import WidgetKit

/// One place the widget can show (from widget-places.json, built from the Atlas data at build time).
struct WidgetPlace: Codable, Hashable {
    let id: String
    let name: String
    let `where`: String
    let kind: String
    let climate: String
    let gst: Int?
    var gst_c: Int? = nil   // the same in Celsius; the widget follows the device's region, as it cannot see the app's choice
    let grape: String?

    static let all: [WidgetPlace] = {
        guard let url = Bundle.main.url(forResource: "widget-places", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([WidgetPlace].self, from: data) else { return [] }
        return list
    }()

    static let sample = WidgetPlace(id: "france/romanee-conti", name: "Romanée-Conti", where: "Côte de Nuits, France", kind: "PDO", climate: "Cool", gst: 59, gst_c: 15, grape: "Pinot Noir")

    /// The same place all day, a new one each day.
    static func ofTheDay(_ date: Date) -> WidgetPlace {
        let list = all
        guard !list.isEmpty else { return sample }
        let day = Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: date) ?? 0
        return list[(day &* 2_654_435_761 % list.count + list.count) % list.count]
    }
}

struct PlaceEntry: TimelineEntry {
    let date: Date
    let place: WidgetPlace
}

struct PlaceProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceEntry { PlaceEntry(date: .now, place: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (PlaceEntry) -> Void) { completion(PlaceEntry(date: .now, place: .ofTheDay(.now))) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceEntry>) -> Void) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let entries = (0..<7).map { d -> PlaceEntry in
            let day = cal.date(byAdding: .day, value: d, to: start)!
            return PlaceEntry(date: day, place: .ofTheDay(day))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private extension Color {
    static let atlasGold = Color(red: 0xC9 / 255, green: 0x8F / 255, blue: 0x22 / 255)
    static let atlasTeal = Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0x73 / 255)
}

struct PlaceWidgetView: View {
    let entry: PlaceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let p = entry.place
        Group {
            switch family {
            case .accessoryInline:
                Text("\(p.name) · \(p.climate)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("PLACE OF THE DAY").font(.system(size: 10, weight: .heavy))
                    Text(p.name).font(.headline).lineLimit(1)
                    Text([p.climate, p.grape].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).lineLimit(1)
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe.europe.africa.fill").foregroundStyle(Color.atlasGold)
                        Text("PLACE OF THE DAY").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(p.name).font(.system(size: family == .systemSmall ? 20 : 24, weight: .heavy)).minimumScaleFactor(0.6).lineLimit(2)
                    Text(p.where).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if family != .systemSmall { Spacer(minLength: 0) }
                    HStack(spacing: 10) {
                        if let g = p.gst { fact(Locale.current.measurementSystem == .us ? "\(g)°F" : "\(p.gst_c ?? Int((Double(g - 32) * 5 / 9).rounded()))°C", p.climate) }
                        if let grape = p.grape { fact(grape, "Main grape") }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "atlas://place/\(p.id)"))
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct PlaceOfTheDay: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PlaceOfTheDay", provider: PlaceProvider()) { PlaceWidgetView(entry: $0) }
            .configurationDisplayName("Place of the day")
            .description("A Benchmark wine region each day, with its climate and main grape.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct AtlasWidgets: WidgetBundle {
    var body: some Widget { PlaceOfTheDay() }
}
