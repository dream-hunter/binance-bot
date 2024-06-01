package GetConfig;

require Exporter;

use strict;
use vars qw($VERSION @ISA @EXPORT);
use JSON        qw(from_json encode_json);
use POSIX;
use Data::Dumper;
use DateTime;
use DateTime::TimeZone::Local;

use lib './binance-rest-api-pl/';
use ServiceSubs;
use APIHandlers;

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = qw(configHandler getConfig setConfig appendConfig);

sub configHandler {
    my $configfile = $_[0];
    my $loglevel   = $_[1];
    my $result     = getConfig($configfile,0);
    if (!defined $result) {
        logMessage( "Config file not found - exit.\n", $loglevel);
        exit 0;
    } else { logMessage("Reading config file - ok;\n", $loglevel); }
    if (!defined $result->{"WSS"} || !defined $result->{"WSS"}->{"host"} || !defined $result->{"WSS"}->{"port"}) {
        logMessage( "WSS config not found - exit.\n", $loglevel);
        exit 0;
    } else { logMessage("WSS config found;\n", $loglevel); }

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

sub getConfig {
    my $configfile = $_[0];
    my $loglevel = $_[1];
    my $config;
    logMessage ("Downloading config from $configfile...", $loglevel);

    if (-e $configfile) {
        my $json;
        {
            local $/; #Enable 'slurp' mode
            open my $fh, "<", "$configfile";
            $json = <$fh>;
            close $fh;
        }
        $config = from_json($json);
        logMessage (" - ok\n", $loglevel);
    } else {
        logMessage (" - file $configfile does not exits", $loglevel);
        $config = {};
        setConfig($configfile, $loglevel, $config);
#        return undef;
    }
    return $config;
}

sub setConfig {
    my $configfile = $_[0];
    my $loglevel = $_[1];
    my $config = $_[2];
    if (defined $loglevel && $loglevel >= 1) {
        logMessage ("\nRewriting config to $configfile...",$loglevel);
    }
    local $/; #Enable 'slurp' mode
    open my $fh, ">", "$configfile";
    print $fh encode_json($config);
    close $fh;
    if (defined $loglevel && $loglevel >= 1) {
        print " - ok\n";
    }
    if (defined $loglevel && $loglevel >= 10) {
        print Dumper $config;
    }
    return 1;
}

sub appendConfig {
    my $configfile = $_[0];
    my $loglevel = $_[1];
    my $config = $_[2];
    if (defined $loglevel && $loglevel >= 1) {
        logMessage ("\nAppend log to $configfile...", $loglevel);
    }
    local $/; #Enable 'slurp' mode
    open my $fh, ">>", "$configfile";
    my $dt = DateTime->now(time_zone => "local");
    print $fh "$dt : $config\n";
    close $fh;
    if (defined $loglevel && $loglevel >= 1) {
        print " - ok\n";
    }
    if (defined $loglevel && $loglevel >= 10) {
        print Dumper $config;
    }
    return 1;
}

1;
