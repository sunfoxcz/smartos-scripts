#!/usr/bin/bash

if [ ! $1 ]; then
	echo "Usage: <vmid> <destination> <operation>"
	exit 1
fi
if [ ! $2 ]; then
	echo "Usage: <vmid> <destination> <operation>"
	exit 1
fi
if [ ! $3 ]; then
	echo "Usage: <vmid> <destination> <operation>"
	exit 1
fi

VMID=$1
DESTINATION=$2
OPERATION=$3

ssh $DESTINATION hostname > /dev/null

if [ $? != "0" ]; then
    echo "Cannot connect SSH on hostname $DESTINATION"
    exit 1
fi

vm_shutdown() {
	# $1: VMID
	STATE=`vmadm get $1 | json state`
	if [ $STATE = "running" ]; then
		vmadm stop $1
	fi
}

vm_copy_config() {
	# $1: DESTINATION
	# $2: VMID
	# $3: FS
	echo "Copying VM config"
	ssh $1 ls /etc/zones/$2.xml > /dev/null 2>&1
	if [ $? = "0" ]; then
		ssh $1 rm /etc/zones/$2.xml
		scp /etc/zones/$2.xml $1:/etc/zones/ > /dev/null
	else
		scp /etc/zones/$2.xml $1:/etc/zones/ > /dev/null
		ssh $1 "echo '$2:installed:/$3:$2' >> /etc/zones/index"
	fi
}

zfs_promote_fs() {
	# $1: FS
	ORIGIN=`zfs get -H origin $1 | awk '{print $3}'`
	if [ $ORIGIN != "-" ]; then
		echo "Promoting FS above $ORIGIN"
		zfs promote $1
	fi
}

zfs_create_migrate_snapshot() {
	# $1: FS
	# $2: SNAPSHOT NAME
	echo "Creating snapshot $1@$2"
	SNAPSHOT=`zfs list -t snapshot -o name -H | grep ^$1@$2$`
	if [[ $SNAPSHOT != "" ]]; then
		zfs destroy $SNAPSHOT
	fi
	zfs snapshot $1@$2
}

zfs_destroy_migrate_snapshots() {
	# $1: DESTINATION
	# $2: FS
	# $3: SNAPSHOT NAME
	echo "Removing snapshot $2@$3"
	zfs destroy -r $2@$3
	ssh $1 zfs destroy -r $2@$3
}

zfs_check_target_dataset_exists() {
	# $1: DESTINATION
	# $2: FS
	ssh $1 zfs list $2 > /dev/null 2>&1
	if [ $? = "0" ]; then
		echo "Dataset $2 exists on target $1, aborting"
		exit 1
	fi
}

zfs_send_full() {
	# $1: DESTINATION
	# $2: FS
	# $3: SNAPSHOT NAME
	zfs_check_target_dataset_exists $1 $2
	# -R: Generate a replication stream package, which will replicate the
	#     specified file system, and all descendent file systems, up to the
	#     named snapshot.
	# -p: Include the dataset's properties in the stream.
	# -v: Print verbose information about the stream package generated.
	echo "Sending $2@$3 to $1"
	zfs send -Rp $2@$3 | ssh $1 zfs recv $2
}

zfs_send_increment() {
	# $1: DESTINATION
	# $2: FS
	# $3: FROM SNAPSHOT
	# $4: TO SNAPSHOT
	ssh $1 zfs rollback -r $2@$3
	# -p: Include the dataset's properties in the stream.
	# -I: Generate a stream package that sends all intermediary snapshots
	#     from the first snapshot to the second snapshot.
	echo "Sending $2@$3 increments tp $1"
	zfs send -p -i $2@$3 $2@$4 | ssh $1 zfs recv $2
}

BRAND=`vmadm get $VMID | json brand`
if [ ! $BRAND ]; then
	echo "VM $VMID does not exists"
	exit 1
fi

FS=`vmadm get $VMID | json zfs_filesystem`
if [ ! $FS ]; then
	echo "ZFS dir for VM $VMID does not exists"
	exit 1
fi

echo "VM: $VMID"
echo "Brand: $BRAND"

if [ $OPERATION = "offline" ]; then
	vm_shutdown $VMID

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $VMID | json disks | json -a zfs_filesystem`; do
			zfs_promote_fs $d
			zfs_create_migrate_snapshot $d "migrate"
			zfs_send_full $DESTINATION $d "migrate"
		done
	fi

	zfs_promote_fs $FS
	zfs_create_migrate_snapshot $FS "migrate"
	zfs_create_migrate_snapshot "zones/cores/$VMID" "migrate"

	zfs_send_full $DESTINATION $FS "migrate"
	zfs_send_full $DESTINATION "zones/cores/$VMID" "migrate"

	vm_copy_config $DESTINATION $VMID $FS

	zfs_destroy_migrate_snapshots $DESTINATION $FS "migrate"
	zfs_destroy_migrate_snapshots $DESTINATION "zones/cores/$VMID" "migrate"

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $VMID | json disks | json -a zfs_filesystem`; do
			zfs_destroy_migrate_snapshots $DESTINATION $d "migrate"
		done
	fi
fi

if [ $OPERATION = "prepare" ]; then
	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $VMID | json disks | json -a zfs_filesystem`; do
			zfs_create_migrate_snapshot $d "today"
			zfs_send_full $DESTINATION $d "today"
		done
	fi

	zfs_promote_fs $FS
	zfs_create_migrate_snapshot $FS "today"
	zfs_send_full $DESTINATION $FS "today"
fi

if [ $OPERATION = "migrate" ]; then
	vm_shutdown $VMID

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $VMID | json disks | json -a zfs_filesystem`; do
			zfs_create_migrate_snapshot $d "migrate"
			zfs_send_increment $DESTINATION $d "today" "migrate"
		done
	fi

	zfs_create_migrate_snapshot $FS "migrate"
	zfs_create_migrate_snapshot "zones/cores/$VMID" "migrate"

	zfs_send_increment $DESTINATION $FS "today" "migrate"
	zfs_send_full $DESTINATION "zones/cores/$VMID" "migrate"

	vm_copy_config $DESTINATION $VMID $FS

	ssh $DESTINATION vmadm start $VMID

	zfs_destroy_migrate_snapshots $DESTINATION $FS "migrate"
	zfs_destroy_migrate_snapshots $DESTINATION "zones/cores/$VMID" "migrate"

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $VMID | json disks | json -a zfs_filesystem`; do
			zfs_destroy_migrate_snapshots $DESTINATION $d "migrate"
		done
	fi
fi

if [ $OPERATION = "cleanup" ]; then
	zfs_destroy_migrate_snapshots $DESTINATION $FS "today"

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $VMID | json disks | json -a zfs_filesystem`; do
			zfs_destroy_migrate_snapshots $DESTINATION $d "today"
		done
	fi

	vmadm destroy $VMID
	logadm -r /zones/$VMID/root/tmp/vm.log
	logadm -r /zones/$VMID/root/tmp/vm.log.0
fi
