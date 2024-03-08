#!/usr/bin/env perl

use lib '.';

use strict;
use IO::Async::Loop;
use IO::Async::Stream;
use IO::Async::Timer::Periodic;
use Net::Async::WebSocket::Client;
use Time::HiRes qw(gettimeofday);
use Data::Dumper;
use JSON;
use POSIX;

use GetConfig qw(getconfig setconfig appendconfig);
##################
# Global variables
##################
my $logfile    = 'bittrex-bot.log';
my $loglevel   = 5;
my $configfile = 'config.json';
my $datapool   = undef;

my $config = getconfig($configfile,0);
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
        if ($decoded->{"data"}->{"e"} eq "aggTrade") {
            print strftime("%Y-%m-%d %H:%M:%S ", localtime);
            print "$decoded->{'data'}->{'s'} $decoded->{'data'}->{'e'} $decoded->{'data'}->{'p'} $decoded->{'data'}->{'q'} $decoded->{'data'}->{'m'}\n";
        }
    },
);

###############
# Timer handler
###############
$timer = IO::Async::Timer::Periodic->new(
        interval=> 30,
        on_tick => sub {
#            $client->send_text_frame( "pong" );
            my $datasend = { "method" => "LIST_SUBSCRIPTIONS", "id" => 1 };
            $client->send_text_frame( encode_json($datasend) );
        },
);


my $loop = IO::Async::Loop->new;

$loop->add( $client );
$timer->start;
$loop->add($timer);


$client->connect(
   host => $config->{'WSS'}->{'host'},
   service => $config->{'WSS'}->{'port'},
#   url => "wss://$HOST:$PORT/ws/btcusdt\@aggTrade",
   url => "wss://$config->{'WSS'}->{'host'}:$config->{'WSS'}->{'port'}/stream",
)->get;

print strftime("%Y-%m-%d %H:%M:%S ", localtime);
print "Connected; go ahead...\n";

#my $datasend = {"method" => "SUBSCRIBE","params" => ["btcusdt\@aggTrade"],"id" => 1};
my $datasend = {"method" => "SUBSCRIBE","params" => [],"id" => 1};
my @params;
foreach my $marketname (keys %{ $config->{"Markets"} }) {
    push(@params, "$marketname\@aggTrade");
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
}
