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
use ServiceSubs qw(getHashed);
use BinanceAPI qw(rest_api);
use DataHandlers;
use MarketAnalysis;


##################
# Global variables
##################
our $datapool  = undef;

my $logfile    = 'bittrex-bot.log';
my $loglevel   = 10;
#######################
# Load config from file
#######################
my $configfile = 'config.json';
our $config = configHandler($configfile, $loglevel-1);
#####################
# Load order database
#####################
foreach my $marketname (keys %{ $config->{'Markets'} }) {
    logmessage("Reading order database for market $marketname...\n", $loglevel);
    $datapool->{$marketname}->{'orders'} = getconfig("DB-".uc($marketname).".json", $loglevel-1);
    if (defined $datapool->{$marketname}->{'orders'}) {
        logmessage(" - ok;\n", $loglevel);
    } else {
        logmessage(" - error.\n", $loglevel);
        exit 0;
    }
    $datapool->{$marketname}->{'analysis'}->{'buyorderlow'} = getOrderLow($datapool->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
    $datapool->{$marketname}->{'analysis'}->{'buyorderhigh'} = getOrderHigh($datapool->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
    print Dumper $datapool->{$marketname};
}
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
#                print Dumper $decoded;
            }
        }
    },
);

###############
# Timer handler
###############
$timer = IO::Async::Timer::Periodic->new(
        interval=> 10,
        on_tick => sub {
            my $result = marketCheck($datapool, $config, $loglevel-1);
#            print Dumper $result;
#            print Dumper $datapool;
            foreach my $marketname (keys %{ $result->{'buy'} }) {
                logmessage("!!!Wanna buy!!!\n", $loglevel);
                my $buyorder = postBuyOrder($marketname,$datapool->{$marketname}->{'analysis'}->{'ask'},$config,$loglevel-1);
                print Dumper $buyorder;
                if (defined $buyorder->{'status'} && $buyorder->{'status'} eq 'FILLED') {
                    logmessage("We have a buy!\nWriting order database for market $marketname...\n", $loglevel);
                    $datapool->{$marketname}->{'orders'}->{'closed'}->{'buy'}->{$buyorder->{'clientOrderId'}} = $buyorder;
#                    $datapool->{$marketname}->{'analysis'}->{'buyorderlow'} = getOrderLow($datapool->{$marketname}->{'orders'}->{'buy'}, $loglevel-1);
#                    $datapool->{$marketname}->{'analysis'}->{'buyorderhigh'} = getOrderHigh($datapool->{$marketname}->{'orders'}->{'buy'}, $loglevel-1);
                    $datapool->{$marketname}->{'analysis'}->{'buyorderlow'} = getOrderLow($datapool->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
                    $datapool->{$marketname}->{'analysis'}->{'buyorderhigh'} = getOrderHigh($datapool->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);

                    setconfig("DB-".uc($marketname).".json", $loglevel-1, $datapool->{$marketname}->{'orders'});

#                    print Dumper $datapool;
#                    exit 0;
                }
            }
            foreach my $marketname (keys %{ $result->{'sell'} }) {
                logmessage("!!!Wanna sell!!!\n", $loglevel);
                my $sellorder = postSellOrder($datapool->{$marketname}->{'analysis'}->{'buyorderlow'},$datapool->{$marketname}->{'analysis'}->{'bid'},$config,$loglevel-1);
                print Dumper $sellorder;
                if (defined $sellorder->{'status'} && $sellorder->{'status'} eq 'FILLED') {
                    logmessage("We have a sell!\nWriting order database for market $marketname...\n", $loglevel);
                    delete($datapool->{$marketname}->{'orders'}->{'closed'}->{'buy'}->{$datapool->{$marketname}->{'analysis'}->{'buyorderlow'}->{'clientOrderId'}});
#                    $datapool->{$marketname}->{'analysis'}->{'buyorderlow'} = getOrderLow($datapool->{$marketname}->{'orders'}->{'buy'}, $loglevel-1);
#                    $datapool->{$marketname}->{'analysis'}->{'buyorderhigh'} = getOrderHigh($datapool->{$marketname}->{'orders'}->{'buy'}, $loglevel-1);
                    $datapool->{$marketname}->{'analysis'}->{'buyorderlow'} = getOrderLow($datapool->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
                    $datapool->{$marketname}->{'analysis'}->{'buyorderhigh'} = getOrderHigh($datapool->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
                    setconfig("DB-".uc($marketname).".json", $loglevel-1, $datapool->{$marketname}->{'orders'});
                }
            }
#            exit 0;
        }
);

my $loop = IO::Async::Loop->new;
$loop->add($client);
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
    push(@params, "$marketname\@bookTicker");
}
push (@{ $datasend->{"params"} }, @params);
#print Dumper $datasend;
$client->send_text_frame( encode_json($datasend) );

$loop->run;

######
# Subs
######
sub marketCheck {
    my $data = $_[0];
    my $config   = $_[1];
    my $loglevel = $_[2];
    my $result;
    foreach my $marketname (keys %{ $config->{'Markets'} }) {
        logmessage ("Check $marketname market.\n", $loglevel);

        printf ("%s %s %.2f %.2f %s %s %.2f %.2f %.2f %% %.2f %.2f %.2f %.2f\n",
            strftime("%Y-%m-%d %H:%M:%S", localtime),
            $marketname,
            $data->{$marketname}->{'analysis'}->{'price'},
            $data->{$marketname}->{'analysis'}->{'buyorderlow'}->{'price'},
            $data->{$marketname}->{'analysis'}->{'trend'}->{'buy'},
            $data->{$marketname}->{'analysis'}->{'trend'}->{'sell'},
            $data->{$marketname}->{'analysis'}->{'ema'}->{'5m'},
            $data->{$marketname}->{'analysis'}->{'ema'}->{'1h'},
            $data->{$marketname}->{'analysis'}->{'spread'} * 100,
            $data->{$marketname}->{'analysis'}->{'klinehigh_1h'},
            $data->{$marketname}->{'analysis'}->{'klinelow_1h'},
            $data->{$marketname}->{'analysis'}->{'diffhigh_1h'},
            $data->{$marketname}->{'analysis'}->{'difflow_1h'}
        );
        my $buycheck = buyCheck($data->{$marketname}->{'analysis'}, $config->{'Markets'}->{$marketname}->{'buy'}, $loglevel-1);
        if (defined $buycheck) {
            $result->{'buy'}->{$marketname} = $buycheck;
        }
        my $sellcheck = sellCheck($data->{$marketname}->{'analysis'}, $config->{'Markets'}->{$marketname}->{'sell'}, $loglevel-1);
        if (defined $sellcheck) {
            $result->{'sell'}->{$marketname} = $sellcheck;
        }
    }
#    print Dumper $result;
    return $result;
}
sub buyCheck {
    my $data     = $_[0];
    my $config   = $_[1];
    my $loglevel = $_[2];
    my $result   = 1;
#    print Dumper $data;
#    print Dumper $config;
    logmessage(" BUY:\n", $loglevel-1);
# Orderlow
    if (!defined $data->{'price'}) {
        logmessage("\t".'1. Failed - $data->{\'price\'} not loaded yet.'."\n", $loglevel-1);
        $result = undef;
#        return undef;
    }
    if (defined $data->{'buyorderlow'}->{'price'}) {
        if ($data->{'buyorderlow'}->{'price'} * $config->{'nextbuyorder'} < $data->{'price'}) {
            logmessage("\t1. Failed - Defined next order price is greater than current price. (" . sprintf("%.8f", ($data->{'buyorderlow'}->{'price'} * $config->{'nextbuyorder'})) . " < " . $data->{'price'}.")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logmessage("\t1. Passed - Defined next order price is fine. (" . sprintf("%.8f", ($data->{'buyorderlow'}->{'price'} * $config->{'nextbuyorder'})) . " > " . $data->{'price'}.")\n", $loglevel-1);
        }
    } else {
        logmessage("\t1. Passed - There is no buyorders in database.\n", $loglevel-1);
    }
# Spread
    if (!defined $data->{'spread'}) {
        logmessage("\t2. Failed - Spread is undefined\n", $loglevel);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'spread'} < $config->{'minspread'}) {
            logmessage("\t2. Failed - Spread is too low. (" . sprintf("%.2f", $data->{'spread'}) . " < " . $config->{'minspread'} . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logmessage("\t2. Passed - Spread is fine (" . sprintf("%.2f", $data->{'spread'}) . " > " . $config->{'minspread'} . ")\n", $loglevel-1);
        }
    }
# Trend
    if (!defined $data->{'trend'}->{'buy'}) {
        logmessage("\t3. Failed - Trend is undefined\n", $loglevel-1);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'trend'}->{'buy'} < ($config->{'maxtrend'} - $config->{'maxtrend'}/10)) {
            logmessage("\t3. Failed - Trend is too low. (" . $data->{'trend'}->{'buy'} . " < " . ($config->{'maxtrend'} - $config->{'maxtrend'}/10) . ")\n", $loglevel-1);
            $result = undef;
#            return undef;
        } else {
            logmessage("\t3. Passed - Trend is fine. (" . $data->{'trend'}->{'buy'} . " > " . ($config->{'maxtrend'} - $config->{'maxtrend'}/10) . ")\n", $loglevel-1);
        }
    }
#    return 1;
# Diffrate
    if (!defined $data->{'diffhigh_1h'} || !defined $data->{'difflow_1h'} || !defined $data->{'price'}) {
        logmessage("\t4. Failed - Price or Diffrates are undefined\n", $loglevel);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'diffhigh_1h'} < $data->{'price'}) {
            logmessage("\t4. Failed - Price is too high. (" . $data->{'diffhigh_1h'} . " < " . $data->{'price'} . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } elsif ($data->{'difflow_1h'} > $data->{'price'}) {
            logmessage("\t4. Failed - Price is too low. (" . $data->{'difflow_1h'} . " > " . $data->{'price'} . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logmessage("\t4. Passed - Price is fine\n", $loglevel-1);
        }
    }
# EMA
    if (!defined $data->{'ema'}->{'5m'} || !defined $data->{'ema'}->{'1h'}) {
        logmessage("\t5. Failed - EMA is undefined\n", $loglevel);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'ema'}->{'5m'} < $data->{'ema'}->{'1h'}) {
            logmessage("\t5. Failed - Short EMA less than Long EMA. (" . sprintf("%.8f", $data->{'ema'}->{'5m'}) . " < " . sprintf("%.8f", $data->{'ema'}->{'1h'}) . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logmessage("\t5. Passed - Short EMA greater than Long EMA. (" . sprintf("%.8f", $data->{'ema'}->{'5m'}) . " > " . sprintf("%.8f", $data->{'ema'}->{'1h'}) . ")\n", $loglevel-1);
        }
    }
