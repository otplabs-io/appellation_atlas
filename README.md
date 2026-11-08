# Appellation Atlas

Spin a globe and go from a country down to a single grand cru. Each of about 2,700 wine places has its own page. It tells you what is planted there, which grapes the rules allow, what the climate is like, what rock lies underneath, how the land sits, and why all of that matters in the glass.

It is a static website. There is no database, no account and no server code. Everything the site needs is in this repository.

## Run it

The finished site is already in `public/`. Any web server will do. With Python:

```bash
python3 -m http.server 8801 --directory public
```

Then open <http://localhost:8801/>.

## Put it on the web

**Vercel:** import this repository. `vercel.json` already sets everything: no build step, `public/` as the output, plus caching and security headers.

**Anywhere else:** upload the contents of `public/` to any static host, such as GitHub Pages, Cloudflare Pages or Netlify.

## Change it

You need Python 3.13 and `make`.

```bash
make setup
```

```bash
make site
```

`make site` rebuilds every place page and rewrites `public/`. It takes about a minute and downloads nothing.

| To change | Edit | Then run |
|---|---|---|
| The page, its look or its behavior | `web/` | `make site` |
| The wine places and how they nest | `regions/tree.json` | `make site` |
| The rock types and what they do to vines | `regions/rock-types.json` | `make site` |
| Which grapes suit which climates | `regions/climate-grapes.json` | `make site` |
| Which places count as Benchmark regions | `regions/wset.json` | `make site` |

## What's in here

| Folder | What it holds |
|---|---|
| `public/` | The finished website |
| `web/` | The page itself: HTML, JavaScript, styles, fonts and icon |
| `regions/` | Every place, boundary and measurement the pages are built from |
| `research/` | Researched notes on some places, each with its sources |
| `src/` | The Python that builds the data |

## Refreshing the data

Everything in `regions/` is included, so you only need this to pull newer numbers. These steps download from the original sources and write their results back to `regions/`:

```bash
.venv/bin/python src/atlasland.py terrain
```

```bash
.venv/bin/python src/atlasland.py plots
```

```bash
.venv/bin/python src/atlasland.py rocks
```

```bash
.venv/bin/python src/notoriety.py fetch
```

```bash
.venv/bin/python src/notoriety.py build
```

Run `make site` afterward. Drawing the boundaries again (`src/atlas.py geo`) and measuring climate and soil again (`src/atlas.py climate`) need about 3.7 GB of raw files in `data/cache/`. Those are not included, because of their size and because some may not be redistributed. The sources are listed below.

## Where the data comes from

Each place page lists the sources behind it. Check each source's own terms before you reuse its data.

| Source | Used for | Terms |
|---|---|---|
| [Candiago et al. 2022](https://doi.org/10.1038/s41597-022-01778-5), EU wine PDO inventory | European boundaries and rules | CC0 |
| [UC Davis AVA Project](https://github.com/UCDavisLibrary/ava) | US boundaries | See the project |
| [Eurostat GISCO](https://ec.europa.eu/eurostat/web/gisco) | Countries and regions | See Eurostat |
| [Wine Australia](https://www.wineaustralia.com/), [IPONZ](https://www.iponz.govt.nz/) | Australian and New Zealand boundaries | See each register |
| [INAO via OpenDataWine](https://github.com/24eme/opendatawine) | French grand cru plots | Licence Ouverte |
| [Anderson, Nelgen and Puga](https://doi.org/10.25909/32870405.v1) | What is planted | CC BY 4.0 |
| [WorldClim 2.1](https://www.worldclim.org/) | Temperature and rain | Limits commercial use and redistribution. See their terms |
| [Beck et al. 2023](https://doi.org/10.1038/s41597-023-02549-6) | Climate type | See the paper |
| [ISRIC SoilGrids 2.0](https://www.isric.org/explore/soilgrids) | Soil | CC BY 4.0 |
| [Macrostrat](https://macrostrat.org/) | Rock | CC BY 4.0 |
| [AWS Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) | Elevation and slope | [Attribution list](https://github.com/tilezen/joerd/blob/master/docs/attribution.md) |
| [Wikidata and Wikimedia](https://www.wikidata.org/) | How well known each place is | See Wikimedia |
| [WSET Level 4 specification](https://www.wsetglobal.com/) | Which places are Benchmark regions | Region list only |

The fonts are Poppins and Nunito Sans, with their licenses in `web/assets/fonts/`.

The notes on how soil, slope and climate affect vines are general viticulture. They describe what usually happens, not findings about each place.

## License

The code is under the [MIT License](LICENSE). The data sources and fonts listed above keep their own terms.
