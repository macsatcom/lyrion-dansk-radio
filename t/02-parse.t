use strict; use warnings; use utf8;
use Test::More;
use Plugins::DKRadio::Menu;

my $parse = \&Plugins::DKRadio::Menu::parseResponse;

is($parse->('not json'), undef, 'bad JSON -> undef');
is($parse->('{"foo":1}'), undef, 'missing playables -> undef');

my $json = '{"totalCount":3,"playables":['
  . '{"id":"a","name":"DR P4 Midt ","hasValidStreams":true,"streams":[{"url":"http://a","contentFormat":"audio/mpeg","status":"VALID"}],'
  .   '"logo300x300":"http://img/a","genreTags":[{"name":"News"}],"city":"Holstebro","regionTag":{"name":"Central Jutland"}},'
  . '{"id":"b","name":"Dead","hasValidStreams":false,"streams":[{"url":"http://b","contentFormat":"audio/mpeg","status":"VALID"}]},'
  . '{"id":"c","name":"NoValid","hasValidStreams":true,"streams":[{"url":"http://c","contentFormat":"audio/mpeg","status":"BROKEN"}]}'
  . ']}';

my $page = $parse->($json);
is($page->{total}, 3, 'total from totalCount');
is(scalar @{ $page->{stations} }, 1, 'invalid stations filtered');
is_deeply($page->{stations}[0], {
	id => 'a', name => 'DR P4 Midt', url => 'http://a', image => 'http://img/a',
	genres => ['News'], city => 'Holstebro', region => 'Central Jutland',
}, 'normalized station (name trimmed)');

# Real fixture
open my $fh, '<:raw', 't/data/denmark.json' or die $!;
my $real = $parse->(do { local $/; <$fh> });
ok($real->{total} >= 200, 'fixture total plausible');
ok(@{ $real->{stations} } >= 200, 'fixture stations parsed');
ok((grep { $_->{name} eq 'DR P1' } @{ $real->{stations} }), 'DR P1 present');
ok(!(grep { !$_->{url} } @{ $real->{stations} }), 'every station has a url');
ok((grep { $_->{name} =~ /ø/ } @{ $real->{stations} }), 'UTF-8 decoded into characters');

done_testing;
