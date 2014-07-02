#!/usr/bin/bash

if [ ! $2 ]; then
    echo "Usage: <uuid> <mac>"
    exit 1
fi

mac=`vmadm get $1 | json nics.0.mac`
nic=`vmadm get $1 | json nics.0`
nic=${nic/$mac/$2}

echo "{\"remove_nics\": [\"$mac\"]}" | vmadm update $1
echo "{\"add_nics\": [$nic]}" | vmadm update $1
