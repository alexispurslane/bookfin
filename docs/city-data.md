# Offline city data

## Provenance and license

Bookfin bundles a reduced GeoNames extract. GeoNames supplies the source data under Creative Commons Attribution 4.0 International, or CC BY 4.0.
GeoNames does not endorse Bookfin. The data comes without a warranty of accuracy, timeliness or completeness.
The app includes attribution in `assets/cities/NOTICE.txt` and the complete license in `assets/cities/CC-BY-4.0.txt`.
Both texts are also registered with Flutter's application license registry.

Sources were retrieved on November 1, 2026, in America/New_York. These live URLs change. The hashes identify this exact source snapshot.

| Source | URL | SHA-256 |
| --- | --- | --- |
| Populated places | https://download.geonames.org/export/dump/cities15000.zip | `1d1a86cc57a641387453beae0a0f89a59cbea636143fccb17368580df23776eb` |
| First-level regions | https://download.geonames.org/export/dump/admin1CodesASCII.txt | `42458864faa9887933d75c33408d4a808b765edbcd62a1328fa9e8cfcdfc718e` |
| Countries | https://download.geonames.org/export/dump/countryInfo.txt | `79f8f59ea01cbb40438bf1856dd6c2ff201f03f8fc72d0530b2646aaf603ef04` |
| Format and license description | https://download.geonames.org/export/dump/readme.txt | See GeoNames for current extract definitions |

The licensor's site is https://www.geonames.org/. The license is https://creativecommons.org/licenses/by/4.0/.

## Coverage and changes

The snapshot includes 34,195 populated places across 244 country/territory codes.
GeoNames describes cities15000 as places over 15,000 people or capitals. Its extract also includes some smaller places and subdivisions.
The list is not a complete set of villages or neighborhoods. Source population figures vary in age.
Coordinates identify each place, not the user's exact position. Selecting a nearby city gives approximate local sunrise and sunset.
City boundaries, elevation, terrain and weather are not part of the calculation.

Bookfin retains identifiers, names, ASCII spellings, region names, country names, country codes, coordinates and population.
It joins first-level region and country names, removes redundant ASCII spellings, and sorts records by numeric GeoNames identifier.
Coordinates are not changed. GeoNames alternate-name lists, time zones and administrative codes are not bundled.
The app derives sunlight from the instant and coordinates, so city time zones are unnecessary.
Search is case-insensitive across retained names and ASCII spellings. It does not provide fuzzy matching or every translated city name.

105 places lack a first-level region in the joined extract. Their labels show city and country.
116 city/region/country labels each name multiple places, covering 236 records.
For those records, the app adds the stable numeric GeoNames identifier to the label. Coordinates remain distinct.

`assets/cities/cities.tsv` is 2,395,206 bytes before APK compression.
Its SHA-256 is `16460f410475fb086a426597e33d326bdf9ad20fea965c4b93fc02e0db3df769`.
TSV means tab-separated values. Each line has these ten columns:

| Column | Value |
| --- | --- |
| 1 | Positive unique GeoNames numeric identifier |
| 2 | City name |
| 3 | ASCII city spelling, empty if identical to column 2 |
| 4 | First-level region name, empty if unavailable |
| 5 | ASCII region spelling, empty if identical to column 4 or unavailable |
| 6 | English country/territory name |
| 7 | Two-letter uppercase country/territory code |
| 8 | Latitude in degrees north of the equator, from -90 to 90 |
| 9 | Longitude in degrees east of Greenwich, from -180 to 180 |
| 10 | Nonnegative reported population, used only to order search results |

The parser rejects an empty extract, malformed rows, duplicate identifiers, empty city/country names, invalid country codes, invalid coordinates and negative populations.
The complete bundled catalog is parsed in application tests. Those tests also exercise cities across six continents and distinguish duplicate labels.

## Updating the snapshot

Updates are deliberate repository changes. The app never downloads city data at runtime.
Download all three source files into one temporary directory and unzip cities15000 there.
Record the download date and source SHA-256 hashes before replacing the asset.
From the project root, run the generator through the pinned development shell:

```sh
nix develop --command dart run tool/prepare_cities.dart /path/to/extracts > /tmp/cities.tsv
```

The generator needs `cities15000.txt`, `admin1CodesASCII.txt`, and `countryInfo.txt` in that directory.
Review the generated file, then replace `assets/cities/cities.tsv` with it.
Update attribution, coverage counts, hashes and this document with the new snapshot.
Run the full application tests and inspect the production search on Android before shipping an update.
Do not regenerate the snapshot merely to rebuild the application. The committed asset is the build input.
