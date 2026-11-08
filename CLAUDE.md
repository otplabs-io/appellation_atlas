# Appellation Atlas

A public website: a globe of every wine place, with what is planted there, its climate, its rock and its land.

- `public/` is the finished site and the only thing that gets deployed. Build it with `make site`.
- `web/` holds the page, `src/` the data builders, `regions/` their inputs and results, `data/cache/` the raw downloads.
- Region differences are data. Never invent facts, metrics or attributions. Every source a page uses goes in `SRC` in `src/atlas.py` and shows in that place's Sources.
- Copy: short sentences, plain and friendly, no em dashes, no "not only...but also", no corporate language.
