# DKRadio Lyrion Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Lyrion Music Server (LMS) plugin listing all Danish radio stations from radio.dk, browsable as All / Region / Genre / DR.

**Architecture:** `Slim::Plugin::OPMLBased` plugin. `Menu.pm` is pure Perl (no `Slim::` imports) and holds all parsing, stream selection, grouping and menu building, so it is unit-testable outside LMS. `API.pm` does async HTTP + caching via LMS APIs. `Plugin.pm` wires them together. The full menu tree is built eagerly (≈234 stations).

**Tech Stack:** Perl 5 (LMS 8+), JSON::PP, Test::More/prove, zip + sha1sum for packaging.

Spec: `docs/superpowers/specs/2026-11-07-dkradio-lyrion-plugin-design.md`

---

## File structure

```
DKRadio/                         (repo root)
├── Plugins/DKRadio/             (plugin source; zipped as-is at zip root)
│   ├── Plugin.pm                LMS entry point, feed handler
│   ├── API.pm                   fetch + paging + cache (LMS-dependent)
│   ├── Menu.pm                  pure logic: parse, normalize, select stream, group, build menus
│   ├── install.xml              plugin metadata
│   └── strings.txt              DA/EN strings
├── t/
│   ├── data/denmark.json        saved real API response (fixture)
│   ├── 01-stream.t              stream selection
│   ├── 02-parse.t               parse + normalize + filtering
│   └── 03-menu.t                sorting, region/genre/DR grouping, top menu
├── build.sh                     builds dist/DKRadio-<ver>.zip + dist/repo.xml
└── docs/superpowers/...
```

Run all tests from repo root with: `prove -I. t/`

Normalized station hash (used everywhere after parsing):

```perl
{ id => 'drp1', name => 'DR P1', url => 'https://...', image => 'https://...300...',
  genres => ['News', 'Talk'], city => 'København', region => 'Hovedstaden' }  # region = API regionTag name, '' if none
```

---

### Task 0: Repo setup and fixture

**Files:**
- Create: `t/data/denmark.json`, `.gitignore`

- [ ] **Step 1: Init git and directories**

```bash
cd /home/ksn/git-ksn/DKRadio
git init
mkdir -p Plugins/DKRadio t/data dist
printf 'dist/\n' > .gitignore
```

- [ ] **Step 2: Save the real API response as fixture**

```bash
curl -s -A 'Mozilla/5.0' 'https://prod.radio-api.net/stations/by-tag?tagType=countries&slug=denmark&count=250&offset=0' -o t/data/denmark.json
perl -MJSON::PP -e 'local $/; open my $f,"<","t/data/denmark.json"; my $d=decode_json(<$f>); printf "%d %d\n",$d->{totalCount},scalar @{$d->{playables}}'
```

Expected: two equal numbers around `234 234`.

- [ ] **Step 3: Commit**

```bash
git add .gitignore t/data/denmark.json docs
git commit -m "chore: init repo with spec, plan and API fixture"
```

---

### Task 1: Stream selection

**Files:**
- Create: `Plugins/DKRadio/Menu.pm`
- Test: `t/01-stream.t`

- [ ] **Step 1: Write the failing test**

`t/01-stream.t`:

