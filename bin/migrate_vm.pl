#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Sys::Hostname;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Terminal qw(colorize);
use VM;
use ZFS;

# ----------------------------------------------------------------------------------------------------------------------
# Parse command line options
# ----------------------------------------------------------------------------------------------------------------------

my $force = 0;

GetOptions(
    "force|f" => \$force,
) or pod2usage(-exit => 1, -message => "Usage: $0 <vmid> <destination> <prepare|reprepare|migrate|offline|cleanup> [--force|-f]");

if (scalar(@ARGV) lt 3) {
    pod2usage(-exit => 1, -message => "Usage: $0 <vmid> <destination> <prepare|reprepare|migrate|offline|cleanup> [--force|-f]");
}

my ($vmid, $destination, $operation) = @ARGV;
my $localHostname = hostname();
my $remoteHostname = substr($destination, 0, index($destination, '.'));

# ----------------------------------------------------------------------------------------------------------------------
# Check if not already running
# ----------------------------------------------------------------------------------------------------------------------

chomp(my $migrateRunning = `pgrep -f migrate_vm\.pl`);
if ($migrateRunning ne "$$") {
    print colorize("<red>$0</red> already running, exiting\n");
    exit 1;
}

# ----------------------------------------------------------------------------------------------------------------------

sub testSsh {
    my ($server) = @_;
    system("ssh $server hostname >/dev/null") and do {
        print " \e[31m* Error\e[m: can't SSH to \e[35m$server\e[m, aborting\n";
        exit 1;
    };
}

# ----------------------------------------------------------------------------------------------------------------------

my $uuid;

if (VM::isUUID($vmid)) {
    $uuid = $vmid;
} else {
    # $vmid is not UUID, try find VM by alias
    $uuid = VM::getUuidByAlias($vmid);
    if (!$uuid) {
        print "\e[31mError\e[m: can't find VM with alias \e[35m$vmid\e[m, aborting\n";
        exit 1;
    }
}

my $vmData = VM::getData($uuid);
if (!$vmData) {
    print "\e[31mError\e[m: can't find VM with uuid \e[35m$uuid\e[m, aborting\n";
    exit 1;
}

my $alias = VM::parseProperty($vmData, 'alias');
my $brand = VM::parseProperty($vmData, 'brand');
my $state = VM::parseProperty($vmData, 'state');
my $rootFs = VM::parseProperty($vmData, 'zfs_filesystem');

print "\e[34mChecking local VM\e[m\n";
print " \e[92m*\e[m UUID: $uuid\n";
print " \e[92m*\e[m Alias: $alias\n";
print " \e[92m*\e[m Brand: $brand\n";
print " \e[92m*\e[m State: $state\n";

if (!ZFS::checkDatasetExists($rootFs)) {
    print " \e[31m* Error\e[m: dataset $rootFs doesn't exist, aborting\n";
    exit 1;
}

if ($operation eq 'prepare') {
    print "\n\e[34mChecking target machine\e[m\n";
    testSsh($destination);
    my $remoteSpace = ZFS::getRemoteSpace($destination);
    print " \e[92m*\e[m Free space: $remoteSpace\n";

    my $remoteVmData = VM::getRemoteData($destination, $uuid);
    if ($remoteVmData and !$force) {
        if ($force) {
            print " \e[92m*\e[m VM exists, forcing removal\n";
            VM::remoteDelete($destination, $uuid);
        } else {
            print " \e[31m* Error\e[m: VM exists, aborting\n";
            exit 1;
        }
    }

    print "\n\e[34mSearching for datasets\e[m\n";
    my @datasets = VM::parseDatasets($vmData);

    for my $dataset (@datasets) {
        my $origin = ZFS::getOrigin($dataset);
        if ($origin) {
            print " \e[92m*\e[m \e[35m$dataset\e[m clone of \e[35m$origin\e[m\n";
            if (!ZFS::checkRemoteDatasetExists($destination, $origin)) {
                my $image = VM::parseImageNameFromDataset($origin);
                if (VM::checkRemoteImageAvailable($destination, $image)) {
                    print " \e[92m*\e[m importing image \e[35m$image\e[m\n";
                    VM::importImage($destination, $image);
                } else {
                    print " \e[31m* Error\e[m: image \e[35m$image\e[m isn't available, aborting\n";
                    exit 1;
                }
            }
        } else {
            print " \e[92m*\e[m \e[35m$dataset\e[m\n";
        }
    }

    for my $dataset (@datasets) {
        if (ZFS::checkRemoteDatasetExists($destination, $dataset)) {
            if ($force) {
                print " \e[92m*\e[m remote dataset $dataset exists, forcing removal\n";
                ZFS::destroyRemoteDataset($destination, $dataset);
            } else {
                print " \e[31m* Error\e[m: remote dataset $dataset exists, aborting\n";
                exit 1;
            }
        }
    }

    print "\n\e[34mCreating snapshots\e[m\n";
    for my $dataset (@datasets) {
        ZFS::createMigrateSnapshot($dataset, 'today');
    }

    print "\n\e[34mSending datasets to\e[m $destination\n";
    for my $dataset (@datasets) {
        ZFS::sendFull($destination, $dataset, 'today');
    }
}

