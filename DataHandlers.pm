#!/usr/bin/env perl

package DataHandlers;

require Exporter;

use strict;
use vars qw($VERSION @ISA @EXPORT);

use lib './binance-rest-api-pl/';

use POSIX;
use GetConfig;
use BinanceAPI qw(rest_api);
use Storable   qw(dclone);
use Data::Dumper;
use ServiceSubs;
use APIHandlers;
$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = qw(buyHandler sellHandler aggTradeHandler klineHandler miniTickerHandler bookTickerHandler getOrderHigh getOrderLow);

sub buyHandler {
    my $result   = $_[0];
    my $data     = $_[1];
    my $config   = $_[2];
    my $loglevel = $_[3];
    foreach my $marketname (keys %{ $data->{'buy'} }) {
        logMessage("!!!Wanna buy!!!\n", $loglevel);
        my $buyorder = postBuyOrder($marketname,$result->{$marketname}->{'analysis'}->{'ask'},$config,$loglevel-1);
        print Dumper $buyorder;
        if (defined $buyorder->{'status'} && $buyorder->{'status'} eq 'FILLED') {
            logMessage("We have a buy!\nWriting order database for market $marketname...\n", $loglevel);
            $result->{$marketname}->{'orders'}->{'closed'}->{'buy'}->{$buyorder->{'clientOrderId'}} = $buyorder;
            $result->{$marketname}->{'analysis'}->{'buyorderlow'} = getOrderLow($result->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
            $result->{$marketname}->{'analysis'}->{'buyorderhigh'} = getOrderHigh($result->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
            setConfig("DB-".uc($marketname).".json", $loglevel-1, $result->{$marketname}->{'orders'});
        }
    }
    return $result;
}
sub sellHandler {
    my $result   = $_[0];
    my $data     = $_[1];
    my $config   = $_[2];
    my $loglevel = $_[3];
    foreach my $marketname (keys %{ $data->{'sell'} }) {
        logMessage("!!!Wanna sell!!!\n", $loglevel);
        my $sellorder = postSellOrder($result->{$marketname}->{'analysis'}->{'buyorderlow'},$result->{$marketname}->{'analysis'}->{'bid'},$config,$loglevel-1);
        print Dumper $sellorder;
        if (defined $sellorder->{'status'} && $sellorder->{'status'} eq 'FILLED') {
            logMessage("We have a sell!\nWriting order database for market $marketname...\n", $loglevel);
            my $buyorderlow = $result->{$marketname}->{'analysis'}->{'buyorderlow'};
            delete($result->{$marketname}->{'orders'}->{'closed'}->{'buy'}->{$buyorderlow->{'clientOrderId'}});
            $result->{$marketname}->{'analysis'}->{'buyorderlow'} = getOrderLow($result->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
            $result->{$marketname}->{'analysis'}->{'buyorderhigh'} = getOrderHigh($result->{$marketname}->{'orders'}->{'closed'}->{'buy'}, $loglevel-1);
            setConfig("DB-".uc($marketname).".json", $loglevel-1, $result->{$marketname}->{'orders'});

            my @tradeline;
            push(@tradeline, $marketname);
            push(@tradeline, $buyorderlow->{'clientOrderId'});
            push(@tradeline, $buyorderlow->{'transactTime'});
            push(@tradeline, $buyorderlow->{'price'});
            push(@tradeline, $buyorderlow->{'executedQty'});
            push(@tradeline, $buyorderlow->{'cummulativeQuoteQty'});

            push(@tradeline, $sellorder->{'clientOrderId'});
            push(@tradeline, $sellorder->{'transactTime'});
            push(@tradeline, $sellorder->{'price'});
            push(@tradeline, $sellorder->{'executedQty'});
            push(@tradeline, $sellorder->{'cummulativeQuoteQty'});
            appendConfig("DB-trade-log.csv",$loglevel-1, join(",",@tradeline));
        }
    }
    return $result;
}


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
}

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
    $datapool->{'data'}->{'kline'}->{$interval} = dclone $data->{'k'};
    if (!defined $datapool->{'data'}->{'kline'}->{'history_'.$interval} || $datapool->{'data'}->{'kline'}->{$interval}->{'t'} > $datapool->{'data'}->{'kline'}->{'history_'.$interval}[-1][0]) {
            my $result = getKlines(uc($data->{'s'}), $interval, $config, $loglevel-1);
            if (defined $result) {
                $datapool->{'data'}->{'kline'}->{'history_'.$interval} = dclone $result;
                ($datapool->{'analysis'}->{'klinehigh_'.$interval}, $datapool->{'analysis'}->{'klinelow_'.$interval}) = getHighLow($result, $limit, $loglevel-1);
                if (defined $datapool->{'analysis'}->{'klinehigh_'.$interval} && defined $datapool->{'analysis'}->{'klinelow_'.$interval}) {
                    ($datapool->{'analysis'}->{'diffhigh_'.$interval}, $datapool->{'analysis'}->{'difflow_'.$interval}) = diffCalc($datapool->{'analysis'}, $config->{'Markets'}->{$marketname}->{'buy'}, $interval, $loglevel-1);
                }
                $ema = emaCalc($result, $config->{'Markets'}->{$marketname}->{'buy'}->{'emamethod'}, $alpha, $limit, $loglevel-1);
                $datapool->{'analysis'}->{'ema'}->{'history_'.$interval} = $ema;
            } else {
                logMessage("klineHandler: getKlines is undefined");
            }
    }
    if (!defined $config->{'Markets'}->{$marketname}->{'buy'}->{'emamethod'} || $config->{'Markets'}->{$marketname}->{'buy'}->{'emamethod'} == 0) {
        $ema = $alpha * $data->{'k'}->{'c'} + (1-$alpha) * $datapool->{'analysis'}->{'ema'}->{'history_'.$interval};
    } else {
        $ema = $datapool->{'analysis'}->{'ema'}->{'history_'.$interval};
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
    $datapool->{'data'}->{'miniTicker'} = dclone $data;
    $datapool->{'analysis'}->{'24high'} = $data->{'h'};
    $datapool->{'analysis'}->{'24low'} = $data->{'l'};
    $datapool->{'analysis'}->{'spread'} = $data->{'c'} / $data->{'o'} - 1;

    return $datapool;
}

sub bookTickerHandler {
    my $data      = $_[0];
    my $datapool  = $_[1];
    my $loglevel  = $_[2];
    my $marketname = lc($data->{'s'});
    $datapool->{'data'}->{'bookTicker'} = dclone $data;
    $datapool->{'analysis'}->{'bid'} = $data->{'b'};
    $datapool->{'analysis'}->{'ask'} = $data->{'a'};

    return $datapool;
}

sub getHighLow {
    my $high;
    my $low;
    my $candles  = $_[0];
    my $limit    = $_[1];
    my $loglevel = $_[2];
    my $length    = scalar @{ $candles } - 1;
    if (defined $limit && $limit > 0 && $limit <= $length+1) {
        foreach my $i (reverse 0..$limit) {
            my $candle = $candles->[$length-$i];
            if (!defined $high || $high == 0 || $high < $candle->[2]) {
                $high = $candle->[2];
            }
            if (!defined $low || $low == 0 || $low > $candle->[3]) {
                $low = $candle->[3];
            }
        }
    } else {
        return undef;
    }
    return ($high, $low);
}

sub emaCalc {
    my $ema;
    my $candles   = $_[0];
    my $emamethod = $_[1];
    my $alpha     = $_[2];
    my $limit     = $_[3];
    my $loglevel  = $_[4];
    my $length    = scalar @{ $candles } - 1;
    if (defined $limit && $limit > 0 && $limit <= $length+1) {
        foreach my $i (reverse 0..$limit) {
            my $candle = $candles->[$length-$i];
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

sub diffCalc {
    my $data     = $_[0];
    my $config   = $_[1];
    my $interval = $_[2];
    my $loglevel = $_[3];
    my $diff     = $data->{'klinehigh_'.$interval} - $data->{'klinelow_'.$interval};
    my $diffhigh = $data->{'klinehigh_'.$interval} - ($diff * $config->{'diffratehigh'});
    my $difflow  = $data->{'klinelow_'.$interval} + ($diff * $config->{'diffratelow'});
    return ($diffhigh, $difflow);
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

1;
