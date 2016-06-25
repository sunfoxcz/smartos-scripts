#!/bin/bash

cores=$(zfs list | grep ^zones/cores/.* | grep -v global | awk '{print $1}' | sed 's#zones/cores/##g')
vms=$(vmadm list -H -o uuid)

for vm in $vms;
do
	if [[ ! $cores =~ $vm ]]; then
		echo "Creating core for zone $vm"
		zfs create -o mountpoint=/zones/$vm/cores -o quota=100G zones/cores/$vm
	fi
done
