import Foundation

// Words and scales the website writes in web/atlas.js. Keep the two in step: a change to one is a change to both.

enum Copy {
    /// A rock family's share in words: it comes from a few map points, so a percentage would claim too much (rockShare in web/atlas.js).
    static func share(_ v: Double) -> String { v >= 0.5 ? "mostly" : v >= 0.25 ? "much" : "some" }

    /// The grapes left out of what is planted because they are not wine grapes (leftOut in web/atlas.js).
    static func whitesOlder(_ year: String) -> String { "red grapes as of \(year), white grapes from an earlier survey, so the shares are approximate." }
    static func leftOut(_ left: JSON) -> String {
        func and(_ xs: [String]) -> String { xs.count > 1 ? xs.dropLast().joined(separator: ", ") + " and " + xs.last! : xs.first ?? "" }
        var out = ""
        let juice = left["juice"].strings, table = left["table"].strings
        if !juice.isEmpty { out += " Juice grapes are left out: \(and(juice))." }
        if !table.isEmpty { out += " Table grapes are left out: \(and(table))." }
        return out
    }

    /// Notes on the rules facts (COPY in web/atlas.js).
    enum Rules {
        static let baseYield = "the yield its rules set; some years a little more is allowed"
        static let yieldCeiling = "the most its rules allow in any year; the usual limit is lower"
        static let yieldLimit = "the most the 2022 EU record allows; some of its wines may have lower limits, and rules change"
        static let recognised = "the year its rules say it was first recognised, sometimes under an older name"
        static let noShares = "The 2022 EU record lists the grapes allowed, not their shares. Later changes to the rules may not be in it."
        static let noRoles = "The cahier gives these grapes different roles in different wines, so they are listed here by colour."
        static let anyName = " That is every vineyard there, whatever name its wine is sold under."
        static let limitsHead = "Planting rules: shares of each grower\u{2019}s vineyard, not of the blend"
        static let blendHead = "Blend rules: shares of the wine itself"
        static func forWine(_ w: String) -> String { "Main grapes, for \(w)" }
    }

    /// What gold and grey mean for each pill (LEVELS in atlas.js). Grey says only that a place is off the study list, never how well known it is.
    struct Level { let name, on, off, ons: String }
    static let levels: [String: Level] = [
        "b": Level(name: "Benchmarks", on: "Benchmark region", off: "Other region", ons: "Benchmark regions"),
        "d": Level(name: "All", on: "Benchmark region", off: "Other region", ons: "Benchmark regions"),
    ]
    static func level(_ l: String) -> Level { levels[l] ?? levels["d"]! }
    /// The grey group's heading under the gold one (moreIn in atlas.js).
    static func moreIn(_ vid: String, _ name: String) -> String { vid == "world" ? "Other countries" : "More in \(name)" }
    static func worldIntro(_ l: String) -> [String] { [
        (l == "d" ? "All turns gold every place inside the classic regions, down to the smallest appellation. Grey marks every other place."
            : "Benchmark regions, in gold, are the classic places to learn first. Grey marks every other place.")
        + " Switch between Benchmarks and All to choose which places are gold.",
        "Darker shades show the places with the most global interest, measured by how many Wikipedias write about them and how often those pages are read. Each map sets its own scale, so the darkest place is the best known one on that map.",
    ] }

    static let feedbackPrompt = "See something wrong or missing?"
    static let feedbackButton = "Send feedback"
    /// The feedback form with the place filled in. The app has no page link, so the link field says where it came from.
    static func feedbackURL(name: String, id: String) -> URL? {
        var c = URLComponents(string: "https://docs.google.com/forms/d/e/1FAIpQLSc7CmB3DsylFI0kt6tZncSwq53i8jsEuxdrv4deyIuWJHq8oA/viewform")
        c?.queryItems = [
            URLQueryItem(name: "usp", value: "pp_url"),
            URLQueryItem(name: "entry.673545042", value: name),
            URLQueryItem(name: "entry.612336214", value: "From the app, place id \(id)"),
        ]
        return c?.url
    }

