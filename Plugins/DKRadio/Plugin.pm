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
