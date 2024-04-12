#!/usr/bin/env perl

use lib '.';
use lib './binance-rest-api-pl/';

use strict;
use IO::Async::Loop;
use IO::Async::Stream;
use IO::Async::Timer::Periodic;
use Net::Async::WebSocket::Client;
use Storable qw(dclone);
use Time::HiRes qw(gettimeofday);
use Data::Dumper;
use JSON;
use POSIX;

use GetConfig qw(getconfig setconfig appendconfig);
use BinanceAPI qw(rest_api);
use DataHandlers;
use MarketAnalysis;


##################
# Global variables
##################
our $datapool  = undef;
our $config    = undef;

my $logfile    = 'bittrex-bot.log';
my $loglevel   = 5;
#######################
# Load config from file
#######################
my $configfile = 'config.json';
$config = getconfig($configfile,0);
if (!defined $config) {
    logmessage( "Main process error: Config file not found - exit\n", $loglevel);
    exit 0;
} else { logmessage(" - ok;\n", $loglevel); }

if (!defined $config->{"WSS"} || !defined $config->{"WSS"}->{"host"} || !defined $config->{"WSS"}->{"port"}) {
    logmessage( "Main process error: WSS config not found - exit\n", $loglevel);
    exit 0;
} else { logmessage(" - ok;\n", $loglevel); }

###########################
# Web Socket Client handler
###########################
my ( $client, $timer );
$client = Net::Async::WebSocket::Client->new(
    on_ping_frame => sub {
        my ( $bytes ) = $_[0];
        print strftime("%Y-%m-%d %H:%M:%S ", localtime);
        print "Ping frame received - sending Pong...\n";
        $client->send_pong_frame($bytes);
    },
    on_text_frame => sub {
        my ( $self, $frame ) = @_;
        my $decoded = decode_json($frame);
        if (defined $decoded && $decoded->{'data'}->{'e'} eq "aggTrade" && defined $decoded->{'data'}->{'s'}) {
            my $marketname = lc($decoded->{'data'}->{'s'});
            $datapool->{$marketname} = aggTradeHandler($decoded->{'data'}, $datapool->{$marketname}, $config, $loglevel-1);
        }
        if (defined $decoded && $decoded->{'data'}->{'e'} eq "kline" && defined $decoded->{'data'}->{'s'}) {
            my $marketname = lc($decoded->{'data'}->{'s'});
            $datapool->{$marketname} = klineHandler($decoded->{'data'}, $datapool->{$marketname}, $config, $loglevel-1);
        }
        if (defined $decoded && $decoded->{'data'}->{'e'} eq "24hrMiniTicker") {
            my $marketname = lc($decoded->{'data'}->{'s'});
            miniTickerHandler($decoded->{'data'}, $datapool->{$marketname}, $loglevel-1);
        }
    },
);

###############
# Timer handler
###############
$timer = IO::Async::Timer::Periodic->new(
        interval=> 30,
        on_tick => sub {
#            $client->send_text_frame( "some thing" );
#            my $datasend = { "method" => "LIST_SUBSCRIPTIONS", "id" => 1 };
#            $client->send_text_frame( encode_json($datasend) );
        },
);

my $loop = IO::Async::Loop->new;
$loop->add( $client );
$timer->start;
$loop->add($timer);


$client->connect(
   host => $config->{'WSS'}->{'host'},
   service => $config->{'WSS'}->{'port'},
   url => "wss://$config->{'WSS'}->{'host'}:$config->{'WSS'}->{'port'}/stream",
)->get;

print strftime("%Y-%m-%d %H:%M:%S ", localtime);
print "Connected; go ahead...\n";

my $datasend = {"method" => "SUBSCRIBE","params" => [],"id" => 1};
my @params;
foreach my $marketname (keys %{ $config->{"Markets"} }) {
    push(@params, "$marketname\@aggTrade");
    push(@params, "$marketname\@kline_5m");
    push(@params, "$marketname\@kline_1h");
    push(@params, "$marketname\@miniTicker");
#    $datapool->{$marketname}->{'config'} = $config->{'Markets'}->{$marketname};
}
push (@{ $datasend->{"params"} }, @params);
#print Dumper $datasend;
$client->send_text_frame( encode_json($datasend) );

$loop->run;

######
# Subs
######
sub logmessage {
    my $string = $_[0];
    my $loglevel = $_[1];
    if (defined $loglevel && $loglevel > 5) { print $string; }
};