```perl
use strict; use warnings;
use Test::More;
use Plugins::DKRadio::Menu;

my $sel = \&Plugins::DKRadio::Menu::selectStream;

is($sel([]), undef, 'no streams -> undef');

is($sel([{ url => 'http://a', contentFormat => 'audio/mpeg', status => 'BROKEN' }]),
   undef, 'only invalid -> undef');

is($sel([{ url => 'http://a', contentFormat => 'audio/mpeg', status => 'VALID' }]),
   'http://a', 'single valid');

is($sel([
    { url => 'https://x/mp3-192/', contentFormat => 'audio/mpeg', status => 'VALID' },
    { url => 'https://x/aac-64/',  contentFormat => 'audio/aac',  status => 'VALID' },
]), 'https://x/aac-64/', 'AAC preferred over MP3');

is($sel([
    { url => 'https://x/mp3-128/', contentFormat => 'audio/mpeg', status => 'VALID' },
    { url => 'https://x/mp3-192/', contentFormat => 'audio/mpeg', status => 'VALID' },
]), 'https://x/mp3-192/', 'higher bitrate wins within format');

is($sel([
    { url => 'https://x/Party128web', contentFormat => 'audio/mpeg', status => 'VALID' },
    { url => 'https://x/live',        contentFormat => 'audio/mpeg', status => 'VALID' },
]), 'https://x/Party128web', 'known bitrate beats unknown');

is($sel([
    { url => 'https://x/one', contentFormat => 'audio/mpeg', status => 'VALID' },
    { url => 'https://x/two', contentFormat => 'audio/mpeg', status => 'VALID' },
]), 'https://x/one', 'tie -> first');

is(Plugins::DKRadio::Menu::bitrateFromUrl('https://drliveradio2.akamaized.net/hls/live/2118698/p1/playlist-320000.m3u8'),
   0, 'long digit runs are not bitrates');

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `prove -I. t/01-stream.t`
Expected: FAIL, `Can't locate Plugins/DKRadio/Menu.pm`.

- [ ] **Step 3: Implement**

`Plugins/DKRadio/Menu.pm`:

```perl
package Plugins::DKRadio::Menu;

# Pure logic. Must not import any Slim:: module so it stays testable outside LMS.

use strict;
use warnings;
use utf8;

my %FORMAT_RANK = ('audio/aac' => 2, 'audio/aacp' => 2, 'audio/mpeg' => 1, 'audio/mp3' => 1);

sub bitrateFromUrl {
	my ($url) = @_;
	return $1 if $url =~ /(?<!\d)(32|48|56|64|96|128|160|192|256|320)(?!\d)/;
	return 0;
}

sub selectStream {
	my ($streams) = @_;
	my @valid = grep { ($_->{status} || '') eq 'VALID' && $_->{url} } @{ $streams || [] };
	return undef unless @valid;

	my ($best, $bestKey);
	for my $s (@valid) {
		my $key = ($FORMAT_RANK{ $s->{contentFormat} || '' } || 0) * 1000 + bitrateFromUrl($s->{url});
		if (!defined $bestKey || $key > $bestKey) {
			($best, $bestKey) = ($s, $key);
		}
	}
	return $best->{url};
}

1;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `prove -I. t/01-stream.t`
Expected: `All tests successful.`

- [ ] **Step 5: Commit**

```bash
git add Plugins/DKRadio/Menu.pm t/01-stream.t
git commit -m "feat: stream selection (AAC first, highest bitrate)"
```

---

### Task 2: Parse and normalize API response

**Files:**
- Modify: `Plugins/DKRadio/Menu.pm`
- Test: `t/02-parse.t`

- [ ] **Step 1: Write the failing test**

`t/02-parse.t`:

```perl
use strict; use warnings; use utf8;
use Test::More;
use Plugins::DKRadio::Menu;

my $parse = \&Plugins::DKRadio::Menu::parseResponse;

is($parse('not json'), undef, 'bad JSON -> undef');
is($parse('{"foo":1}'), undef, 'missing playables -> undef');

my $json = '{"totalCount":3,"playables":['
  . '{"id":"a","name":"DR P4 Midt ","hasValidStreams":true,"streams":[{"url":"http://a","contentFormat":"audio/mpeg","status":"VALID"}],'
  .   '"logo300x300":"http://img/a","genreTags":[{"name":"News"}],"city":"Holstebro","regionTag":{"name":"Central Jutland"}},'
  . '{"id":"b","name":"Dead","hasValidStreams":false,"streams":[{"url":"http://b","contentFormat":"audio/mpeg","status":"VALID"}]},'
  . '{"id":"c","name":"NoValid","hasValidStreams":true,"streams":[{"url":"http://c","contentFormat":"audio/mpeg","status":"BROKEN"}]}'
  . ']}';

my $page = $parse($json);
is($page->{total}, 3, 'total from totalCount');
is(scalar @{ $page->{stations} }, 1, 'invalid stations filtered');
is_deeply($page->{stations}[0], {
	id => 'a', name => 'DR P4 Midt', url => 'http://a', image => 'http://img/a',
	genres => ['News'], city => 'Holstebro', region => 'Central Jutland',
}, 'normalized station (name trimmed)');

