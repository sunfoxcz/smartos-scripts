#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Time::Piece;

use FindBin qw($Bin);
use lib "$Bin/libs";
use Terminal qw(colorize);

# ----------------------------------------------------------------------------------------------------------------------
# Binaries and variables
# ----------------------------------------------------------------------------------------------------------------------

my $ZFS = '/usr/sbin/zfs';
my $ZFSNAP = '/backup/scripts/zfsnap/sbin/zfsnap.sh';
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
    my $alias = `echo '$zone_data' | json alias`;
    my $zfs_filesystem = `echo '$zone_data' | json zfs_filesystem`;
    my @disks = `echo '$zone_data' | json disks | json -a zfs_filesystem`;

    $zone_data =~ s/\s+$//;
    $alias =~ s/\s+$//;
    $zfs_filesystem =~ s/\s+$//;
    chomp @disks;

    if ($verbose) {
        print colorize("<light_green>Creating backup snapshots for VM</light_green> $alias\n");
    }

    my $currentDate = localtime->strftime("$TIME_FORMAT");
    my $snapName = "$currentDate--$ttl";
    if ($verbose) {
        print colorize(" <blue>*</blue> $zfs_filesystem\@$snapName\n");
    }
    system("$ZFS snapshot $zfs_filesystem\@$snapName");
    for my $disk (@disks) {
        if ($verbose) {
            print colorize(" <blue>*</blue> $disk\@$snapName\n");
        }
        system("zfs snapshot $disk\@$snapName");
    }

    chomp(my $migrateRunning = `ps ax | grep [m]igrate_vm\.pl`);
    if ($migrateRunning eq '') {
        if ($verbose) {
            print colorize("<light_green>Pruning old snapshots for VM</light_green> $alias\n");
            print colorize(" <blue>*</blue> $zfs_filesystem\n");
        }
        system("/backup/scripts/zfsnap/sbin/zfsnap.sh destroy $zfs_filesystem") and do {
            print " \e[31m* Error\e[m: can't prune, aborting\n";
            exit 1;
        };
        for my $disk (@disks) {
            if ($verbose) {
                print colorize(" <blue>*</blue> $disk\n");
            }
            system("/backup/scripts/zfsnap/sbin/zfsnap.sh destroy $disk") and do {
                print " \e[31m* Error\e[m: can't prune, aborting\n";
                exit 1;
            };
        }
    }
}