#    $result = undef;
    return $result;
}
sub sellCheck {
    my $data     = $_[0];
    my $config   = $_[1];
    my $loglevel = $_[2];
    my $result   = 1;
    logmessage(" SELL:\n", $loglevel-1);
# Limit check
    if (defined $data->{'buyorderlow'}->{'price'}) {
        if (($data->{'price'} / $data->{'buyorderlow'}->{'price'}) <= (1 + $config->{'nextsellorder'})) {
            logmessage("\t1. Failed - Price too low. (" . sprintf("%.8f", $data->{'price'} / $data->{'buyorderlow'}->{'price'}) . " <= " . sprintf("%.8f", 1 + $config->{'nextsellorder'}) . ")\n", $loglevel);
            $result = undef;
        } else {
            logmessage("\t1. Passed - Price is fine for sell. (" . sprintf("%.8f", $data->{'price'} / $data->{'buyorderlow'}->{'price'}) . " > " . sprintf("%.8f", 1 + $config->{'nextsellorder'}) . ")\n", $loglevel-1);
        }
    } else {
            logmessage("\t1. Failed - Nothing to sell\n", $loglevel-1);
            $result = undef;
#            return undef;
    }
# Stoploss
# Trend
    if (!defined $data->{'trend'}->{'sell'}) {
        logmessage("\t2. Failed - Trend is undefined\n", $loglevel);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'trend'}->{'sell'} < $config->{'maxtrend'} - $config->{'maxtrend'}/10) {
            logmessage("\t2. Failed - Trend is too low. (" . $data->{'trend'}->{'sell'} . " < " . int($config->{'maxtrend'} - $config->{'maxtrend'}/10) . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logmessage("\t2. Passed - Trend is fine. (" . $data->{'trend'}->{'sell'} . " > " . int($config->{'maxtrend'} - $config->{'maxtrend'}/10) . ")\n", $loglevel-1);
        }
    }
