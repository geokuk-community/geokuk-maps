# GeoKuk Maps

Offline map layers for [GeoKuk](https://github.com/geokuk-community/geokuk), generated automatically
by GitHub Actions. Each layer belongs to one base map from
[download.mapsforge.org](https://download.mapsforge.org/maps/v5/) and uses the same name and region.

The layers are ordinary Mapsforge files, so other Mapsforge-based apps can use them too.

## Layers

| Layer | File | Content |
|---|---|---|
| Tourist | `<region>.tourist.map` | Marked hiking, cycling, ski and horse routes, including Czech/Slovak trail colours and the names of official hiking routes; rocks, crosses, guideposts, information boards, viewpoints, solitary trees, ridges, mines, bunkers, fords, weirs, hunting stands, shelters, path difficulty (`sac_scale`, `mtb:scale`, `trail_visibility`, `incline`) and other outdoor features that the base maps do not contain |
| Contours | `<region>.contours.map` | Contour lines |
| Elevation | `<region>.dem.zip` | Elevation tiles (`.hgt`, 1 arc-second) for hillshading |

`<region>` is the path of the base map on download.mapsforge.org without the extension, for example:

    europe/czech-republic.map            (base map, from mapsforge)
    europe/czech-republic.tourist.map
    europe/czech-republic.contours.map
    europe/czech-republic.dem.zip

Base maps are not hosted here. Download them from download.mapsforge.org or its mirrors.

## How GeoKuk draws the layers

GeoKuk draws an offline map with its built-in **GeoKuk** theme: a clear outdoor map for orientation
in the terrain, designed for these layers. In **Maps → Map management** a layer is downloaded next to
its base map, and GeoKuk then draws the base map and all of its downloaded layers together, without
further settings.

![Krkonoše at zoom 13: base map, tourist layer, contour lines and hillshading](docs/krkonose-z13.png)

![Krkonoše at zoom 15: names of official hiking routes, guideposts, rocks and contour lines every 10 m](docs/krkonose-z15.png)

Map data © OpenStreetMap contributors, elevation data and contours Zdroj: ČÚZK.

The screenshots show GeoKuk offline maps made from OpenStreetMap data: the base map with GeoKuk's own
layers (tourist, contour lines and hillshading) in GeoKuk's own look (the GeoKuk theme).

What the theme draws from the layers:

| Layer | In the GeoKuk theme |
|---|---|
| Tourist | Marked hiking routes in their trail colours, cycling and MTB routes, names of official hiking routes along the line (from zoom 15); viewpoints (from zoom 13), waterfalls, rocks and stones (from zoom 14), cliffs, guideposts, wayside crosses and shrines (from zoom 15) |
| Contours | Contour lines every 100 m from zoom 12, every 50 m from zoom 13, every 10 m from zoom 15, elevation labels from zoom 17 |
| Elevation | Hillshading from zoom 9 to 17 |

The tourist layer carries more features than the GeoKuk theme draws (ski and horse routes, information boards,
solitary trees, hunting stands, shelters, path difficulty and others). Other Mapsforge themes can use them.

## Download

Each generation is published as a release tagged `layers-YYYY-MM`. Asset names use `_` instead of `/`,
for example `europe_germany_bayern.tourist.map`.

The catalogue of all files, with sizes, SHA-256 checksums and dates, is always available at:

    https://github.com/geokuk-community/geokuk-maps/releases/latest/download/layers.json

GeoKuk downloads layers through **Maps → Map management** and stores them in its `layers/` folder,
using the same folder structure as the base maps.

## Sources and licences

**Tourist** – © OpenStreetMap contributors, data available under the
[Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/).
Extracts from [Geofabrik](https://download.geofabrik.de/).

**Czech Republic elevation data and contours** – Zdroj: ČÚZK, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) (Digital Terrain Model of the Czech Republic 4th generation, DMR 4G), completed from Copernicus outside the country.

**Contours and elevation data** – produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014
and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union
and ESA; all rights reserved.

The organisations in charge of the Copernicus programme by law or by delegation do not incur any
liability for any use of the Copernicus WorldDEM-30.

Anyone who redistributes these files must keep the attributions above and is bound by the same
conditions ([COP-DEM-GLO-30-F licence](https://spacedata.copernicus.eu/documents/20123/121286/CSCDA_ESA_Mission-specific+Annex_31_Oct_22.pdf)).
This project is not endorsed by ESA, the European Union, DLR or Airbus.

**Tools** – [osmium-tool](https://osmcode.org/osmium-tool/),
[mapsforge-map-writer](https://github.com/mapsforge/mapsforge) (LGPL-3.0),
[pyhgtmap](https://github.com/agrenott/pyhgtmap), addfmreltags (GPL-3.0-or-later, modified;
source in this repository).

The scripts and workflows in this repository are licensed under GPL-3.0-or-later, like GeoKuk.

## Česky

Vrstvy k offline mapám programu GeoKuk: turistické a cyklotrasy s body pro orientaci v terénu, vrstevnice a výšková data pro
stínování terénu. Každá vrstva patří k jedné mapě z download.mapsforge.org a má stejný název.
GeoKuk je stahuje sám v okně **Mapy → Správa map**. Ručně stažené soubory patří do složky `layers/`
se stejnou strukturou podsložek, jakou mají mapy. GeoKuk je kreslí vestavěným tématem **GeoKuk**
(přehledná turistická mapa): značené trasy v barvách značení s názvy oficiálních tras, skály,
vyhlídky, rozcestníky, kříže, vodopády, vrstevnice po 10 m a stínování terénu.
