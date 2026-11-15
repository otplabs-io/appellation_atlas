import Foundation

// Words and scales the website writes in web/atlas.js. Keep the two in step: a change to one is a change to both.

enum Copy {
    static let worldIntro = [
        "Benchmark regions, in gold, are the ones the WSET Diploma teaches: the classic places to learn first. Emerging regions, in grey, are the rest.",
        "Stronger shades are better known: more Wikipedias write about them, and more people read those pages. Each place is compared with the places beside it, so Bordeaux is set against Burgundy and Languedoc, and France against Uruguay.",
    ]

    static func worldCount(_ n: Int) -> String { "Every wine country, region and appellation we have, \(fmt(Double(n))) places in all." }

    static let shapeNote: [String: String] = [
        "Eurostat NUTS, the area it is named for": "The map draws the department, province or region it is named for. The PGI\u{2019}s own area can differ a little.",
        "Eurostat LAU, the commune it is named for": "The map draws the commune it is named for.",
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
func inches(_ mm: Double) -> Double { mm / 25.4 }
func feet(_ m: Double) -> Double { (m * 3.281 / 10).rounded() * 10 }
func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
