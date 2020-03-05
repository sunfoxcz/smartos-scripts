#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Sys::Hostname;
use Time::Piece;

use experimental 'smartmatch';

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Terminal qw(colorize);
use ZFS;

# ----------------------------------------------------------------------------------------------------------------------
# Host variables
# ----------------------------------------------------------------------------------------------------------------------

my $TAG = 'backup';
my $SRC_HOST = hostname();
my $DEST_HOST = 'storage.sunfox.cz';
my $DEST_PATH = "zones/backup/$SRC_HOST";

# ----------------------------------------------------------------------------------------------------------------------
# Binaries
# ----------------------------------------------------------------------------------------------------------------------

my $MBUFFER = '/opt/local/bin/mbuffer -q -s 128k -m 1G';
my $PV = '/opt/local/bin/pv';
my $SSH = 'ssh -T -c aes128-ctr -o Compression=no -x';

# ----------------------------------------------------------------------------------------------------------------------
# Parse command line options
# ----------------------------------------------------------------------------------------------------------------------

my $PROGRESS = "$PV -q";
my $progressFlag = 0;
my $clearFlag = 0;

GetOptions(
    "progress|p" => \$progressFlag,
    "clear|c" => \$clearFlag,
) or pod2usage(-exit => 1, -message => "Usage: $0 [vmid] [--progress|-p] [--clear|-c]");

my ($vmid) = @ARGV;

if ($progressFlag) {
    $PROGRESS = "$PV -rtab"
}

# ----------------------------------------------------------------------------------------------------------------------
# Check if not already running
# ----------------------------------------------------------------------------------------------------------------------

chomp(my $backupRunning = `pgrep -f backup_zfs\.pl`);
if ($backupRunning ne "$$") {
    print colorize("<red>$0</red> already running, exiting\n");
    exit 1;
}

# ----------------------------------------------------------------------------------------------------------------------
# Remote functions
# ----------------------------------------------------------------------------------------------------------------------

# ZFS SEND
# -R: replicate recursively
# -p: include the dataset's properties in the stream (implicit for -R)
# -e: generate a more compact stream by using WRITE_EMBEDDED records
# -c: generate a more compact stream by using compressed WRITE records
# -L: Generate a stream which may contain blocks larger than 128KB
# ZFS RECEIVE
# -F: force a rollback of the file system to the most recent snapshot
# -u: do not mount received filesystem
sub sendInitial {
    my ($source_fs, $snapshot, $dest_host, $dest_fs) = @_;
    my $dataset_size = `zfs get -Ho value used $source_fs`;
    chomp $dataset_size;

    print colorize(" <blue>*</blue> sending to $dest_host:$dest_fs ($dataset_size)\n");
    system("zfs send -RpecL $source_fs\@$snapshot | $MBUFFER | $PROGRESS |
        $SSH $dest_host \"$MBUFFER | zfs recv -Fu $dest_fs\"");
}

# ZFS PRE-SEND (for counting send size)
# -n: Do a dry-run
# -v: Print verbose information about the stream package generated
# -i: Generate an incremental stream from the first to the second snapshot
# ZFS SEND
# -R: replicate recursively
# -p: include the dataset's properties in the stream (implicit for -R)
# -e: generate a more compact stream by using WRITE_EMBEDDED records
# -c: generate a more compact stream by using compressed WRITE records
# -L: Generate a stream which may contain blocks larger than 128KB
# -i: Generate an incremental stream from the first to the second snapshot
# ZFS RECEIVE
# -F: force a rollback of the file system to the most recent snapshot
# -u: do not mount received filesystem
sub sendIncremental {
    my ($source_fs, $source_snap_from, $source_snap_to, $dest_host, $dest_fs) = @_;
    my $snapshot_size = `zfs send -nvi $source_fs\@$source_snap_from $source_fs\@$source_snap_to | tail -1 | sed 's/.* //g'`;
    chomp $snapshot_size;

    print colorize(" <blue>*</blue> sending to $dest_host:$dest_fs ($snapshot_size)\n");
    system("zfs send -RpecLi $source_fs\@$source_snap_from $source_fs\@$source_snap_to | $MBUFFER | $PROGRESS |
        $SSH $dest_host \"$MBUFFER | zfs recv -Fu $dest_fs\"");
}

# ----------------------------------------------------------------------------------------------------------------------
# Check existene and create target FS for backups if needed
# ----------------------------------------------------------------------------------------------------------------------

my $startTime = localtime->strftime('%Y-%m-%d %H:%M:%S');
print "-- starting at $startTime\n";

