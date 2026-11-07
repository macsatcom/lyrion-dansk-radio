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
	return $best->{url};
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

1;
