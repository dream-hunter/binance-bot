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

##################
# Global variables
##################
our $datapool  = undef;
our $config    = undef;

my $logfile    = 'bittrex-bot.log';
my $loglevel   = 5;
my $configfile = 'config.json';

$config = getconfig($configfile,0);
#my $api = $config->{API};
if (!defined $config) {
    logmessage( "Main process error: Config file not found - exit\n", $loglevel);
    exit 0;
} else { logmessage(" - ok;\n", $loglevel); }

if (!defined $config->{"WSS"} || !defined $config->{"WSS"}->{"host"} || !defined $config->{"WSS"}->{"port"}) {
    logmessage( "Main process error: WSS config not found - exit\n", $loglevel);
    exit 0;
} else { logmessage(" - ok;\n", $loglevel); }


my ( $client, $timer );

###########################
# Web Socket Client handler
###########################
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
        if (defined $decoded && $decoded->{'data'}->{'e'} eq "aggTrade") {
            aggTradeHandler($decoded->{'data'});
        }
        if (defined $decoded && $decoded->{'data'}->{'e'} eq "kline") {
            klineHandler($decoded->{'data'}, $loglevel-1);
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
}
push (@{ $datasend->{"params"} }, @params);
#print Dumper $datasend;
$client->send_text_frame( encode_json($datasend) );

$loop->run;

######
# Subs
######
sub aggTradeHandler {
    my $data = $_[0];
    if (!defined $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'buy'}) {
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'buy'} = 0;
    };
    if (!defined $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'sell'}) {
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'sell'} = 0;
    };
    if ($data->{'m'}) {
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'buy'} -= $config->{'Markets'}->{lc($data->{'s'})}->{'buy'}->{'stepback'};
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'sell'} += $config->{'Markets'}->{lc($data->{'s'})}->{'sell'}->{'stepforward'};
    } else {
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'buy'} += $config->{'Markets'}->{lc($data->{'s'})}->{'buy'}->{'stepforward'};
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'sell'} -= $config->{'Markets'}->{lc($data->{'s'})}->{'sell'}->{'stepback'};
    }
    if ($datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'buy'} < 0) {
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'buy'} = 0;
    }
    if ($datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'sell'} < 0) {
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'sell'} = 0;
    }
    if ($datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'buy'} > $config->{'Markets'}->{lc($data->{'s'})}->{'buy'}->{'maxtrend'}) {
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'buy'} = $config->{'Markets'}->{lc($data->{'s'})}->{'buy'}->{'maxtrend'};
    }
    if ($datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'sell'} > $config->{'Markets'}->{lc($data->{'s'})}->{'sell'}->{'maxtrend'}) {
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'sell'} = $config->{'Markets'}->{lc($data->{'s'})}->{'sell'}->{'maxtrend'};
    }
#    return undef;
    printf ("%s %s %s %s %s %s %s %s %s %s %s %s\n",
        strftime("%Y-%m-%d %H:%M:%S", localtime),
        $data->{'s'},
        $data->{'e'},
        $data->{'p'},
        $data->{'q'},
        $data->{'m'},
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'buy'},
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'trend'}->{'sell'},
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'ema'}->{'history_5m'},
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'ema'}->{'history_1h'},
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'ema'}->{'5m'},
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'ema'}->{'1h'},
    );
#    print Dumper $data;
};
sub klineHandler {
    my $data     = $_[0];
    my $loglevel = $_[1];
    my $limit    = 48;
    my $alpha    = 0.125;
    my $ema;
    if (defined $datapool->{lc($data->{'s'})}->{'analysis'}->{'kline'}->{$data->{'k'}->{'i'}}) {
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'kline'}->{$data->{'k'}->{'i'}} = dclone $data->{'k'};
    } else {
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'kline'}->{$data->{'k'}->{'i'}} = dclone $data->{'k'};
    }
    if (defined $datapool->{lc($data->{'s'})}->{'analysis'}->{'kline'}->{"history_".$data->{'k'}->{'i'}}) {
        if ($datapool->{lc($data->{'s'})}->{'analysis'}->{'kline'}->{$data->{'k'}->{'i'}}->{'t'} > $datapool->{lc($data->{'s'})}->{'analysis'}->{'kline'}->{"history_".$data->{'k'}->{'i'}}[-1][0]) {
            my $result = getKlines(uc($data->{'s'}), $data->{'k'}->{'i'}, $limit, $loglevel-1);
#            print Dumper $result;
            $datapool->{lc($data->{'s'})}->{'analysis'}->{'kline'}->{"history_".$data->{'k'}->{'i'}} = dclone $result;
            $ema = emacalc($result, $alpha, $limit);
            $datapool->{lc($data->{'s'})}->{'analysis'}->{'ema'}->{"history_".$data->{'k'}->{'i'}} = $ema;
#            print "$ema\n";
#            exit 0;
        }
    } else {
        my $result = getKlines(uc($data->{'s'}), $data->{'k'}->{'i'}, $limit, $loglevel-1);
#        print Dumper $result;
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'kline'}->{"history_".$data->{'k'}->{'i'}} = dclone $result;
        $ema = emacalc($result, $alpha, $limit);
        $datapool->{lc($data->{'s'})}->{'analysis'}->{'ema'}->{"history_".$data->{'k'}->{'i'}} = $ema;
#        print "$ema\n";
    }
#    $ema = $datapool->{lc($data->{'s'})}->{'analysis'}->{'ema'}->{"history_".$data->{'k'}->{'i'}};
#    $ema = $ema + 2 * ($data->{'k'}->{'c'} - $ema);
    $ema = $alpha * $data->{'k'}->{'c'} + (1-$alpha) * $datapool->{lc($data->{'s'})}->{'analysis'}->{'ema'}->{"history_".$data->{'k'}->{'i'}};
    $datapool->{lc($data->{'s'})}->{'analysis'}->{'ema'}->{$data->{'k'}->{'i'}} = $ema;
#    print Dumper $data;
}
sub getKlines {
#GET /api/v3/klines
#
#Intervals:
#m -> minutes; h -> hours; d -> days; w -> weeks; M -> months
#Possible values: 1m,3m,5m,15m,30m,1h,2h,4h,6h,8h,12h,1d,3d,1w,1M
#Limit: Default 500; max 1000 (not required value)
#
    my $endpoint     = $config->{'API'}->{'url'} . "/klines";
    my $marketname = $_[0];
    my $interval   = $_[1];
    my $limit      = $_[2];
    my $loglevel   = $_[3];
    my $parameters = "symbol=$marketname&interval=$interval&limit=$limit";
    my $method     = "GET";
    my ($result, $ping) = rest_api($endpoint, $parameters, undef, $method, $loglevel-1);
#    print Dumper $result;
    return $result;
}

sub logmessage {
    my $string = $_[0];
    my $loglevel = $_[1];
    if (defined $loglevel && $loglevel > 5) { print $string; }
};
sub emacalc {
    my $candles = $_[0];
    my $alpha   = $_[1];
    my $limit   = $_[2];
    my $ema     = 0;
    my $length  = scalar @{ $candles } - 1;
    if (defined $limit && $limit > 0) {
        foreach my $i (reverse 0..$length ) {
            my $candle = $candles->[$i];
            if (defined $ema && $ema != 0) {
                $ema = $alpha * $candle->[4] + (1-$alpha) * $ema;
#                $ema = $ema + 2 * ($candle->[4] - $ema);
            } else {
                $ema = $candle->[4];
            }
        }
    }
    return $ema;
}