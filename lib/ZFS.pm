package ZFS;

use strict;
use warnings;

use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

our $VERSION     = 1.00;
our @ISA         = qw(Exporter);
our @EXPORT      = ();
our @EXPORT_OK   = qw(
    checkDatasetExists
    checkRemoteDatasetExists
    getOrigin
    getAllSnaps
    getLastSnap
    getLastSequence
    getRemoteSpace
    createMigrateSnapshot
    sendFull
    sendIncrement
    destroyMigrateSnapshot
    destroyDataset
    destroyRemoteDataset
);
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

our $TAG = 'backup';
# -q: Be quiet
# -s: Block size, 128k is default for ZFS
# -m: Buffer size
our $MBUFFER = '/opt/local/bin/mbuffer -q -s 128k -m 1G';
# -r: Display the current rate of data transfer
# -t: Display the total elapsed time
# -a: Display the average rate of data transfer so far
# -b: Display the total amount of data transferred so far
our $PV = 'pv -rtab';
# -T: Disable pseudo-terminal allocation
# -c: Selects the cipher specification for encrypting the session
# -o: Set options
# -x: Disable X11 forwarding
our $SSH = 'ssh -T -c aes128-ctr -o Compression=no -x';

sub checkDatasetExists {
    my ($fs) = @_;
    system("zfs list $fs >/dev/null 2>&1") and do {
        return 0;
    };
    return 1;
}

sub checkRemoteDatasetExists {
    my ($server, $fs) = @_;
    system("$SSH $server zfs list $fs >/dev/null 2>&1") and do {
        return 0;
    };
    return 1;
}

sub getOrigin {
    my ($fs) = @_;
    my $origin = `zfs get -Ho value origin $fs`;
    $origin =~ s/\s+$//;
    return $origin eq '-' ? '' : $origin;
}

sub getAllSnaps {
    my ($fs) = @_;
    my @snaps = `zfs list -t snapshot -Ho name -r $fs |
       sed -n "/\@${TAG}_[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/"p |
       grep $fs@ | sort`;
   chomp @snaps;
   return @snaps;
}

# prints out last snapshot zrep created, going purely by sequence.
# Note: "last created", which may or may NOT be "last successfully synced".
# This is basically "getallsnaps |tail -1"
sub getLastSnap {
    my ($fs) = @_;
    my $snap = `zfs list -t snapshot -rHo name $fs |
       sed -n "/\@${TAG}_[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/"p |
       sort | tail -1`;
   chomp $snap;
   return $snap;
}

sub getLastRemoteSnap {
    my ($server, $fs) = @_;
    my $snap = `$SSH $server zfs list -t snapshot -rHo name $fs |
        sed -n "/\@${TAG}_[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/"p |
        sort | tail -1`;
    chomp $snap;
    return $snap;
}

# By observation, 'zfs list' shows snapshots order of creation.
# last listed, should be last in sequence.
# But, dont take chances!!
sub getLastSequence {
    my ($fs) = @_;
    my ($sequence) = ($fs =~ m/\@${TAG}_([0-9a-fA-F]{6})/);
    return $sequence;
}

# Get space available on remote machine
sub getRemoteSpace {
    my ($server) = @_;
    my $space = `$SSH $server zfs get -Ho value available zones`;
    chomp $space;
    return $space;
}

sub createMigrateSnapshot {
    my ($fs, $snapshotName) = @_;
    my $snapshot = "$fs\@$snapshotName";
    my $exists = 0;

    system("zfs list -Ho name $snapshot >/dev/null 2>&1") or do {
        $exists = 1;
        system("zfs destroy -r $snapshot") and do {
            print " \e[31m* Error\e[m: can't destroy earlier snapshot \e[35m$snapshot\e[m, aborting\n";
            exit 1;
        };
    };

    if ($exists) {
        print " \e[92m*\e[m recreating snapshot \e[35m$snapshot\e[m\n";
    } else  {
        print " \e[92m*\e[m creating snapshot \e[35m$snapshot\e[m\n";
    }

    system("zfs snapshot -r $snapshot") and do {
        print " \e[31m* Error\e[m: can't create snapshot \e[35m$snapshot\e[m, aborting\n";
        exit 1;
    };
}

