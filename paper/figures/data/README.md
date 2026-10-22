# Map data for the figures

`ne_10m_admin_0_countries_pacific.geojson` is the base map of the site map in
Figure 1(a). It holds the United States, Canada and Mexico from the Natural
Earth 1:10m Cultural Vectors theme "Admin 0 – Countries", version 5.1.1
(`ne_10m_admin_0_countries.shp`), cropped to longitude 128° W to 110° W and
latitude 30° N to 51° N, simplified with a tolerance of 0.01° (about 1 km,
narrower than a printed line at the map's scale) and written as RFC 7946
GeoJSON in WGS 84 with four decimals. Only the `NAME` and `ISO_A3` attributes
are kept. Natural Earth draws de facto boundaries and has no state outlines at
this level, so the figure labels the two regions instead.

Source: the [Natural Earth Admin 0 – Countries download page][ne-countries].
Licence: Natural Earth data are in the public domain; they may be used,
modified and redistributed without permission, as the
[Natural Earth terms of use][ne-terms] state. The figure credits the source in
its caption.

`scripts/paper_figures.R` reads this file, so the figures do not depend on a
path outside the repository. To rebuild it from the downloaded shapefile:

```sh
CLAUDE_JOB_DIR=/path/to/paper_runs Rscript scripts/paper_figures.R FIGURES=1 \
  OUT=/path/to/figures NE_COUNTRIES=/path/to/ne_10m_admin_0_countries.shp
```

The figure projects it to an Albers equal-area conic projection centred on
120° W with standard parallels at 34° N and 46° N.

[ne-countries]: https://www.naturalearthdata.com/downloads/10m-cultural-vectors/10m-admin-0-countries/
[ne-terms]: https://www.naturalearthdata.com/about/terms-of-use/