# Real fixture
open my $fh, '<:raw', 't/data/denmark.json' or die $!;
my $real = $parse(do { local $/; <$fh> });
ok($real->{total} >= 200, 'fixture total plausible');
ok(@{ $real->{stations} } >= 200, 'fixture stations parsed');
ok((grep { $_->{name} eq 'DR P1' } @{ $real->{stations} }), 'DR P1 present');
ok(!(grep { !$_->{url} } @{ $real->{stations} }), 'every station has a url');
ok((grep { $_->{name} =~ /ø/ } @{ $real->{stations} }), 'UTF-8 decoded into characters');

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `prove -I. t/02-parse.t`
Expected: FAIL, `Undefined subroutine &Plugins::DKRadio::Menu::parseResponse`.

- [ ] **Step 3: Implement** — add to `Menu.pm` (after `use warnings; use utf8;` add `use JSON::PP ();`; add subs before `1;`):

```perl
use JSON::PP ();

sub normalizeStation {
	my ($p) = @_;
	return undef unless $p->{hasValidStreams};
	my $url = selectStream($p->{streams});
	return undef unless $url;

	(my $name = $p->{name} // '') =~ s/^\s+|\s+$//g;
	return {
		id     => $p->{id},
		name   => $name,
		url    => $url,
		image  => $p->{logo300x300} || $p->{logo175x175} || '',
		genres => [ map { $_->{name} } grep { $_->{name} } @{ $p->{genreTags} || [] } ],
		city   => $p->{city} // '',
		region => ($p->{regionTag} && $p->{regionTag}{name}) || $p->{region} || '',
	};
}

# Takes raw response bytes. Returns { total => N, stations => [...] } or undef.
sub parseResponse {
	my ($bytes) = @_;
	my $data = eval { JSON::PP::decode_json($bytes) };
	return undef unless ref $data eq 'HASH' && ref $data->{playables} eq 'ARRAY';
	return {
		total    => $data->{totalCount} || 0,
		stations => [ grep { defined } map { normalizeStation($_) } @{ $data->{playables} } ],
	};
}
```

- [ ] **Step 4: Run tests**

Run: `prove -I. t/`
Expected: `All tests successful.`

- [ ] **Step 5: Commit**

```bash
git add Plugins/DKRadio/Menu.pm t/02-parse.t
git commit -m "feat: parse and normalize radio-api response"
```

---

### Task 3: Sorting, grouping and menu tree

**Files:**
- Modify: `Plugins/DKRadio/Menu.pm`
- Test: `t/03-menu.t`

Labels come in through a `$str` coderef (`$str->('PLUGIN_DKRADIO_ALL')`) so `Menu.pm` stays free of `Slim::Utils::Strings`. Tests pass `sub { $_[0] }`.

- [ ] **Step 1: Write the failing test**

`t/03-menu.t`:

