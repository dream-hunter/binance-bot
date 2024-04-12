#!/usr/bin/env perl

package DataHandlers;

require Exporter;

use strict;
use vars qw($VERSION @ISA @EXPORT);

use lib './binance-rest-api-pl/';

use POSIX;
use BinanceAPI qw(rest_api);
use Storable   qw(dclone);
use Data::Dumper;

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = qw(aggTradeHandler klineHandler miniTickerHandler);

sub aggTradeHandler {
    my $data       = $_[0];
    my $datapool   = $_[1];
    my $config     = $_[2];
    my $loglevel   = $_[3];
    my $marketname = lc($data->{'s'});

    if (!defined $datapool->{'analysis'}->{'trend'}->{'buy'}) {
        $datapool->{'analysis'}->{'trend'}->{'buy'} = 0;
    };
    if (!defined $datapool->{'analysis'}->{'trend'}->{'sell'}) {
        $datapool->{'analysis'}->{'trend'}->{'sell'} = 0;
    };
    if ($data->{'m'}) {
        $datapool->{'analysis'}->{'trend'}->{'buy'} -= $config->{'Markets'}->{$marketname}->{'buy'}->{'stepback'};
        $datapool->{'analysis'}->{'trend'}->{'sell'} += $config->{'Markets'}->{$marketname}->{'sell'}->{'stepforward'};
    } else {
        $datapool->{'analysis'}->{'trend'}->{'buy'} += $config->{'Markets'}->{$marketname}->{'buy'}->{'stepforward'};
        $datapool->{'analysis'}->{'trend'}->{'sell'} -= $config->{'Markets'}->{$marketname}->{'sell'}->{'stepback'};
    }
    if ($datapool->{'analysis'}->{'trend'}->{'buy'} < 0) {
        $datapool->{'analysis'}->{'trend'}->{'buy'} = 0;
    }
    if ($datapool->{'analysis'}->{'trend'}->{'sell'} < 0) {
        $datapool->{'analysis'}->{'trend'}->{'sell'} = 0;
    }
    if ($datapool->{'analysis'}->{'trend'}->{'buy'} > $config->{'Markets'}->{$marketname}->{'buy'}->{'maxtrend'}) {
        $datapool->{'analysis'}->{'trend'}->{'buy'} = $config->{'Markets'}->{$marketname}->{'buy'}->{'maxtrend'};
    }
    if ($datapool->{'analysis'}->{'trend'}->{'sell'} > $config->{'Markets'}->{$marketname}->{'sell'}->{'maxtrend'}) {
        $datapool->{'analysis'}->{'trend'}->{'sell'} = $config->{'Markets'}->{$marketname}->{'sell'}->{'maxtrend'};
    }
    $datapool->{'analysis'}->{'price'} = $data->{'p'};

    return $datapool;
};
sub klineHandler {
    my $data       = $_[0];
    my $datapool   = $_[1];
    my $config     = $_[2];
    my $loglevel   = $_[3];
    my $marketname = lc($data->{'s'});

    my $ema;
    my $alpha      = 0.125;
    my $interval   = $data->{'k'}->{'i'};
    my $limit      = 24;
    $datapool->{'analysis'}->{'kline'}->{$interval} = dclone $data->{'k'};
    if (!defined $datapool->{'analysis'}->{'kline'}->{"history_".$interval} || $datapool->{'analysis'}->{'kline'}->{$interval}->{'t'} > $datapool->{'analysis'}->{'kline'}->{"history_".$interval}[-1][0]) {
            my $result = getKlines(uc($data->{'s'}), $interval, $config, $loglevel-1);
            if (defined $result) {
                $datapool->{'analysis'}->{'kline'}->{"history_".$interval} = dclone $result;
                ($datapool->{'analysis'}->{'klinehigh'}, $datapool->{'analysis'}->{'klinelow'}) = getHighLow($result, $loglevel-1);
                $ema = emacalc($result, $config->{'Markets'}->{$marketname}->{'buy'}->{'emamethod'}, $alpha, $limit, $loglevel-1);
                $datapool->{'analysis'}->{'ema'}->{"history_".$interval} = $ema;
            } else {
                logmessage("klineHandler: getKlines is undefined");
            }
    }
    if (!defined $config->{'Markets'}->{$marketname}->{'buy'}->{'emamethod'} || $config->{'Markets'}->{$marketname}->{'buy'}->{'emamethod'} == 0) {
        $ema = $alpha * $data->{'k'}->{'c'} + (1-$alpha) * $datapool->{'analysis'}->{'ema'}->{"history_".$interval};
    } else {
        $ema = $datapool->{'analysis'}->{'ema'}->{"history_".$interval};
        $ema = $ema + 2 * ($data->{'k'}->{'c'} - $ema);
    }
    $datapool->{'analysis'}->{'ema'}->{$interval} = $ema;

#    print Dumper $data;
    return $datapool;
}
sub miniTickerHandler {
    my $data      = $_[0];
    my $datapool  = $_[1];
    my $loglevel  = $_[2];
    my $marketname = lc($data->{'s'});
    $datapool->{'analysis'}->{'miniTicker'} = dclone $data;
    $datapool->{'analysis'}->{'24high'} = $data->{'h'};
    $datapool->{'analysis'}->{'24low'} = $data->{'l'};
    $datapool->{'analysis'}->{'spread'} = $data->{'c'} / $data->{'o'} - 1;
#    print Dumper $datapool;
    printf ("%s %s %.2f %s %s %.2f %.2f %.2f %.2f %.2f %.2f %.2f\n",
        strftime("%Y-%m-%d %H:%M:%S", localtime),
        $marketname,
        $datapool->{'analysis'}->{'price'},
        $datapool->{'analysis'}->{'trend'}->{'buy'},
        $datapool->{'analysis'}->{'trend'}->{'sell'},
        $datapool->{'analysis'}->{'ema'}->{'5m'},
        $datapool->{'analysis'}->{'ema'}->{'1h'},
        $datapool->{'analysis'}->{'spread'} * 100,
        $datapool->{'analysis'}->{'24high'},
        $datapool->{'analysis'}->{'24low'},
        $datapool->{'analysis'}->{'klinehigh'},
        $datapool->{'analysis'}->{'klinelow'}
    );
    return $datapool;
}
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
    return $result;
}
sub getHighLow {
    my $high;
    my $low;
    my $data     = $_[0];
    my $loglevel = $_[1];
    foreach my $candle (values @{ $data }) {
        if (!defined $high || $high == 0 || $high < $candle->[2]) {
            $high = $candle->[2];
        }
        if (!defined $low || $low == 0 || $low > $candle->[3]) {
            $low = $candle->[3];
        }
    }
    return ($high, $low);
}
sub emacalc {
    my $ema;
    my $candles   = $_[0];
    my $emamethod = $_[1];
    my $alpha     = $_[2];
    my $limit     = $_[3];
    my $loglevel  = $_[4];
    my $length    = scalar @{ $candles } - 1;
    if (defined $limit && $limit > 0 && $limit <= $length+1) {
        foreach my $i (reverse 0..$limit) {
            my $candle = $candles->[$i];
            if (defined $ema && $ema != 0) {
                if (!defined $emamethod || $emamethod == 0) {
                    $ema = $alpha * $candle->[4] + (1-$alpha) * $ema;
                } else {
                    $ema = $ema + 2 * ($candle->[4] - $ema);
                }
            } else {
                $ema = $candle->[4];
            }
        }
    } else {
        return undef;
    }
    return $ema;
}
sub logmessage {
    my $string = $_[0];
    my $loglevel = $_[1];
    if (defined $loglevel && $loglevel > 5) { print $string; }
}
