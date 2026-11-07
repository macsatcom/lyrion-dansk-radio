use strict; use warnings;
use Test::More;
use Plugins::DKRadio::Menu;

my $sel = \&Plugins::DKRadio::Menu::selectStream;

is($sel->([]), undef, 'no streams -> undef');

is($sel->([{ url => 'http://a', contentFormat => 'audio/mpeg', status => 'BROKEN' }]),
   undef, 'only invalid -> undef');

is($sel->([{ url => 'http://a', contentFormat => 'audio/mpeg', status => 'VALID' }]),
   'http://a', 'single valid');

is($sel->([
    { url => 'https://x/mp3-192/', contentFormat => 'audio/mpeg', status => 'VALID' },
    { url => 'https://x/aac-64/',  contentFormat => 'audio/aac',  status => 'VALID' },
]), 'https://x/aac-64/', 'AAC preferred over MP3');

is($sel->([
    { url => 'https://x/mp3-128/', contentFormat => 'audio/mpeg', status => 'VALID' },
    { url => 'https://x/mp3-192/', contentFormat => 'audio/mpeg', status => 'VALID' },
]), 'https://x/mp3-192/', 'higher bitrate wins within format');

is($sel->([
    { url => 'https://x/Party128web', contentFormat => 'audio/mpeg', status => 'VALID' },
    { url => 'https://x/live',        contentFormat => 'audio/mpeg', status => 'VALID' },
]), 'https://x/Party128web', 'known bitrate beats unknown');

is($sel->([
    { url => 'https://x/one', contentFormat => 'audio/mpeg', status => 'VALID' },
    { url => 'https://x/two', contentFormat => 'audio/mpeg', status => 'VALID' },
]), 'https://x/one', 'tie -> first');

is(Plugins::DKRadio::Menu::bitrateFromUrl('https://drliveradio2.akamaized.net/hls/live/2118698/p1/playlist-320000.m3u8'),
   0, 'long digit runs are not bitrates');

is($sel->([{ url => 'https://x/p1/playlist-320000.m3u8?_HLS_skip=YES', contentFormat => 'audio/aac', status => 'VALID' }]),
   'https://x/p1/playlist-320000.m3u8', 'LL-HLS _HLS_skip directive stripped');

is($sel->([{ url => 'https://x/s?a=1&_HLS_skip=YES&b=2', contentFormat => 'audio/aac', status => 'VALID' }]),
   'https://x/s?a=1&b=2', '_HLS_skip stripped, other params kept');

done_testing;
