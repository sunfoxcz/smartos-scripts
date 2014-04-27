#!/bin/bash

DATASETS=`zfs list -H -o name | grep "^zones\/[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}" | sed 's/zones\///g'`
IMAGES=`imgadm list -H -o uuid`
ZONES=`vmadm list -H -o uuid`

for d in $DATASETS; do
    if [[ ! $ZONES =~ `echo $d|sed 's/-disk[0-9]*//g'` ]]; then
        if [[ ! $IMAGES =~ $d ]]; then
            echo $d
        fi
    fi
done
