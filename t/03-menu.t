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