```perl
use strict; use warnings; use utf8;
use Test::More;
use Plugins::DKRadio::Menu;

my $M = 'Plugins::DKRadio::Menu';
sub st { my %a = @_; return { id => $a{name}, url => "http://$a{name}", image => '', genres => [], city => '', region => '', %a } }

# Danish sorting
is_deeply([ map { $_->{name} } @{ $M->can('sortStations')->([ map { st(name => $_) } qw(Åbo ærø Zulu alfa Øst) ]) } ],
	[qw(alfa Zulu ærø Øst Åbo)], 'Danish collation: Æ Ø Å after Z, case-insensitive');

# Region mapping
my $r = $M->can('danishRegion');
is($r->('Southern Denmark'), 'Syddanmark');
is($r->('Zealand'),          'Sjælland');
is($r->('North Zealand'),    'Hovedstaden');
is($r->('Frederiksberg'),    'Hovedstaden');
is($r->('Central Jutland'),  'Midtjylland');
is($r->('North Jutland'),    'Nordjylland');
is($r->('Hovedstaden'),      'Hovedstaden');
is($r->('Mitrovica'),        undef, 'unknown region -> undef');
is($r->(''),                 undef);

my @stations = (
	st(name => 'DR P1', region => 'Hovedstaden', genres => ['News']),
	st(name => 'Nova',  region => 'Zealand',     genres => ['Pop', 'Rock']),
	st(name => 'Ukendt'),
);
my $str = sub { $_[0] };
my $top = $M->can('topMenu')->(\@stations, $str);

is_deeply([ map { $_->{name} } @$top ],
	[qw(PLUGIN_DKRADIO_ALL PLUGIN_DKRADIO_REGION PLUGIN_DKRADIO_GENRE PLUGIN_DKRADIO_DR)], 'top menu');

my ($all, $region, $genre, $dr) = @$top;
is(scalar @{ $all->{items} }, 3, 'all stations');
is_deeply($all->{items}[0], { name => 'DR P1', type => 'audio', url => 'http://DR P1', image => '', line2 => 'News', on_select => 'play' }, 'station item shape');

is_deeply([ map { $_->{name} } @{ $region->{items} } ],
	['Hovedstaden', 'Sjælland', 'PLUGIN_DKRADIO_OTHER'], 'regions in fixed order, empty ones hidden, other last');
is_deeply([ map { $_->{name} } @{ $region->{items}[1]{items} } ], ['Nova'], 'Zealand -> Sjælland');

is_deeply([ map { $_->{name} } @{ $genre->{items} } ],
	['News', 'Pop', 'Rock', 'PLUGIN_DKRADIO_OTHER'], 'genres sorted, other last');
is_deeply([ map { $_->{name} } @{ $genre->{items}[2]{items} } ], ['Nova'], 'station in each of its genres');

is_deeply([ map { $_->{name} } @{ $dr->{items} } ], ['DR P1'], 'DR folder');

# Real fixture sanity
open my $fh, '<:raw', 't/data/denmark.json' or die $!;
my $page = $M->can('parseResponse')->(do { local $/; <$fh> });
my $realTop = $M->can('topMenu')->($page->{stations}, $str);
ok(@{ $realTop->[3]{items} } >= 20, 'fixture has 20+ DR stations');

done_testing;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `prove -I. t/03-menu.t`
Expected: FAIL, undefined `sortStations`.

- [ ] **Step 3: Implement** — add to `Menu.pm` before `1;`:

```perl
my %REGION_MAP = (
	'Hovedstaden'      => 'Hovedstaden',
	'Capital Region'   => 'Hovedstaden',
	'North Zealand'    => 'Hovedstaden',
	'Frederiksberg'    => 'Hovedstaden',
	'Zealand'          => 'Sjælland',
	'Southern Denmark' => 'Syddanmark',
	'Central Jutland'  => 'Midtjylland',
	'North Jutland'    => 'Nordjylland',
);
my @REGION_ORDER = ('Hovedstaden', 'Sjælland', 'Syddanmark', 'Midtjylland', 'Nordjylland');

