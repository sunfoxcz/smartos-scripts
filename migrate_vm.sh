#!/usr/bin/bash

if [ ! $1 ]; then
	echo "Usage: <operation> <vmid>"
	exit 1
fi
if [ ! $2 ]; then
	echo "Usage: <operation> <vmid>"
	exit 1
fi

BRAND=`vmadm get $2 | json brand`
if [ ! $BRAND ]; then
	echo "VM $2 does not exists"
	exit 1
fi

# FS=`vmadm get $2 | json zonepath`
# if [ ! $FS ]; then
# 	echo "VM $2 does not exists"
# 	exit 1
# fi

FS="zones/$2"

# ORIGIN=`zfs get -H origin $FS|awk '{print $3}'`
# if [ $ORIGIN ]; then
# 	zfs send $ORIGIN | ssh vm2 zfs recv $ORIGIN
# fi

if [ $1 == "prepare" ]; then
	zfs snapshot $FS@today
	zfs send -p -R $FS@today | ssh vm2 zfs recv $FS

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $2 | json disks | json -a zfs_filesystem`; do
			zfs snapshot $d@today
			zfs send -p -R $d@today | ssh vm2 zfs recv $d
		done
	fi
fi

if [ $1 == "migrate" ]; then
	vmadm stop $2
	zfs snapshot $FS@migrate
	zfs send -p -i $FS@today $FS@migrate | ssh vm2 zfs recv $FS
	zfs snapshot zones/cores/$2@migrate
	zfs send -p zones/cores/$2@migrate | ssh vm2 zfs recv zones/cores/$2

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $2 | json disks | json -a zfs_filesystem`; do
			zfs snapshot $d@migrate
			zfs send -p -i $d@today $d@migrate | ssh vm2 zfs recv $d
		done
	fi

	scp /etc/zones/$2.xml vm2:/etc/zones/
	ssh vm2 "echo '$2:installed:/$FS:$2' >> /etc/zones/index"
	ssh vm2 vmadm start $2

	zfs destroy $FS@migrate
	zfs destroy zones/cores/$2@migrate
	ssh vm2 zfs destroy $FS@migrate
	ssh vm2 zfs destroy zones/cores/$2@migrate

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $2 | json disks | json -a zfs_filesystem`; do
			zfs destroy $d@migrate
			ssh vm2 zfs destroy $d@migrate
		done
	fi
fi

if [ $1 == "cleanup" ]; then
	ssh vm2 zfs destroy $FS@today
	# zfs destroy -r zones/cores/$2
	# zfs destroy -r zones/$2

	if [ $BRAND = "kvm" ]; then
		for d in `vmadm get $2 | json disks | json -a zfs_filesystem`; do
			ssh vm2 zfs destroy $d@today
			zfs destroy -r $d
		done
	fi

	# rm /etc/zones/$2.xml
	# cp /etc/zones/index /etc/zones/index.bak
	# cat /etc/zones/index | grep -v $2 > /etc/zones/index.new
	# mv /etc/zones/index.new /etc/zones/index
	vmadm destroy $2
fi
