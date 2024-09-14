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

use GetConfig;
use ServiceSubs;
use BinanceAPI qw(rest_api);
use APIHandlers;
use DataHandlers;
use MarketAnalysis;


##################
# Global variables
##################
our $datapool  = undef;

my $logfile    = 'bittrex-bot.log';
my $loglevel   = 10;

my $heartbeat_interval = 300;
my $heartbeat;
#######################
# Load config from file
#######################
my $configfile = 'config.json';
our $config = configHandler($configfile, $loglevel-1);
#####################
# Load order database
#####################
foreach my $marketname (keys %{ $config->{'Markets'} }) {
    logMessage("Reading order database for market $marketname...\n", $loglevel);
    $datapool->{$marketname}->{'orders'} = getConfig("DB-".uc($marketname).".json", $loglevel-1);
    if (defined $datapool->{$marketname}->{'orders'}) {
        logMessage(" - ok;\n", $loglevel);
    } else {
        logMessage(" - error.\n", $loglevel);
        exit 0;
    }
    $datapool->{$marketname}->{'analysis'}->{'buyorderlow'} = getOrderLow($datapool->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
    $datapool->{$marketname}->{'analysis'}->{'buyorderhigh'} = getOrderHigh($datapool->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
    print Dumper $datapool->{$marketname};
}
###############
# Watchdog loop
###############
while (1) {
    my $timer  = undef;
    my $client = undef;
    my $loop   = undef;

    $heartbeat = time+$heartbeat_interval;

###############
# Timer handler
###############
    $timer = IO::Async::Timer::Periodic->new(
        interval=> 10,
        on_tick => sub {
            my $result = marketCheck($datapool, $config, $loglevel-1);
            $datapool = buyHandler($datapool, $result, $config, $loglevel-1);
            $datapool = sellHandler($datapool, $result, $config, $loglevel-1);
            if ($heartbeat < time) {
                logMessage("Close connection...\n", $loglevel);
                $client->close_now;
                $timer->stop;
                $loop->loop_stop;
            } else {
                logMessage (sprintf ("Heartbeat is fine %s > %s\n", $heartbeat, time), $loglevel);
            }
        }
    );

###########################
# Web Socket Client handler
###########################
    $client = Net::Async::WebSocket::Client->new(
        on_ping_frame => sub {
            my ( $bytes ) = $_[0];
            logMessage("Ping frame received - sending Pong...\n", $loglevel);
            $client->send_pong_frame($bytes);
            $heartbeat = time+$heartbeat_interval;
        },
        on_text_frame => sub {
            my ( $self, $frame ) = @_;
            my $decoded = decode_json($frame);
            my @stream = split('@',$decoded->{'stream'});
            if (defined $decoded && defined $decoded->{'data'}->{'s'} && defined $decoded->{'data'}->{'e'}) {
                if ($decoded->{'data'}->{'e'} eq "aggTrade") {
                    my $marketname = lc($decoded->{'data'}->{'s'});
                    $datapool->{$marketname} = aggTradeHandler($decoded->{'data'}, $datapool->{$marketname}, $config, $loglevel-1);
                } elsif ($decoded->{'data'}->{'e'} eq "kline") {
                    my $marketname = lc($decoded->{'data'}->{'s'});
                    $datapool->{$marketname} = klineHandler($decoded->{'data'}, $datapool->{$marketname}, $config, $loglevel-1);
                } elsif ($decoded->{'data'}->{'e'} eq "24hrMiniTicker") {
                    my $marketname = lc($decoded->{'data'}->{'s'});
                    $datapool->{$marketname} = miniTickerHandler($decoded->{'data'}, $datapool->{$marketname}, $loglevel-1);
                }
            } elsif (defined $stream[1]) {
                if ($stream[1] eq "bookTicker") {
                    my $marketname = lc($stream[0]);
                    $datapool->{$marketname} = bookTickerHandler($decoded->{'data'}, $datapool->{$marketname}, $loglevel-1);
                }
            }
        },
    );
##################
# Start async Loop
##################
    $loop = IO::Async::Loop->new;

    $timer->start;
    $loop->add($timer);

    $loop->add($client);
    $client->connect(
       host => $config->{'WSS'}->{'host'},
       service => $config->{'WSS'}->{'port'},
       url => "wss://$config->{'WSS'}->{'host'}:$config->{'WSS'}->{'port'}/stream",
    )->get;
    logMessage("Connected; go ahead...\n", $loglevel);

    my $datasend = {"method" => "SUBSCRIBE","params" => [],"id" => 1};
    my @params;
    foreach my $marketname (keys %{ $config->{"Markets"} }) {
        push(@params, "$marketname\@aggTrade");
        push(@params, "$marketname\@kline_5m");
        push(@params, "$marketname\@kline_1h");
        push(@params, "$marketname\@miniTicker");
        push(@params, "$marketname\@bookTicker");
    }
    push (@{ $datasend->{"params"} }, @params);
    $client->send_text_frame( encode_json($datasend) );

    $loop->run;

    sleep 10;
    logMessage("Start again.\n", $loglevel);
}
######
# Subs
######