if (system("$SSH $DEST_HOST zfs list -Ho name $DEST_PATH >/dev/null 2>&1")) {
    print colorize(" <red>*</red> $DEST_PATH doesn't exist, creating\n");
    system("$SSH $DEST_HOST zfs create $DEST_PATH");
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
# Try to get remote dataset list
# ----------------------------------------------------------------------------------------------------------------------

my @remotes= `$SSH $DEST_HOST zfs list -rHo name $DEST_PATH`;
if ($? ne 0) {
    print colorize(" <red>*</red> can't get remotes for $DEST_PATH, aborting\n");
    exit 1;
}

chomp @remotes;

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

    if ($clearFlag) {
        print colorize("<light_green>Clearing snapshots for VM</light_green> $alias\n");

        if (ZFS::checkRemoteDatasetExists($DEST_HOST, "$DEST_PATH/$alias")) {
            print colorize(" <red>*</red> deleting remote backup $DEST_PATH/$alias\n");
            system("$SSH $DEST_HOST zfs destroy -r $DEST_PATH/$alias 2>/dev/null");
        }

        my @all_snaps = ZFS::getAllSnaps($zfs_filesystem);
        for my $snap (@all_snaps) {
            print colorize(" <red>*</red> deleting snapshot $snap\n");
            system("zfs destroy -r $snap");
        }

        for my $disk (@disks) {
            my $diskSuffix = substr($disk, rindex($disk, '-') + 1);
            if (ZFS::checkRemoteDatasetExists($DEST_HOST, "$DEST_PATH/$alias-$diskSuffix")) {
                print colorize(" <red>*</red> deleting remote backup $DEST_PATH/$alias-$diskSuffix\n");
                system("$SSH $DEST_HOST zfs destroy -r $DEST_PATH/$alias-$diskSuffix");
            }

            my @all_snaps = ZFS::getAllSnaps($disk);
            for my $snap (@all_snaps) {
                print colorize(" <red>*</red> deleting snapshot $snap\n");
                system("zfs destroy -r $snap");
            }
        }

        next;
    }

    print colorize("<light_green>Backing up VM</light_green> $alias\n");

    my $last_remote_snap = '';
    if ("$DEST_PATH/$alias" ~~ @remotes) {
        $last_remote_snap = ZFS::getLastRemoteSnap($DEST_HOST, "$DEST_PATH/$alias");
    }

    if ($last_remote_snap eq '') {
        print colorize(" <blue>*</blue> no remote snapshots found for dataset $zfs_filesystem\n");

        my @all_snaps = ZFS::getAllSnaps($zfs_filesystem);
        for my $snap (@all_snaps) {
            print colorize(" <red>*</red> deleting snapshot $snap\n");
            system("zfs destroy -r $snap");
        }

        for my $disk (@disks) {
            print colorize(" <blue>*</blue> no remote snapshots found for dataset $disk\n");
            my @all_snaps = ZFS::getAllSnaps($disk);
            for my $snap (@all_snaps) {
                print colorize(" <red>*</red> deleting snapshot $snap\n");
                system("zfs destroy -r $snap");
            }
        }
    } else {
        $last_remote_snap = substr($last_remote_snap, rindex($last_remote_snap, '@') + 1);
    }

    my $dataset_size = '';
    my $last_number = '';
    my $last_snap = ZFS::getLastSnap($zfs_filesystem);
    if ($last_snap) {
        $last_snap = substr($last_snap, rindex($last_snap, '@') + 1);
        $last_number = substr($last_snap, rindex($last_snap, '_') + 1);
    }
    my $next_number = '';
    my $next_snap = '';
    if ($last_number eq '') {
        $next_number = '000000';
        $next_snap = "${TAG}_${next_number}";
        print colorize(" <blue>*</blue> creating initial snapshot $zfs_filesystem\@$next_snap\n");
    } else {
        $next_number = sprintf("%06d", $last_number + 1);
        $next_snap = "${TAG}_${next_number}";
        print colorize(" <blue>*</blue> creating snapshot $zfs_filesystem\@$next_snap\n");
    }

    system("zfs snapshot -r $zfs_filesystem\@$next_snap");
    for my $disk (@disks) {
        if ($next_number eq '000000') {
            print colorize(" <blue>*</blue> creating initial snapshot $disk\@$next_snap\n");
        } else {
            print colorize(" <blue>*</blue> creating snapshot $disk\@$next_snap\n");
        }
        system("zfs snapshot -r $disk\@$next_snap");
    }

    if ($next_number eq '000000') {
        sendInitial($zfs_filesystem, $next_snap, $DEST_HOST, "$DEST_PATH/$alias");
    } else {
        sendIncremental($zfs_filesystem, $last_remote_snap, $next_snap, $DEST_HOST, "$DEST_PATH/$alias");
    }

    for my $disk (@disks) {
        my $diskSuffix = substr($disk, rindex($disk, '-') + 1);
        if ($next_number eq '000000') {
            sendInitial($disk, $next_snap, $DEST_HOST, "$DEST_PATH/$alias-$diskSuffix");
        } else {
            sendIncremental($disk, $last_remote_snap, $next_snap, $DEST_HOST, "$DEST_PATH/$alias-$diskSuffix");
        }
    }

    system("scp -q /etc/zones/$uuid.xml $DEST_HOST:/backup/xml/");
}

my $endTime = localtime->strftime('%Y-%m-%d %H:%M:%S');
print "-- ending at $endTime\n";