if ($operation eq 'reprepare') {
    print "\n\e[34mChecking target machine\e[m\n";
    testSsh($destination);
    my $remoteSpace = ZFS::getRemoteSpace($destination);
    print " \e[92m*\e[m Free space: $remoteSpace\n";

    print "\n\e[34mSearching for datasets\e[m\n";
    my @datasets = VM::parseDatasets($vmData);

    for my $dataset (@datasets) {
        print " \e[92m*\e[m \e[35m$dataset\e[m\n";
        if (!ZFS::checkDatasetExists("$dataset\@today")) {
            print " \e[31m* Error\e[m: dataset $dataset\@today doesn't exist, aborting\n";
            exit 1;
        }
        if (!ZFS::checkRemoteDatasetExists($destination, "$dataset\@today")) {
            print " \e[31m* Error\e[m: remote dataset $dataset\@today doesn't exist, aborting\n";
            exit 1;
        }
        if (ZFS::checkDatasetExists("$dataset\@today2")) {
            if ($force) {
                print " \e[92m*\e[m dataset $dataset\@today2 exists, forcing removal\n";
                ZFS::destroyRemoteDataset($destination, $dataset);
            } else {
                print " \e[31m* Error\e[m: dataset $dataset\@today2 exists, aborting\n";
                exit 1;
            }
        }
        if (ZFS::checkRemoteDatasetExists($destination, "$dataset\@today2")) {
            if ($force) {
                print " \e[92m*\e[m remote dataset $dataset\@today2 exists, forcing removal\n";
                ZFS::destroyRemoteDataset($destination, $dataset);
            } else {
                print " \e[31m* Error\e[m: remote dataset $dataset\@today2 exists, aborting\n";
                exit 1;
            }
        }
    }

    print "\n\e[34mCreating snapshots\e[m\n";
    for my $dataset (@datasets) {
        ZFS::createMigrateSnapshot($dataset, 'today2');
    }

    print "\n\e[34mSending datasets to\e[m $destination\n";
    for my $dataset (@datasets) {
        ZFS::sendIncrement($destination, $dataset, 'today', 'today2');
    }

    print "\n\e[34mRenaming datasets\n";
    for my $dataset (@datasets) {
        ZFS::destroyDataset("$dataset\@today");
        ZFS::destroyRemoteDataset($destination, "$dataset\@today");
        ZFS::renameDataset("$dataset\@today2", "$dataset\@today");
        ZFS::renameRemoteDataset($destination, "$dataset\@today2", "$dataset\@today");
    }
}

if ($operation eq 'migrate') {
    if ($state eq 'running') {
        print " \e[92m*\e[m stopping local VM\n";
        VM::stop($uuid);
        $state = VM::getState($uuid);
    }
    if ($state ne 'stopped') {
        print " \e[31m* Error\e[m: strange VM state $state, aborting\n";
        exit 1;
    }

    print "\n\e[34mChecking target machine\e[m\n";

    testSsh($destination);

    my @datasets = VM::parseDatasets($vmData);
    for my $dataset (@datasets) {
        if (!ZFS::checkRemoteDatasetExists($destination, "$dataset\@today")) {
            print " \e[31m* Error\e[m: dataset $dataset\@today missing, aborting\n";
            exit 1;
        }
    }

    print "\n\e[34mCreating snapshots\e[m\n";
    for my $dataset (@datasets) {
        ZFS::createMigrateSnapshot($dataset, 'migrate');
    }
    ZFS::createMigrateSnapshot("zones/cores/$uuid", 'migrate');

    print "\n\e[34mSending datasets to\e[m $destination\n";
    for my $dataset (@datasets) {
        ZFS::sendIncrement($destination, $dataset, 'today', 'migrate');
    }
    ZFS::sendFull($destination, "zones/cores/$uuid", 'migrate');

    print "\n\e[34mTarget machine\e[m\n";
    print " \e[92m*\e[m creating remote VM config\n";
    VM::copyConfig($destination, $uuid);
    print " \e[92m*\e[m starting remote VM\n";
    VM::remoteStart($destination, $uuid);

    print "\n\e[34mDestroying migrate datasets\n";
    for my $dataset (@datasets) {
        ZFS::destroyMigrateSnapshot($destination, $dataset, 'migrate');
    }
    ZFS::destroyMigrateSnapshot($destination, "zones/cores/$uuid", 'migrate');
}

if ($operation eq 'cleanup') {
    print "\n\e[34mTarget machine\e[m\n";

    testSsh($destination);

    my @datasets = VM::parseDatasets($vmData);
    for my $dataset (@datasets) {
        ZFS::destroyMigrateSnapshot($destination, $dataset, 'today');
    }

    print "\n\e[34mLocal machine\e[m\n";
    print " \e[92m*\e[m deleting VM\n";
    VM::delete($uuid);
    print " \e[92m*\e[m deleting logadm entries\n";
    system("logadm -r /zones/$uuid/root/tmp/vm.log");
    system("logadm -r /zones/$uuid/root/tmp/vm.log.0");
}
