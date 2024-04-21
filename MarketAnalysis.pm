#!/usr/bin/env perl

package MarketAnalysis;

require Exporter;



use strict;
use lib './binance-rest-api-pl/';
use BinanceAPI qw(rest_api);

#use JSON          qw(from_json);
#use Digest::SHA   qw(hmac_sha512_hex);
#use Storable      qw(dclone);

use vars qw($VERSION @ISA @EXPORT);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = qw(checkForBuy checkForSell);
#@EXPORT_OK;

sub checkForBuy {
}

sub checkForSell {
}

sub logmessage {
    my $string = $_[0];
    my $loglevel = $_[1];
    if (defined $loglevel && $loglevel > 5) { print $string; }
}

1;