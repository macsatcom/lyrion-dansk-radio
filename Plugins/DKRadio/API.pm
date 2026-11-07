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
