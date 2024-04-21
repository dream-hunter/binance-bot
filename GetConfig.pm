package GetConfig;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use JSON        qw(from_json encode_json);
use POSIX;
use Data::Dumper;
use DateTime;
use DateTime::TimeZone::Local;


$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(getconfig setconfig appendconfig);
%EXPORT_TAGS = ( DEFAULT => [qw(&getconfig &setconfig &appendconfig)]);

sub getconfig {
    my $configfile = $_[0];
    my $loglevel = $_[1];
    my $config;
    logmessage ("Downloading config from $configfile...", $loglevel);

    if (-e $configfile) {
        my $json;
        {
            local $/; #Enable 'slurp' mode
            open my $fh, "<", "$configfile";
            $json = <$fh>;
            close $fh;
        }
        $config = from_json($json);
        logmessage (" - ok\n", $loglevel);
    } else {
        logmessage (" - file $configfile does not exits", $loglevel);
        $config = {};
        setconfig($configfile, $loglevel, $config);
#        return undef;
    }
    return $config;
}

sub setconfig {
    my $configfile = $_[0];
    my $loglevel = $_[1];
    my $config = $_[2];
    if (defined $loglevel && $loglevel >= 1) {
        logmessage ("\nRewriting config to $configfile...",$loglevel);
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

sub appendconfig {
    my $configfile = $_[0];
    my $loglevel = $_[1];
    my $config = $_[2];
    if (defined $loglevel && $loglevel >= 1) {
        logmessage ("\nAppend log to $configfile...", $loglevel);
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

sub logmessage {
    my $string = $_[0];
    my $loglevel = $_[1];
    if (defined $loglevel && $loglevel >= 5) {
        print strftime("%Y-%m-%d %H:%M:%S ", localtime);
        print $string;
    }
};

1;
