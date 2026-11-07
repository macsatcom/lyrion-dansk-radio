# DKRadio – Lyrion plugin for all Danish radio stations

Date: 2026-11-07
Status: Design approved, awaiting spec review

## Goal

A Lyrion Music Server (LMS) plugin that exposes all Danish radio stations
listed on radio.dk, browsable by name, region, genre and a dedicated DR folder.

## Data source

- Endpoint (unofficial, used by radio.dk's own frontend):
  `GET https://prod.radio-api.net/stations/by-tag?tagType=countries&slug=denmark&count=250&offset=0`
- Verified 2026-11-07: `totalCount` 234; every playable includes `streams`.
- Response fields used per station: `id`, `name`, `hasValidStreams`, `streams[]`
  (`url`, `contentFormat`, `status`), `logo300x300`, `genreTags[].name`,
  `city`, `regionTag.name` / `region`.
- Pagination: if `totalCount > count`, fetch further pages with `offset`
  until all are loaded.

## Architecture

Pure Perl plugin built on `Slim::Plugin::OPMLBased`. No external services.

| File | Responsibility |
|---|---|
| `Plugin.pm` | Registers the plugin and the top-level menu feed (`feed => \&Menu::handleFeed`). |
| `API.pm` | Fetches stations asynchronously (`Slim::Networking::SimpleAsyncHTTP`), parses JSON, filters, caches. The only module that knows the API. |
| `Menu.pm` | Pure functions turning a station list into OPML menu structures; stream selection. |
| `install.xml` | Plugin metadata (id, version, min LMS version). |
| `strings.txt` | UI strings in DA and EN. |
| `repo.xml` + `build.sh` | Packaging: zip + SHA1 for a third-party repository. |
| `t/` | Unit tests for `Menu.pm` against a saved API fixture. |

## Data flow

1. User opens "DK Radio".
2. `Menu::handleFeed` asks `API::getStations($cb)`.
3. `API` returns the cached list if younger than 24 h; otherwise it fetches,
   stores the result in `Slim::Utils::Cache` (namespace `dkradio`), and
   returns it.
4. `Menu` builds the requested submenu and passes it to the callback.

## Filtering and stream selection

- Drop stations where `hasValidStreams` is false or no stream has `status: VALID`.
- Select the best stream among VALID streams:
  1. Prefer `audio/aac` over `audio/mpeg`/`audio/mp3`.
  2. Within the same format, the highest bitrate parsed from the URL
     (regex `(\d{2,3})(?:k|kbps)?` on segments like `mp3-192`, `aac-128`,
     `Party128web`); unknown bitrate ranks lowest.
  3. Tie: first in API order.
- Playlist URLs (PLS/M3U, e.g. KNR) are passed through unchanged; LMS resolves them.

## Menu structure

- **Alle stationer**: all stations, sorted by name using Danish collation
  (Æ, Ø, Å last; case-insensitive).
- **Region**: one folder per region (Hovedstaden, Sjælland, Syddanmark,
  Midtjylland, Nordjylland) plus "Øvrige" for stations with no or a non-Danish
  region. API region names (e.g. "Southern Denmark", "Zealand",
  "North Zealand", "Frederiksberg") are mapped to these five Danish regions
  via a fixed table in `Menu.pm`; anything unmapped goes to "Øvrige".
- **Genre**: one folder per genre from `genreTags[].name`; a station appears
  in each of its genres; folders sorted by name; stations without a genre go
  under "Øvrige".
- **DR**: stations whose name starts with `DR ` (P1–P8 and regional channels).

Each station item: `type => 'audio'`, `name`, `url` (selected stream),
`image` (`logo300x300`), `line2` (`genre · city`).

## Error handling

- Fetch fails (network, HTTP ≠ 200, bad JSON) and a cached list exists: serve
  the stale cache and log a warning.
- Fetch fails with no cache: return a single menu item with a localized
  error text ("Kunne ikke hente stationer – prøv igen senere").
- Unexpected response shape (no `playables` array): treated as a fetch failure.

## Known risks

- **HLS:** DR streams are `.m3u8` (HLS). Playback needs HLS support on the
  user's LMS. Not yet confirmed on the target server (LMS version also
  unknown). Implementation must check this early; if HLS fails, DR stations
  are still listed but will not play.
- **Unofficial API:** may change or block without notice. Mitigated by
  cache fallback and isolating all API knowledge in `API.pm`.

## Testing

- `prove t/` unit tests for `Menu.pm`, run against a saved JSON fixture of the
  real response: stream selection, filtering, region mapping, genre grouping,
  DR detection, Danish sorting.
- Manual test on the user's LMS: install via repo.xml, browse all four menus,
  play one MP3, one AAC and one DR (HLS) station.

## Out of scope

Search, favorites management (LMS core handles favorites), podcasts,
now-playing metadata, non-Danish stations.
