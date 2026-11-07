package Plugins::DKRadio::Menu;

# Pure logic. Must not import any Slim:: module so it stays testable outside LMS.

use strict;
use warnings;
use utf8;
use JSON::PP ();

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
	return cleanUrl($best->{url});
}

# Remove Low-Latency HLS delta-playlist directives that simple HLS clients can't handle.
sub cleanUrl {
	my ($url) = @_;
	$url =~ s/([?&])_HLS_skip=[^&]*(&|$)/$2 ? $1 : ''/e;
	return $url;
}

sub normalizeStation {
	my ($p) = @_;
	return undef unless $p && ref $p eq 'HASH';
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

# Takes raw response bytes or string. Returns { total => N, stations => [...] } or undef.
sub parseResponse {
	my ($bytes) = @_;
	return undef unless defined $bytes;
	my $data = eval { JSON::PP::decode_json($bytes) };
	return undef unless ref $data eq 'HASH' && ref $data->{playables} eq 'ARRAY';
	return {
		total    => $data->{totalCount} || 0,
		stations => [ grep { defined } map { normalizeStation($_) } @{ $data->{playables} } ],
	};
}

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

1;
