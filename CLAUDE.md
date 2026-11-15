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
- **Colors are the same tokens.** `ios/AppellationAtlas/UI/Theme.swift` matches `web/atlas.css`, light and dark.
- App-only extras, by Chris's choice: Where am I, saved places with notes (iCloud), the place-of-the-day widget.