    static let homeTitle = "Explore the world\u{2019}s wine regions"
    static func worldCount(_ n: Int) -> String {
        "\(fmt(Double(n))) wine regions, from whole countries down to single vineyards. Tap a country on the globe to begin, or search for one you know."
    }

    static let shapeNote: [String: String] = [
        "Eurostat NUTS, the area it is named for": "The map draws the department, province or region it is named for. The PGI\u{2019}s own area can differ a little.",
        "Eurostat LAU, the commune it is named for": "The map draws the commune it is named for.",
        "Eurostat LAU, the municipalities its rules name": "The map draws the municipalities its rules name.",
        "Chile Decreto 464, drawn from its comunas and provinces": "The boundary follows the comunas and provinces that Chile\u{2019}s Decreto 464 names.",
        "geoBoundaries, the department it is named for": "The map draws the department it is named for. The IG\u{2019}s own area can be smaller.",
        "geoBoundaries, the province it is named for": "The map draws the province.",
        "IPONZ GI register": "The boundary is the one on New Zealand\u{2019}s GI register.",
        "Wine Australia GI boundaries": "The boundary is Wine Australia\u{2019}s. The legal one is the written description in the register.",
        "union of its children": "There is no single boundary for it, so the map joins the places inside it.",
    ]

    static func bigNote(hasParts: Bool) -> String {
        hasParts
            ? "Too big and varied for one reading. These figures average all of it; the table further down compares the places inside."
            : "Too big and varied for one reading. These figures average all of it, hills and valleys alike."
    }

    /// Growing season classes in Celsius bounds, with the Fahrenheit range shown.
    static let growingSeason: [(String, Double, Double, String)] = [
        ("Too cool", -99, 13, "under 55°F"), ("Cool", 13, 15, "55 to 59°F"), ("Intermediate", 15, 17, "59 to 63°F"),
        ("Warm", 17, 19, "63 to 66°F"), ("Hot", 19, 24, "66 to 75°F"), ("Too hot", 24, 99, "over 75°F"),
    ]

    /// Winkler regions in Celsius degree days, with the Fahrenheit range shown.
    static let winkler: [(String, Double, Double, String)] = [
        ("Below Ia", 0, 850, "under 1,500"), ("Ia", 850, 1111, "1,500 to 2,000"), ("Ib", 1111, 1389, "2,000 to 2,500"),
        ("II", 1389, 1667, "2,500 to 3,000"), ("III", 1667, 1944, "3,000 to 3,500"), ("IV", 1944, 2222, "3,500 to 4,000"),
        ("V", 2222, 2700, "4,000 to 4,900"), ("Above V", 2700, 9999, "over 4,900"),
    ]

    /// Which segment a value falls in, and how far along it.
    static func segment(_ t: [(String, Double, Double, String)], _ v: Double) -> (Int, Double) {
        guard let i = t.firstIndex(where: { $0.1 <= v && v < $0.2 }) else { return (-1, 0) }
        let (_, lo, hi, _) = t[i]
        let a = lo < -50 ? hi - 2 : lo
        let b = hi > 90 && hi < 1000 ? lo + 2 : hi > 5000 ? lo + 400 : hi
        return (i, (v - a) / (b - a))
    }

    static let directions = ["N": "North", "NE": "Northeast", "E": "East", "SE": "Southeast", "S": "South", "SW": "Southwest", "W": "West", "NW": "Northwest"]
    static let compass = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
}

func fmt(_ n: Double?) -> String {
    guard let n else { return "" }
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    f.locale = Locale(identifier: "en_US")
    return f.string(from: NSNumber(value: n.rounded())) ?? String(Int(n.rounded()))
}

func toF(_ c: Double) -> Double { c * 9 / 5 + 32 }
func feet(_ m: Double) -> Double { (m * 3.281 / 10).rounded() * 10 }
func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
