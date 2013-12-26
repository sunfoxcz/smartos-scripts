#!/usr/bin/bash

if [ ! $1 ]; then
    echo "Usage: <uuid> <ip> <mask> <gateway>"
    exit 1
fi
if [ ! $2 ]; then
    echo "Usage: <uuid> <ip> <mask> <gateway>"
    exit 1
fi
if [ ! $3 ]; then
    echo "Usage: <uuid> <ip> <mask> <gateway>"
    exit 1
fi
if [ ! $4 ]; then
    echo "Usage: <uuid> <ip> <netmask> <gateway>"
    exit 1
fi

MAC=`vmadm get $1 | json nics.0.mac`
UPDATE="{ \"update_nics\" : [{ \"mac\": \"$MAC\", \"ip\": \"$2\", \"netmask\": \"$3\", \"gateway\": \"$4\" }] }"

echo $UPDATE | vmadm update $1