sub danishRegion {
	my ($apiRegion) = @_;
	return $REGION_MAP{ $apiRegion // '' };
}

# Sort key: lowercase, then push æ/ø/å after z ({ | } follow z in ASCII).
sub _sortKey {
	my $k = lc($_[0] // '');
	$k =~ tr/æøå/{|}/;
	return $k;
}

sub sortStations {
	my ($stations) = @_;
	return [ sort { _sortKey($a->{name}) cmp _sortKey($b->{name}) } @$stations ];
}

sub stationItem {
	my ($s) = @_;
	return {
		name      => $s->{name},
		type      => 'audio',
		url       => $s->{url},
		image     => $s->{image},
		line2     => join(' · ', grep { length } (join(', ', @{ $s->{genres} }), $s->{city})),
		on_select => 'play',
	};
}

sub _folder {
	my ($name, $stations) = @_;
	return { name => $name, type => 'link', items => [ map { stationItem($_) } @{ sortStations($stations) } ] };
}

sub topMenu {
	my ($stations, $str) = @_;
	my $other = $str->('PLUGIN_DKRADIO_OTHER');

	my (%byRegion, @noRegion, %byGenre, @noGenre, @dr);
	for my $s (@$stations) {
		my $reg = danishRegion($s->{region});
		if ($reg) { push @{ $byRegion{$reg} }, $s } else { push @noRegion, $s }

		if (@{ $s->{genres} }) { push @{ $byGenre{$_} }, $s for @{ $s->{genres} } }
		else                   { push @noGenre, $s }

		push @dr, $s if $s->{name} =~ /^DR\s/;
	}

	my @regionFolders = map { _folder($_, $byRegion{$_}) } grep { $byRegion{$_} } @REGION_ORDER;
	push @regionFolders, _folder($other, \@noRegion) if @noRegion;

	my @genreFolders = map { _folder($_, $byGenre{$_}) } sort { _sortKey($a) cmp _sortKey($b) } keys %byGenre;
	push @genreFolders, _folder($other, \@noGenre) if @noGenre;

	return [
		_folder($str->('PLUGIN_DKRADIO_ALL'), $stations),
		{ name => $str->('PLUGIN_DKRADIO_REGION'), type => 'link', items => \@regionFolders },
		{ name => $str->('PLUGIN_DKRADIO_GENRE'),  type => 'link', items => \@genreFolders },
		_folder($str->('PLUGIN_DKRADIO_DR'), \@dr),
	];
}
```

Note: `line2` for the test station `DR P1` with genres `['News']` and city `''` is `'News'` (empty parts dropped), matching the test.

- [ ] **Step 4: Run tests**

Run: `prove -I. t/`
Expected: `All tests successful.`

- [ ] **Step 5: Commit**

```bash
git add Plugins/DKRadio/Menu.pm t/03-menu.t
git commit -m "feat: Danish sorting, region/genre/DR grouping, menu tree"
```

---

### Task 4: API module (fetch, paging, cache)

**Files:**
- Create: `Plugins/DKRadio/API.pm`

LMS-dependent; verified by `perl -c` against an LMS checkout is not available here, so verify syntax with stub modules, then manually in Task 7.

- [ ] **Step 1: Implement**

`Plugins/DKRadio/API.pm`:

```perl
package Plugins::DKRadio::API;

use strict;
use warnings;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::Log;

use Plugins::DKRadio::Menu;

use constant URL       => 'https://prod.radio-api.net/stations/by-tag?tagType=countries&slug=denmark&count=%d&offset=%d';
use constant PAGE_SIZE => 250;
use constant FRESH_FOR => 24 * 3600;
use constant KEEP_FOR  => '30 days';

# Logger resolved lazily: Plugin.pm registers the category after this module is compiled.
sub _log { logger('plugin.dkradio') }
my $cache = Slim::Utils::Cache->new;

# $cb->($stations) — arrayref of normalized stations, or undef if nothing is available.
sub getStations {
	my ($class, $cb) = @_;

	my $stale = $cache->get('dkradio_stations');
	return $cb->($stale) if $stale && $cache->get('dkradio_fresh');

	_fetchPage(0, [], sub {
		my ($list) = @_;
		if ($list && @$list) {
			$cache->set('dkradio_stations', $list, KEEP_FOR);
			$cache->set('dkradio_fresh', 1, FRESH_FOR);
			return $cb->($list);
		}
		_log()->warn('Station fetch failed; ' . ($stale ? 'using stale cache' : 'no cache available'));
		$cb->($stale);
	});
}

sub _fetchPage {
	my ($offset, $acc, $done) = @_;

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $http = shift;
			my $page = Plugins::DKRadio::Menu::parseResponse($http->content);
			return $done->(undef) unless $page;

			push @$acc, @{ $page->{stations} };
			my $next = $offset + PAGE_SIZE;
			if ($next < $page->{total}) {
				_fetchPage($next, $acc, $done);
			} else {
				$done->($acc);
			}
		},
		sub {
			my ($http, $error) = @_;
			_log()->warn("radio-api request failed: $error");
			$done->(undef);
		},
		{ timeout => 30 },
	)->get(sprintf(URL, PAGE_SIZE, $offset));
}

