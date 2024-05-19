#!/usr/bin/env perl

package APIHandlers;

require Exporter;

use strict;
use vars qw($VERSION @ISA @EXPORT);

use lib './binance-rest-api-pl/';

use POSIX;
use BinanceAPI qw(rest_api);
#use Storable   qw(dclone);
#use Data::Dumper;
use ServiceSubs;

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = qw(getKlines getExchangeInfo postBuyOrder postSellOrder);

sub getKlines {
    my $marketname      = $_[0];
    my $interval        = $_[1];
    my $config          = $_[2];
    my $loglevel        = $_[3];
    my $limit           = $config->{'Markets'}->{lc($marketname)}->{'buy'}->{'historycheck'};
    my $endpoint        = $config->{'API'}->{'url'} . "/uiKlines";
    my $parameters      = "symbol=$marketname&interval=$interval&limit=$limit";
    my $method          = "GET";
    my ($result, $ping) = rest_api($endpoint, $parameters, undef, $method, $loglevel-1);
#    print Dumper $result;
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
        logMessage ("Order price in config too low", $loglevel);
        $config->{'Markets'}->{$marketname}->{'buy'}->{'orderprice'} = $filters->{'NOTIONAL'}->{'minNotional'};
    }
    my $quantity        = $config->{'Markets'}->{$marketname}->{'buy'}->{'orderprice'} / $price;
    $quantity           = sprintf ("%f", ceil($quantity / $filters->{'LOT_SIZE'}->{'minQty'}) * $filters->{'LOT_SIZE'}->{'minQty'});
    if ($quantity < $filters->{''}->{'minQty'}) {
        logMessage ("Order quantity too low", $loglevel);
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

1;