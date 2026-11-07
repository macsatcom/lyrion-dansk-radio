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
