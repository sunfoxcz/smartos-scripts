package VM;

use strict;
use warnings;

use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

our $VERSION     = 1.00;
our @ISA         = qw(Exporter);
our @EXPORT      = ();
our @EXPORT_OK   = qw(
    isUUID
    checkRemoteImageAvailable
    getUuidByAlias
    getData
    getState
    getRemoteData
    parseProperty
    parseDatasets
    parseImageNameFromDataset
    importImage
    copyConfig
    stop
    remoteStart
    delete
    remoteDelete
);
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

sub isUUID {
    my ($uuid) = @_;
    return $uuid =~ /[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}/;
}

sub checkRemoteImageAvailable {
    my ($server, $image) = @_;
    chomp(my $imgadmOutput = `imgadm avail uuid=$image`);
    if ($imgadmOutput eq '') {
        return 0;
    }

    return 1;
}

sub getUuidByAlias {
    my ($alias) = @_;
    my $uuid = `vmadm list -Ho uuid alias=$alias 2>/dev/null`;
    $uuid =~ s/\s+$//;
    return $uuid;
}

sub getData {
    my ($uuid) = @_;
    my $vmdata = `vmadm get $uuid 2>/dev/null`;
    return $vmdata;
}

sub getState {
    my ($uuid) = @_;
    my $state = `vmadm get $uuid 2>/dev/null | json state`;
    $state =~ s/\s+$//;
    return $state;
}

sub getRemoteData {
    my ($server, $uuid) = @_;
    my $vmdata = `ssh $server vmadm get $uuid 2>/dev/null`;
    return $vmdata;
}

sub parseProperty {
    my ($data, $property) = @_;
    my $value = `echo '$data' | json $property`;
    $value =~ s/\s+$//;
    return $value;
}

sub parseDatasets {
    my ($data) = @_;
    my $brand = parseProperty($data, 'brand');

    my $rootFs = `echo '$data' | json zfs_filesystem`;
    $rootFs =~ s/\s+$//;
    my @datasets = ($rootFs);

    if ($brand eq 'kvm') {
        my @disks = `echo '$data' | json disks | json -a zfs_filesystem`;
        chomp @disks;
        push(@datasets, @disks);
    }
    return @datasets;
}

sub parseImageNameFromDataset {
    my ($fs) = @_;
    my $image = substr($fs, rindex($fs, '/') + 1);
    $image = substr($image, 0, index($image, '@'));
    return $image;
}

sub importImage {
    my ($server, $image) = @_;
    system("ssh $server imgadm import $image") and do {
        print " \e[31m* Error\e[m: can't import image \e[35m$image\e[m, aborting\n";
        exit 1;
    };
}

sub copyConfig {
    my ($server, $uuid) = @_;
    system("vmadm get $uuid | json -e \"for(i in this.disks){this.disks[i].nocreate=true;this.disks[i].refreservation=undefined;this.disks[i].image_uuid=undefined;}this.i=undefined;\" | ssh $server vmadm create 2>/dev/null") and do {
        print " \e[31m* Error\e[m: can't create VM \e[35m$uuid\e[m, aborting\n";
        exit 1;
    };
}

sub stop {
    my ($uuid) = @_;
    system("vmadm stop $uuid 2>/dev/null") and do {
        print " \e[31m* Error\e[m: can't stop VM \e[35m$uuid\e[m, aborting\n";
        exit 1;
    };
}

sub remoteStart {
    my ($server, $uuid) = @_;
    system("ssh $server vmadm start $uuid 2>/dev/null") and do {
        print " \e[31m* Error\e[m: can't start remote VM \e[35m$uuid\e[m, aborting\n";
        exit 1;
    };
}

sub delete {
    my ($uuid) = @_;
    system("vmadm delete $uuid 2>/dev/null") and do {
        print " \e[31m* Error\e[m: can't delete VM \e[35m$uuid\e[m, aborting\n";
        exit 1;
    };
}

sub remoteDelete {
    my ($server, $uuid) = @_;
    system("ssh $server vmadm delete $uuid 2>/dev/null") and do {
        print " \e[31m* Error\e[m: can't delete remote VM \e[35m$uuid\e[m, aborting\n";
        exit 1;
    };
}

1;