1;
```

Paging note: the loop stops on `$next >= total`, and since filtered-out stations still count in `total`, a short page is never mistaken for "more to come".

- [ ] **Step 2: Syntax check with stubs**

```bash
mkdir -p /tmp/lmsstub/Slim/Networking /tmp/lmsstub/Slim/Utils
printf 'package Slim::Networking::SimpleAsyncHTTP; sub new{bless{},shift} sub get{} 1;\n' > /tmp/lmsstub/Slim/Networking/SimpleAsyncHTTP.pm
printf 'package Slim::Utils::Cache; sub new{bless{},shift} sub get{} sub set{} 1;\n' > /tmp/lmsstub/Slim/Utils/Cache.pm
printf 'package Slim::Utils::Log; use Exporter "import"; our @EXPORT=qw(logger); sub logger{bless{},"Slim::Utils::Log"} sub warn{} 1;\n' > /tmp/lmsstub/Slim/Utils/Log.pm
perl -I/tmp/lmsstub -I. -c Plugins/DKRadio/API.pm
```

Expected: `Plugins/DKRadio/API.pm syntax OK`

- [ ] **Step 3: Commit**

```bash
git add Plugins/DKRadio/API.pm
git commit -m "feat: async station fetch with paging and 24h cache"
```

---

### Task 5: Plugin entry point, metadata, strings

**Files:**
- Create: `Plugins/DKRadio/Plugin.pm`, `Plugins/DKRadio/install.xml`, `Plugins/DKRadio/strings.txt`

- [ ] **Step 1: `Plugin.pm`**

```perl
package Plugins::DKRadio::Plugin;

use strict;
use warnings;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Plugins::DKRadio::API;
use Plugins::DKRadio::Menu;

my $log = Slim::Utils::Log->addLogCategory({
	category     => 'plugin.dkradio',
	defaultLevel => 'WARN',
	description  => 'PLUGIN_DKRADIO',
});

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'dkradio',
		menu   => 'radios',
		is_app => 1,
		weight => 10,
	);
}

sub getDisplayName { 'PLUGIN_DKRADIO' }

sub playerMenu { 'RADIO' }

sub handleFeed {
	my ($client, $cb, $args) = @_;

	Plugins::DKRadio::API->getStations(sub {
		my ($stations) = @_;

		unless ($stations && @$stations) {
			return $cb->({ items => [{ name => cstring($client, 'PLUGIN_DKRADIO_ERROR'), type => 'text' }] });
		}

		$cb->({ items => Plugins::DKRadio::Menu::topMenu($stations, sub { cstring($client, $_[0]) }) });
	});
}

1;
```

- [ ] **Step 2: `install.xml`**

```xml
<?xml version="1.0"?>
<extension>
	<name>PLUGIN_DKRADIO</name>
	<module>Plugins::DKRadio::Plugin</module>
	<version>0.1.0</version>
	<description>PLUGIN_DKRADIO_DESC</description>
	<creator>ksn</creator>
	<id>6f1c2d4e-8a7b-4c39-9e51-2b3d4a5f6c70</id>
	<category>radio</category>
	<defaultState>enabled</defaultState>
	<icon>https://www.radio.dk/assets/fav/apple-touch-icon.png</icon>
	<targetApplication>
		<id>SqueezeCenter</id>
		<minVersion>8.0</minVersion>
		<maxVersion>*</maxVersion>
	</targetApplication>
	<type>2</type>
</extension>
```

- [ ] **Step 3: `strings.txt`** (indent with TABs: one TAB before the language code, one TAB between code and text)

```
PLUGIN_DKRADIO
	DA	DK Radio
	EN	DK Radio

PLUGIN_DKRADIO_DESC
	DA	Alle danske radiostationer fra radio.dk
	EN	All Danish radio stations from radio.dk

PLUGIN_DKRADIO_ALL
	DA	Alle stationer
	EN	All stations

PLUGIN_DKRADIO_REGION
	DA	Region
	EN	Region

PLUGIN_DKRADIO_GENRE
	DA	Genre
	EN	Genre

PLUGIN_DKRADIO_DR
	DA	DR
	EN	DR

PLUGIN_DKRADIO_OTHER
	DA	Øvrige
	EN	Other

