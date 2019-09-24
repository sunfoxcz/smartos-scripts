package Terminal;

use strict;
use warnings;

use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

our $VERSION     = 1.00;
our @ISA         = qw(Exporter);
our @EXPORT      = ();
our @EXPORT_OK   = qw(colorize);
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

sub colorize {
    my ($string) = @_;
    my %backgrounds = (
        'default' => "\e[49m",
        'black' => "\e[40m",
        'red' => "\e[41m",
        'green' => "\e[42m",
        'yellow' => "\e[43m",
        'blue' => "\e[44m",
        'magenta' => "\e[45m",
        'cyan' => "\e[46m",
        'light_gray' => "\e[47m",
        'dark_gray' => "\e[100m",
        'light_red' => "\e[101m",
        'light_green' => "\e[102m",
        'light_yellow' => "\e[103m",
        'light_blue' => "\e[104m",
        'light_magenta' => "\e[105m",
        'light_cyan' => "\e[106m",
        'white' => "\e[107m",
    );
    my %colors = (
        'default' => "\e[39m",
        'black' => "\e[30m",
        'red' => "\e[31m",
        'green' => "\e[32m",
        'yellow' => "\e[33m",
        'blue' => "\e[34m",
        'magenta' => "\e[35m",
        'cyan' => "\e[36m",
        'light_gray' => "\e[37m",
        'dark_gray' => "\e[90m",
        'light_red' => "\e[91m",
        'light_green' => "\e[92m",
        'light_yellow' => "\e[93m",
        'light_blue' => "\e[94m",
        'light_magenta' => "\e[95m",
        'light_cyan' => "\e[96m",
        'white' => "\e[97m",
        'bold' => "\e[1m",
        'dim' => "\e[2m",
        'underlined' => '\e[4m',
        'blink' => '\e[5m',
        'inverted' => "\e[7m",
        'hidden' => "\e[8m",
    );
    $string =~ s/<(@{[join "|", keys %colors]})\|(@{[join "|", keys %backgrounds]})>/$colors{$1}$backgrounds{$2}/g;
    $string =~ s/<(@{[join "|", keys %colors]})>/$colors{$1}/g;
    $string =~ s/<\/[^>]+>/\e[m/g;

    return $string;
}

1;