sub sendFull {
    my ($server, $fs, $snapshotName) = @_;
    my $snapshot = "$fs\@$snapshotName";
    my $dataset_size = `zfs get -Ho value used $fs`;
    chomp $dataset_size;

    # ZFS SEND
    # -R: replicate recursively
    # -p: include the dataset's properties in the stream (implicit for -R)
    # -e: generate a more compact stream by using WRITE_EMBEDDED records
    # -c: generate a more compact stream by using compressed WRITE records
    print " \e[92m*\e[m sending \e[35m$snapshot\e[m ($dataset_size)\n";
    system("zfs send -Rpec $snapshot | $MBUFFER | $PV | $SSH $server \"$MBUFFER | zfs recv $fs\"") and do {
        print " \e[31m* Error\e[m: can't send \e[35m$snapshot\e[m, aborting\n";
        exit 1;
    };
}

sub sendIncrement {
    my ($server, $fs, $sourceSnapshot, $targetSnapshot) = @_;
    my $source = "$fs\@$sourceSnapshot";
    my $target = "$fs\@$targetSnapshot";
    my $snapshot_size = `zfs send -nvI $source $target | tail -1 | sed 's/.* //g'`;
    chomp $snapshot_size;

    system("$SSH $server zfs rollback -r $source") and do {
        print " \e[31m* Error\e[m: can't rollback \e[35m$source\e[m, aborting\n";
        exit 1;
    };

    # -p: include the dataset's properties in the stream.
    # -i: generate an incremental stream from the first snapshot to the second snapshot
    print " \e[92m*\e[m sending \e[35m$source\e[m increments ($snapshot_size)\n";
    system("zfs send -pi $source $target | $MBUFFER | $PV | $SSH $server \"$MBUFFER | zfs recv $fs\"") and do {
        print " \e[31m* Error\e[m: can't send \e[35m$source\e[m, aborting\n";
        exit 1;
    };
}

sub renameDataset {
    my ($oldName, $newName) = @_;
    print " \e[92m*\e[m ranaming snapshot \e[35m$oldName\e[m to \e[35m$newName\e[m\n";
    system("zfs rename $oldName $newName") and do {
        print " \e[31m* Error\e[m: can't rename dataset \e[35m$oldName\e[m, aborting\n";
        exit 1;
    };
}

sub renameRemoteDataset {
    my ($server, $oldName, $newName) = @_;
    print " \e[92m*\e[m ranaming remote snapshot \e[35m$oldName\e[m to \e[35m$newName\e[m\n";
    system("$SSH $server zfs rename $oldName $newName") and do {
        print " \e[31m* Error\e[m: can't rename remote dataset \e[35m$oldName\e[m, aborting\n";
        exit 1;
    };
}

sub destroyMigrateSnapshot {
    my ($server, $fs, $snapshotName) = @_;
    my $snapshot = "$fs\@$snapshotName";

    print " \e[92m*\e[m destroying snapshot \e[35m$snapshot\e[m\n";
    destroyRemoteDataset($server, $snapshot);
    destroyDataset($snapshot);
}

sub destroyDataset {
    my ($fs) = @_;
    system("zfs destroy -r $fs") and do {
        print " \e[31m* Error\e[m: can't destroy target dataset \e[35m$fs\e[m, aborting\n";
        exit 1;
    };
}

sub destroyRemoteDataset {
    my ($server, $fs) = @_;
    system("$SSH $server zfs destroy -r $fs") and do {
        print " \e[31m* Error\e[m: can't destroy target dataset \e[35m$fs\e[m, aborting\n";
        exit 1;
    };
}

1;
