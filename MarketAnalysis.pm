#!/usr/bin/env perl

package MarketAnalysis;

require Exporter;



use strict;
use lib './binance-rest-api-pl/';
use BinanceAPI qw(rest_api);
use ServiceSubs qw(logMessage);
use POSIX;

use vars qw($VERSION @ISA @EXPORT);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = qw(marketCheck buyCheck sellCheck);
#@EXPORT_OK;

sub marketCheck {
    my $data = $_[0];
    my $config   = $_[1];
    my $loglevel = $_[2];
    my $result;
    foreach my $marketname (keys %{ $config->{'Markets'} }) {
        logMessage ("Check $marketname market.\n", $loglevel);

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
    logMessage(" BUY:\n", $loglevel-1);
# Orderlow
    if (!defined $data->{'price'}) {
        logMessage("\t".'1. Failed - $data->{\'price\'} not loaded yet.'."\n", $loglevel-1);
        $result = undef;
#        return undef;
    }
    if (defined $data->{'buyorderlow'}->{'price'}) {
        if ($data->{'buyorderlow'}->{'price'} * $config->{'nextbuyorder'} < $data->{'price'}) {
            logMessage("\t1. Failed - Defined next order price is greater than current price. (" . sprintf("%.8f", ($data->{'buyorderlow'}->{'price'} * $config->{'nextbuyorder'})) . " < " . $data->{'price'}.")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logMessage("\t1. Passed - Defined next order price is fine. (" . sprintf("%.8f", ($data->{'buyorderlow'}->{'price'} * $config->{'nextbuyorder'})) . " > " . $data->{'price'}.")\n", $loglevel-1);
        }
    } else {
        logMessage("\t1. Passed - There is no buyorders in database.\n", $loglevel-1);
    }
# Spread
    if (!defined $data->{'spread'}) {
        logMessage("\t2. Failed - Spread is undefined\n", $loglevel);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'spread'} < $config->{'minspread'}) {
            logMessage("\t2. Failed - Spread is too low. (" . sprintf("%.2f", $data->{'spread'}) . " < " . $config->{'minspread'} . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logMessage("\t2. Passed - Spread is fine (" . sprintf("%.2f", $data->{'spread'}) . " > " . $config->{'minspread'} . ")\n", $loglevel-1);
        }
    }
# Trend
    if (!defined $data->{'trend'}->{'buy'}) {
        logMessage("\t3. Failed - Trend is undefined\n", $loglevel-1);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'trend'}->{'buy'} < ($config->{'maxtrend'} - $config->{'maxtrend'}/10)) {
            logMessage("\t3. Failed - Trend is too low. (" . $data->{'trend'}->{'buy'} . " < " . ($config->{'maxtrend'} - $config->{'maxtrend'}/10) . ")\n", $loglevel-1);
            $result = undef;
#            return undef;
        } else {
            logMessage("\t3. Passed - Trend is fine. (" . $data->{'trend'}->{'buy'} . " > " . ($config->{'maxtrend'} - $config->{'maxtrend'}/10) . ")\n", $loglevel-1);
        }
    }
# Diffrate
    if (!defined $data->{'diffhigh_1h'} || !defined $data->{'difflow_1h'} || !defined $data->{'price'}) {
        logMessage("\t4. Failed - Price or Diffrates are undefined\n", $loglevel);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'diffhigh_1h'} < $data->{'price'}) {
            logMessage("\t4. Failed - Price is too high. (" . $data->{'diffhigh_1h'} . " < " . $data->{'price'} . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } elsif ($data->{'difflow_1h'} > $data->{'price'}) {
            logMessage("\t4. Failed - Price is too low. (" . $data->{'difflow_1h'} . " > " . $data->{'price'} . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logMessage("\t4. Passed - Price is fine\n", $loglevel-1);
        }
    }
# EMA
    if (!defined $data->{'ema'}->{'5m'} || !defined $data->{'ema'}->{'1h'}) {
        logMessage("\t5. Failed - EMA is undefined\n", $loglevel);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'ema'}->{'5m'} < $data->{'ema'}->{'1h'}) {
            logMessage("\t5. Failed - Short EMA less than Long EMA. (" . sprintf("%.8f", $data->{'ema'}->{'5m'}) . " < " . sprintf("%.8f", $data->{'ema'}->{'1h'}) . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logMessage("\t5. Passed - Short EMA greater than Long EMA. (" . sprintf("%.8f", $data->{'ema'}->{'5m'}) . " > " . sprintf("%.8f", $data->{'ema'}->{'1h'}) . ")\n", $loglevel-1);
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
    logMessage(" SELL:\n", $loglevel-1);
# Limit check
    if (defined $data->{'buyorderlow'}->{'price'}) {
        if (($data->{'price'} / $data->{'buyorderlow'}->{'price'}) <= (1 + $config->{'nextsellorder'})) {
            logMessage("\t1. Failed - Price too low. (" . sprintf("%.8f", $data->{'price'} / $data->{'buyorderlow'}->{'price'}) . " <= " . sprintf("%.8f", 1 + $config->{'nextsellorder'}) . ")\n", $loglevel);
            $result = undef;
        } else {
            logMessage("\t1. Passed - Price is fine for sell. (" . sprintf("%.8f", $data->{'price'} / $data->{'buyorderlow'}->{'price'}) . " > " . sprintf("%.8f", 1 + $config->{'nextsellorder'}) . ")\n", $loglevel);
        }
    } else {
            logMessage("\t1. Failed - Nothing to sell\n", $loglevel-1);
            $result = undef;
#            return undef;
    }
# Stoploss
#    return $result;
# Trend
    if (!defined $data->{'trend'}->{'sell'}) {
        logMessage("\t2. Failed - Trend is undefined\n", $loglevel);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'trend'}->{'sell'} < $config->{'maxtrend'} - $config->{'maxtrend'}/10) {
            logMessage("\t2. Failed - Trend is too low. (" . $data->{'trend'}->{'sell'} . " < " . int($config->{'maxtrend'} - $config->{'maxtrend'}/10) . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logMessage("\t2. Passed - Trend is fine. (" . $data->{'trend'}->{'sell'} . " > " . int($config->{'maxtrend'} - $config->{'maxtrend'}/10) . ")\n", $loglevel-1);
        }
    }
# EMA
    if (!defined $data->{'ema'}->{'5m'} || !defined $data->{'ema'}->{'1h'}) {
        logMessage("\t3. Failed - EMA is undefined\n", $loglevel);
        $result = undef;
#        return undef;
    } else {
        if ($data->{'ema'}->{'5m'} > $data->{'ema'}->{'1h'}) {
            logMessage("\t3. Failed - Short EMA greater than Long EMA. (" . sprintf("%.8f", $data->{'ema'}->{'5m'}) . " > " . sprintf("%.8f", $data->{'ema'}->{'1h'}) . ")\n", $loglevel);
            $result = undef;
#            return undef;
        } else {
            logMessage("\t3. Passed - EMA is fine.  (" . sprintf("%.8f", $data->{'ema'}->{'5m'}) . " < " . sprintf("%.8f", $data->{'ema'}->{'1h'}) . ")\n", $loglevel-1);
        }
    }
#    return 1;
    return $result;
}

1;
