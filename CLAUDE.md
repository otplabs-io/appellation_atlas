# Appellation Atlas

A public website: a globe of every wine place, with what is planted there, its climate, its rock and its land.

- `public/` is the finished site and the only thing that gets deployed. Build it with `make site`.
- `web/` holds the page, `src/` the data builders, `regions/` their inputs and results, `data/cache/` the raw downloads.
- Region differences are data. Never invent facts, metrics or attributions. Every source a page uses goes in `SRC` in `src/atlas.py` and shows in that place's Sources.
- Copy: short sentences, plain and friendly, no em dashes, no "not only...but also", no corporate language.

## The iPhone and iPad app (`ios/`)

The app and the website must carry the same information and features. Keep them in step:
- **Data is shared automatically.** Xcode copies `public/places.json`, `public/geo/` and `public/facts/` into the app on every build (`ios/Config/copy-atlas-data.sh`), so run `make site` first. Every sentence built in `src/` reaches both.
- **Words and scales are mirrored by hand.** `ios/AppellationAtlas/UI/Copy.swift` holds what `web/atlas.js` writes itself: section notes, the growing season and Winkler scales, shape notes, the world intro. Change one, change the other.
- **Sections follow the same order and logic.** `ios/AppellationAtlas/UI/PlaceInfo.swift` mirrors `renderInfo` in `web/atlas.js`. A new section on one gets added to the other.
- **The globe is the same math.** `ios/AppellationAtlas/Globe/` ports the projection, clipping, culling, flights, zoom rules and labels from `web/atlas.js`.
- **Compare and units are mirrored too.** `ios/AppellationAtlas/Features/Compare.swift` mirrors `renderCompare`, `renderPairs` and `placesText` in `web/atlas.js`; `UI/Units.swift` mirrors the unit formatters. Unit figures inside place text are marked once at build time (`src/units.py`); outlines for Compare come from `src/outlines.py`; the often compared pairs live in `regions/compare-pairs.json`, and their wine text may say only what the sources listed with it say.
- **Colors are the same tokens.** `ios/AppellationAtlas/UI/Theme.swift` matches `web/atlas.css`, light and dark.
- **Design D is the layout on both.** The map fills the screen and panels float over it. The design canvas's D boards (Home, Place, Compare, Pairs, Settings, and the iPad and web boards) are the reference; match them closely. The web side is the D block at the end of `web/atlas.css`; the app's shared pieces are in `ios/AppellationAtlas/UI/DesignD.swift`. The app uses the website's own fonts (Poppins and Nunito Sans, copied from `web/assets/fonts` to `ios/AppellationAtlas/Fonts`). iPhone and an upright iPad use the sheet over the map; an iPad on its side (1150 points or wider) and a browser 1024 px or wider get a panel each side.
- App-only extras, by Chris's choice: Where am I, saved places with notes (iCloud), the place-of-the-day widget.
- **Before any App Store submission, follow `ios/RELEASE.md`.** Apple held 1.0 for a screen recording and written review notes (Guideline 2.1). Every version needs both, plus device testing of the exact archive.