PLUGIN_DKRADIO_ERROR
	DA	Kunne ikke hente stationer – prøv igen senere
	EN	Could not load stations – please try again later
```

- [ ] **Step 4: Verify**

```bash
grep -cP '^\t[A-Z]{2}\t' Plugins/DKRadio/strings.txt    # expect 16
xmllint --noout Plugins/DKRadio/install.xml && echo xml ok
prove -I. t/
```

- [ ] **Step 5: Commit**

```bash
git add Plugins/DKRadio/Plugin.pm Plugins/DKRadio/install.xml Plugins/DKRadio/strings.txt
git commit -m "feat: LMS plugin entry point, metadata and strings"
```

---

### Task 6: Packaging (zip + repo.xml)

**Files:**
- Create: `build.sh`

- [ ] **Step 1: `build.sh`**

```bash
#!/usr/bin/env bash
# Usage: BASE_URL=https://example.org/dkradio ./build.sh
# Produces dist/DKRadio-<version>.zip and dist/repo.xml pointing at BASE_URL.
set -euo pipefail
cd "$(dirname "$0")"

: "${BASE_URL:?Set BASE_URL to where the zip will be hosted}"
VERSION=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' Plugins/DKRadio/install.xml)
ZIP="DKRadio-${VERSION}.zip"

prove -I. t/

rm -rf dist && mkdir dist
(cd Plugins/DKRadio && zip -qr "../../dist/${ZIP}" . -x '*.swp')
SHA=$(sha1sum "dist/${ZIP}" | cut -d' ' -f1)

cat > dist/repo.xml <<EOF
<?xml version="1.0"?>
<extensions>
	<details>
		<title lang="EN">DK Radio repository</title>
	</details>
	<plugins>
		<plugin name="DKRadio" version="${VERSION}" minTarget="8.0" maxTarget="*">
			<title lang="EN">DK Radio</title>
			<title lang="DA">DK Radio</title>
			<desc lang="EN">All Danish radio stations from radio.dk</desc>
			<desc lang="DA">Alle danske radiostationer fra radio.dk</desc>
			<creator>ksn</creator>
			<url>${BASE_URL}/${ZIP}</url>
			<sha>${SHA}</sha>
		</plugin>
	</plugins>
</extensions>
EOF

echo "Built dist/${ZIP} (sha1 ${SHA}) and dist/repo.xml"
```

- [ ] **Step 2: Run it**

```bash
chmod +x build.sh
BASE_URL=http://localhost:8000 ./build.sh
unzip -l dist/DKRadio-0.1.0.zip    # install.xml, Plugin.pm, API.pm, Menu.pm, strings.txt at zip root
xmllint --noout dist/repo.xml && echo repo ok
```

- [ ] **Step 3: Commit**

```bash
git add build.sh
git commit -m "build: zip and repo.xml packaging"
```

---

### Task 7: Install and verify on Lyrion (manual, with user)

- [ ] **Step 1: HLS check first.** On the LMS web UI, add `https://drliveradio2.akamaized.net/hls/live/2118698/p1/playlist-320000.m3u8` via *Radio → Tune in URL* and play it. Record LMS version (Settings → Information) and whether it plays. If not: note it to the user; DR stations stay listed (spec accepts this) and an HLS-capable setup is a follow-up.
- [ ] **Step 2: Host the build.** From `dist/`: `python3 -m http.server 8000` on a host reachable from LMS, rebuild with that `BASE_URL`.
- [ ] **Step 3: Install.** LMS Settings → Manage Plugins → add `<BASE_URL>/repo.xml` as additional repository → install *DK Radio* → restart LMS.
- [ ] **Step 4: Browse.** Radio → DK Radio: check *Alle stationer* (~234, Danish order), *Region* (5 regions + Øvrige), *Genre*, *DR* (25 stations).
- [ ] **Step 5: Play.** One MP3 station (e.g. Nova FM), one AAC station if any, one DR station.
- [ ] **Step 6: Failure path.** Optional: block `prod.radio-api.net` and clear cache; menu shows the error item. With a warm cache it shows the stale list.
- [ ] **Step 7: Tag**

```bash
git tag v0.1.0
```
