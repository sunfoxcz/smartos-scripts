#!/bin/bash

IFS=$'\n'
vms=($(vmadm list -H -o alias,ram))

total_ram='0'
for vm in "${vms[@]}"
do
    ram=`echo $vm|awk '{print $2}'`
    let "total_ram = $total_ram + $ram"
done

let "total_ram = $total_ram / 1024"
echo "Total RAM: ${total_ram} GB"
