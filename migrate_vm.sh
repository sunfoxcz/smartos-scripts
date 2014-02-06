#!/usr/bin/bash

if [ ! $1 ]; then
	echo "Usage: <operation> <vmid> <destination>"
	exit 1
fi
if [ ! $2 ]; then
	echo "Usage: <operation> <vmid> <destination>"
	exit 1
fi
if [ ! $3 ]; then
	echo "Usage: <operation> <vmid> <destination>"
	exit 1
fi

BRAND=`vmadm get $2 | json brand`
if [ ! $BRAND ]; then
	echo "VM $2 does not exists"
	exit 1
fi

FS=`vmadm get $2 | json zfs_filesystem`
if [ ! $FS ]; then
	echo "ZFS dir for VM $2 does not exists"
	exit 1
fi

if [ $1 == "offline" ]; then
	zfs snapshot $FS@today
	zfs send -p -R $FS@today | ssh $3 zfs recv $FS
	zfs snapshot zones/cores/$2@migrate
	zfs send -p zones/cores/$2@migrate | ssh $3 zfs recv zones/cores/$2

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $2 | json disks | json -a zfs_filesystem`; do
			zfs snapshot $d@today
			zfs send -p -R $d@today | ssh $3 zfs recv $d
		done
	fi

	scp /etc/zones/$2.xml $3:/etc/zones/
	ssh $3 "echo '$2:installed:/$FS:$2' >> /etc/zones/index"
	ssh $3 vmadm start $2

	zfs destroy $FS@today
	zfs destroy zones/cores/$2@today
	ssh $3 zfs destroy $FS@today
	ssh $3 zfs destroy zones/cores/$2@today

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $2 | json disks | json -a zfs_filesystem`; do
			zfs destroy $d@today
			ssh $3 zfs destroy $d@today
		done
	fi
fi

if [ $1 == "prepare" ]; then
	#ORIGIN=`zfs get -H origin $FS|awk '{print $3}'`
	#ORIGIN_BASE=${ORIGIN/@*/}
	#if [ $ORIGIN ]; then
	#	zfs send -R $ORIGIN | ssh $3 zfs recv $ORIGIN_BASE
	#fi

	zfs snapshot $FS@today
	zfs send -p -R $FS@today | ssh $3 zfs recv $FS

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $2 | json disks | json -a zfs_filesystem`; do
			zfs snapshot $d@today
			zfs send -p -R $d@today | ssh $3 zfs recv $d
		done
	fi
fi

if [ $1 == "migrate" ]; then
	vmadm stop $2
	zfs snapshot $FS@migrate
	zfs send -p -i $FS@today $FS@migrate | ssh $3 zfs recv $FS
	zfs snapshot zones/cores/$2@migrate
	zfs send -p zones/cores/$2@migrate | ssh $3 zfs recv zones/cores/$2

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $2 | json disks | json -a zfs_filesystem`; do
			zfs snapshot $d@migrate
			zfs send -p -i $d@today $d@migrate | ssh $3 zfs recv $d
		done
	fi

	scp /etc/zones/$2.xml $3:/etc/zones/
	ssh $3 "echo '$2:installed:/$FS:$2' >> /etc/zones/index"
	ssh $3 vmadm start $2

	zfs destroy $FS@migrate
	zfs destroy zones/cores/$2@migrate
	ssh $3 zfs destroy $FS@migrate
	ssh $3 zfs destroy zones/cores/$2@migrate

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $2 | json disks | json -a zfs_filesystem`; do
			zfs destroy $d@migrate
			ssh $3 zfs destroy $d@migrate
		done
	fi
fi

if [ $1 == "cleanup" ]; then
	ssh $3 zfs destroy $FS@today

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $2 | json disks | json -a zfs_filesystem`; do
			ssh $3 zfs destroy $d@today
		done
	fi

	vmadm destroy $2
fi
