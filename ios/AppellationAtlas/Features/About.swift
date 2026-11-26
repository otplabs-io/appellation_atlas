import SwiftUI

/// Where the Atlas's data comes from, and the terms each source sets. Each place's own page lists its sources too.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Atlas.self) private var atlas

    private let sources: [(String, String, String)] = [
        ("Candiago et al. 2022, EU wine PDO inventory", "European boundaries and rules", "https://doi.org/10.1038/s41597-022-01513-0"),
        ("UC Davis AVA Project", "US boundaries", "https://github.com/UCDavisLibrary/ava"),
        ("Eurostat GISCO", "Countries and regions", "https://ec.europa.eu/eurostat/web/gisco"),
        ("Wine Australia and IPONZ", "Australian and New Zealand boundaries", "https://www.wineaustralia.com/"),
        ("INAO via OpenDataWine", "French grand cru plots", "https://github.com/24eme/opendatawine"),
        ("Anderson, Nelgen and Puga", "What is planted (CC BY 4.0)", "https://doi.org/10.25909/32870405.v1"),
        ("WorldClim 2.1", "Monthly temperatures, used with the author's permission", "https://www.worldclim.org/"),
        ("Beck et al. 2023", "Climate type", "https://doi.org/10.1038/s41597-023-02549-6"),
        ("ISRIC SoilGrids 2.0", "Soil (CC BY 4.0)", "https://www.isric.org/explore/soilgrids"),
        ("Macrostrat", "Rock (CC BY 4.0)", "https://macrostrat.org/"),
        ("AWS Terrain Tiles", "Elevation and slope", "https://registry.opendata.aws/terrain-tiles/"),
        ("Wikidata and Wikimedia", "How well known each place is", "https://www.wikidata.org/"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Every wine place in the world on one globe, with what is planted there, its climate, its rock and its land. Everything is inside the app and works with no connection.")
                        .font(.atlasBody)
                    Text("The Atlas is free to use. It is updated from time to time based on feedback from the people who use it.")
                        .font(.atlasBody)
                    LabeledContent("Places", value: fmt(Double(atlas.places.count)))
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
                Section("Open source") {
                    Text("The code is on GitHub under the MIT License. Anyone can read it, copy it, change it and run it on their own computer.")
                        .font(.atlasNote)
                    Link("github.com/otplabs-io/appellation_atlas", destination: URL(string: "https://github.com/otplabs-io/appellation_atlas")!)
                        .font(.atlasNote)
                }
                Section("Where the data comes from") {
                    ForEach(sources, id: \.0) { s in
                        Link(destination: URL(string: s.2)!) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.0).font(.subheadline.weight(.semibold))
                                Text(s.1).font(.atlasNote).foregroundStyle(Palette.soft)
                            }
                        }
                    }
                }
                Section {
                    Link("Privacy policy", destination: URL(string: "https://www.appellation-atlas.com/privacy.html")!)
                    Link("Support", destination: URL(string: "https://www.appellation-atlas.com/support.html")!)
                }
                Section {
                    Text("The notes on how soil, slope and climate affect vines are general viticulture. They describe what usually happens, not findings about each place.")
                        .font(.atlasNote).foregroundStyle(Palette.soft)
                }
            }
            .navigationTitle("About the Atlas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Opens About.
struct AboutButton: View {
    @State private var open = false
    var body: some View {
        Button { open = true } label: { Label("About the Atlas", systemImage: "info.circle") }
            .sheet(isPresented: $open) { AboutView() }
    }
}
