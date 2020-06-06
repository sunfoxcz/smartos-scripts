#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use JSON::PP;
use Pod::Usage;
use Time::Piece;
use Time::Seconds;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Terminal qw(colorize);

# ----------------------------------------------------------------------------------------------------------------------
# Variables
# ----------------------------------------------------------------------------------------------------------------------

my $TIME_FORMAT = '%Y-%m-%d_%H.%M.%S';

# ----------------------------------------------------------------------------------------------------------------------
# Parse command line options
# ----------------------------------------------------------------------------------------------------------------------

my $ttl = '';
my $verbose = 0;

GetOptions(
    "ttl|a" => \$ttl,
    "verbose|v" => \$verbose,
) or pod2usage(-exit => 1, -message => "Usage: $0 [vmid] [--ttl|-a] [--verbose|-v]");

my ($vmid) = @ARGV;

if (!$ttl) {
    my $currentHour = localtime->strftime("%H");
    if ($currentHour == 1) {
        $ttl = '1w';
    } else {
        $ttl = '1d';
    }
}

# ----------------------------------------------------------------------------------------------------------------------
# Are we running backup for one host or all hosts?
# ----------------------------------------------------------------------------------------------------------------------

my @zones;

if (defined $vmid) {
    @zones = `vmadm list -Ho uuid alias=$vmid`;
} else {
    @zones = `vmadm list -Ho uuid`;
}
chomp @zones;

# ----------------------------------------------------------------------------------------------------------------------
# Process zones
# ----------------------------------------------------------------------------------------------------------------------

for my $uuid (@zones) {
    my $zone_data = `vmadm get $uuid`;
    $zone_data = decode_json $zone_data;
    my $alias = $zone_data->{alias};
    my $zfs_filesystem = $zone_data->{zfs_filesystem};
    my @disks = @{$zone_data->{disks}};

    if ($verbose) {
        print colorize("<light_green>Creating backup snapshots for VM</light_green> $alias\n");
    }

    my $currentDate = localtime->strftime("$TIME_FORMAT");
    my $snapName = "$currentDate--$ttl";
    if ($verbose) {
        print colorize(" <blue>*</blue> $zfs_filesystem\@$snapName\n");
    }
    system("zfs snapshot -r $zfs_filesystem\@$snapName");
    for my $disk (@disks) {
        my $disk_zfs_filesystem = $disk->{zfs_filesystem};
        if ($verbose) {
            print colorize(" <blue>*</blue> $disk_zfs_filesystem\@$snapName\n");
        }
        system("zfs snapshot -r $disk_zfs_filesystem\@$snapName");
    }
}