# EMA
    if (!defined $data->{'ema'}->{'5m'} || !defined $data->{'ema'}->{'1h'}) {
        logmessage("\t3. Failed - EMA is undefined\n", $loglevel);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'ema'}->{'5m'} > $data->{'ema'}->{'1h'}) {
            logmessage("\t3. Passed - Short EMA greater than Long EMA. (" . $data->{'ema'}->{'5m'} . " > " . $data->{'ema'}->{'1h'} . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logmessage("\t3. Passed - EMA is fine.  (" . $data->{'ema'}->{'5m'} . " < " . $data->{'ema'}->{'1h'} . ")\n", $loglevel-1);
        }
    }
#    return 1;
    return $result;
}
sub getOrderLow {
    my $orders   = $_[0];
    my $loglevel = $_[1];
    my $result   = undef;
    foreach my $order (values %{ $orders }) {
        if (!defined $result || $result->{'price'} > $order->{'price'}) {
            $result = dclone $order;
        }
    }
    return $result;
}
sub getOrderHigh {
    my $orders   = $_[0];
    my $loglevel = $_[1];
    my $result   = undef;
    foreach my $order (values %{ $orders }) {
        if (!defined $result || $result->{'price'} < $order->{'price'}) {
            $result = dclone $order;
        }
    }
    return $result;
}
sub configHandler {
    my $configfile = $_[0];
    my $loglevel   = $_[1];
    my $result     = getconfig($configfile,0);
    if (!defined $result) {
        logmessage( "Config file not found - exit.\n", $loglevel);
        exit 0;
    } else { logmessage("Reading config file - ok;\n", $loglevel); }
    if (!defined $result->{"WSS"} || !defined $result->{"WSS"}->{"host"} || !defined $result->{"WSS"}->{"port"}) {
        logmessage( "WSS config not found - exit.\n", $loglevel);
        exit 0;
    } else { logmessage("WSS config found;\n", $loglevel); }

    my $exchangeinfo = getExchangeInfo($result, $loglevel-1);
    foreach my $marketname (keys %{ $exchangeinfo }) {
        if (defined $exchangeinfo->{$marketname} && defined $exchangeinfo->{$marketname}->{'permissions'} && grep( "/^SPOT$/", $exchangeinfo->{$marketname}->{'permissions'}) ) {
            $result->{'ExchangeInfo'} = $exchangeinfo;
            $result->{'ExchangeInfo'}->{$marketname}->{'filters'} = getHashed($exchangeinfo->{$marketname}->{'filters'},'filterType');
        }
    }
    print Dumper $result;
    return $result;
}
sub getExchangeInfo {
    my $config          = $_[0];
    my $loglevel        = $_[1];
    my @marketlist = (keys %{ $config->{'Markets'} });
    my $api             = $config->{'API'};
    my $endpoint        = $api->{'url'} . "/exchangeInfo";
    my $parameters      = "symbols=[\"".uc(join("\",\"", @marketlist))."\"]";
    my $method          = "GET";
    my ($result, $ping) = rest_api($endpoint, $parameters, undef, $method, $loglevel-1);
    $result = getHashed($result->{'symbols'}, 'symbol');
#    print Dumper $result;
    return $result;
}
sub postBuyOrder {
    my $marketname      = $_[0];
    my $price           = $_[1];
    my $config          = $_[2];
    my $loglevel        = $_[3];
#POST /api/v3/order
#
#timeInForce: #GTC - Good Till Cancel #OC - Immediate or Cancel #FOK - Fill or Kill #GTX - Good Till Crossing (Post Only)
    my $api             = $config->{'API'};
    my $endpoint        = $api->{'url'} . "/order";
    my $filters         = $config->{'ExchangeInfo'}->{uc($marketname)}->{'filters'};
    if ($config->{'Markets'}->{$marketname}->{'buy'}->{'orderprice'} < $filters->{'NOTIONAL'}->{'minNotional'}) {
        logmessage ("Order price in config too low", $loglevel);
        $config->{'Markets'}->{$marketname}->{'buy'}->{'orderprice'} = $filters->{'NOTIONAL'}->{'minNotional'};
    }
    my $quantity        = $config->{'Markets'}->{$marketname}->{'buy'}->{'orderprice'} / $price;
    $quantity           = sprintf ("%f", ceil($quantity / $filters->{'LOT_SIZE'}->{'minQty'}) * $filters->{'LOT_SIZE'}->{'minQty'});
    if ($quantity < $filters->{''}->{'minQty'}) {
        logmessage ("Order quantity too low", $loglevel);
        $quantity = $filters->{'minQty'}
    }
    my $parameters      = "symbol=".uc($marketname)."&side=BUY&type=LIMIT&timeInForce=FOK&quantity=".$quantity."&price=".$price;
    my $method          = "POST";
    my ($result, $ping) = rest_api($endpoint, $parameters, $api, $method, $loglevel-1);
    return $result;
}
sub postSellOrder {
    my $order    = $_[0];
    my $price    = $_[1];
    my $config   = $_[2];
    my $loglevel = $_[3];
    if (!defined $order || !keys %{ $order }) { return undef; }
    print Dumper $order;
#    exit 0;
#POST /api/v3/order
#
#timeInForce: #GTC - Good Till Cancel #OC - Immediate or Cancel #FOK - Fill or Kill #GTX - Good Till Crossing (Post Only)
    my $api             = $config->{'API'};
    my $endpoint        = $api->{'url'} . "/order";
    my $marketname      = $order->{'symbol'};
    my $filters         = $config->{'ExchangeInfo'}->{uc($marketname)}->{'filters'};
    my $commission  = 0;
    foreach my $fill (values @{ $order->{'fills'} }) {
        $commission += $fill->{'commission'};
    }
    my $quantity   = $order->{'executedQty'} - $commission;
    $quantity      = sprintf ("%f", floor($quantity / $filters->{'LOT_SIZE'}->{'minQty'}) * $filters->{'LOT_SIZE'}->{'minQty'});
    my $method     = "POST";
    my $parameters = "symbol=".uc($marketname)."&side=SELL&type=LIMIT&timeInForce=FOK&quantity=".(sprintf("%.8f", $quantity))."&price=".$price;
    my ($result, $ping) = rest_api($endpoint, $parameters, $api, $method, 10);
    return $result;
}
sub logmessage {
    my $string = $_[0];
    my $loglevel = $_[1];
    if (defined $loglevel && $loglevel >= 5) {
        print strftime("%Y-%m-%d %H:%M:%S ", localtime);
        print $string;
    }
};
