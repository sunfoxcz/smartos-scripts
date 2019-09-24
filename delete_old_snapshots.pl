#!/usr/bin/env perl

use strict;
use warnings;

use POSIX;
use Time::Piece;

use FindBin qw($Bin);
use lib "$Bin/libs";
use Terminal qw(colorize);
use ZFS;

# ----------------------------------------------------------------------------------------------------------------------
# Host variables
# ----------------------------------------------------------------------------------------------------------------------

my $TAG = 'backup';

# ----------------------------------------------------------------------------------------------------------------------
# Parse command line options
# ----------------------------------------------------------------------------------------------------------------------

my ($vmid) = @ARGV;

# ----------------------------------------------------------------------------------------------------------------------
# Are we running backup for one host or all hosts?
# ----------------------------------------------------------------------------------------------------------------------

my @zones;

if (defined $vmid) {
    chomp(@zones = `vmadm list -Ho uuid alias=$vmid`);
} else {
    chomp(@zones = `vmadm list -Ho uuid`);
}

# ----------------------------------------------------------------------------------------------------------------------
# Process zones
# ----------------------------------------------------------------------------------------------------------------------

for my $uuid (@zones) {
    chomp(my $zone_data = `vmadm get $uuid`);
    chomp(my $alias = `echo '$zone_data' | json alias`);
    chomp(my $zfs_filesystem = `echo '$zone_data' | json zfs_filesystem`);

    print colorize("<light_green>Checking old snapshots for vm</light_green> $alias\n");

    # my $now = localtime->strftime('%s');
    # chomp(my @snapshots = `zfs list -rt snapshot -Hpo name,creation $zfs_filesystem`);

    # for my $snapshot (@snapshots) {
    #     my ($name, $creation) = split(/\t/, $snapshot);
    #     chomp(my $diff_hours = `bc <<<"scale=0; ($now - $creation) / 60 / 60"`);

    #     if ($diff_hours le 24) {
    #         # Let snapshots younger than 24 hours as is
    #     } elsif ($diff_hours le 168) {
    #         # For snapshots older than 1 day and younger than week, keep one snapshot per day
    #         my $created_hour = POSIX::strftime('%k', localtime($creation));
    #         my $created_date = POSIX::strftime('%Y-%m-%d %H:%M', localtime($creation));
    #         if ($created_hour ne '01') {
    #             print colorize(" <red>*</red> deleting snapshot $name ($created_date)\n");
    #         }
    #     } elsif ($diff_hours le 672) {
    #         # For snapshots older than week and younger than month, keep one snapshot per week
    #         my $created_weekday = POSIX::strftime('%u-$k', localtime($creation));
    #         my $created_date = POSIX::strftime('%Y-%m-%d %H:%M', localtime($creation));
    #         if ($created_weekday ne '1-01') {
    #             print colorize(" <red>*</red> deleting snapshot $name ($created_date)\n");
    #         }
    #     } else {
    #         # Delete older snapshots
    #         my $created_date = POSIX::strftime('%Y-%m-%d %H:%M', localtime($creation));
    #         print colorize(" <red>*</red> deleting snapshot $name ($created_date)\n");
    #     }

    #     # TODO: Keep at least last two snapshots even if they are old
    # }

    chomp(my @zvols = `zfs list -rHo name $zfs_filesystem`);
    for my $z (@zvols) {
        my $last_snap = ZFS::getLastSnap($z);
        if ($last_snap eq '') {
            next;
        }

        my $last_seq = ZFS::getLastSequence($last_snap);
        print colorize(" <light_green>*</light_green> $z last seq is <light_red>$last_seq</light_red>\n");

        my @old_snaps = ZFS::getAllSnaps($z);
        if (scalar(@old_snaps) < 3) {
            next;
        }
        splice(@old_snaps, -2);

        for my $s (@old_snaps) {
            print colorize(" <light_red>*</light_red> Deleting snapshot $s\n");
            system("zfs destroy $s");
        }
    }

    chomp(my @disks = `echo '$zone_data' | json disks | json -a zfs_filesystem`);
    for my $disk (@disks) {
        my $last_snap = ZFS::getLastSnap($disk);
        if ($last_snap eq '') {
            next;
        }

        my $last_seq = ZFS::getLastSequence($last_snap);
        print colorize(" <light_green>*</light_green> $disk last seq is <light_red>$last_seq</light_red>\n");

        my @old_snaps = ZFS::getAllSnaps($disk);
        if (scalar(@old_snaps) < 3) {
            next;
        }
        splice(@old_snaps, -2);

        for my $s (@old_snaps) {
            print colorize(" <light_red>*</light_red> Deleting snapshot $s\n");
            system("zfs destroy $s");
        }
    }
}
