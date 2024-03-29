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
# Binaries and variables
# ----------------------------------------------------------------------------------------------------------------------

my $DATE_PATTERN = '^20[0-9][0-9]-[01][0-9]-[0-3][0-9]_[0-2][0-9]\.[0-5][0-9]\.[0-5][0-9]$';
my $TTL_PATTERN = '^([0-9]{1})([wd]+)$';
my $TIME_FORMAT = '%Y-%m-%d_%H.%M.%S';

# ----------------------------------------------------------------------------------------------------------------------
# Parse command line options
# ----------------------------------------------------------------------------------------------------------------------

my $verbose = 0;

GetOptions(
    "verbose|v" => \$verbose,
) or pod2usage(-exit => 1, -message => "Usage: $0 [vmid] [--verbose|-v]");

my ($vmid) = @ARGV;


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
# Local functions
# ----------------------------------------------------------------------------------------------------------------------

sub findExpiredSnapshots {
    my ($fs) = @_;
    my @expired = ();

    chomp(my @snapshots = `zfs list -Ho name -t snapshot -r $fs`);
    for my $snapshot (@snapshots) {
        my $snapshotName = substr($snapshot, rindex($snapshot, '@') + 1);
        my ($snapDate, $ttl) = split /--/, $snapshotName;
        if ($snapDate =~ /$DATE_PATTERN/ && $ttl =~ /$TTL_PATTERN/) {
            my $dt = Time::Piece->strptime($snapDate, $TIME_FORMAT);
            my ($ttlCount, $ttlUnit) = ($ttl =~ /$TTL_PATTERN/);
            if ($ttlUnit eq 'w') {
                $dt += ONE_DAY * $ttlCount * 7;
            } else {
                $dt += ONE_DAY * $ttlCount;
            }
            if ($dt < localtime) {
                push @expired, $snapshot;
            }
        }
    }

    return @expired;
}

# ----------------------------------------------------------------------------------------------------------------------
# Process zones
# ----------------------------------------------------------------------------------------------------------------------

for my $uuid (@zones) {
    my $zone_data = `vmadm get $uuid`;
    $zone_data = decode_json $zone_data;
    my $alias = $zone_data->{alias};
    my $zfs_filesystem = $zone_data->{zfs_filesystem};
    my @disks = @{$zone_data->{disks}};

    chomp(my $backupRunning = `pgrep -f backup_zfs\.pl`);
    chomp(my $migrateRunning = `pgrep -f migrate_vm\.pl`);
    if ($backupRunning eq '' && $migrateRunning eq '') {
        if ($verbose) {
            print colorize("<light_green>Deleting old snapshots for VM</light_green> $alias\n");
        }

        my @expired = findExpiredSnapshots($zfs_filesystem);
        for my $snapshot (@expired) {
            if ($verbose) {
                print colorize(" <blue>*</blue> $snapshot\n");
            }
            system("zfs destroy $snapshot") and do {
                print " \e[31m* Error\e[m: can't destroy snapshot, aborting\n";
                exit 1;
            };
        }

        for my $disk (@disks) {
            my $disk_zfs_filesystem = $disk->{zfs_filesystem};
            my @expired = findExpiredSnapshots($disk_zfs_filesystem);
            for my $snapshot (@expired) {
                if ($verbose) {
                    print colorize(" <blue>*</blue> $snapshot\n");
                }
                system("zfs destroy $snapshot") and do {
                    print " \e[31m* Error\e[m: can't destroy snapshot, aborting\n";
                    exit 1;
                };
            }
        }
    }
}
