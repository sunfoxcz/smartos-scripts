#!/bin/bash

ZONES=`zfs list -H -o name | grep "^zones\/[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}" | sed 's/zones\///g'`
# SNAPS=`zfs list -H -t snapshot -o name`
IMAGES=`imgadm list -H -o uuid`

today=`date +%Y-%m-%d`
old=`TZ=GMT+119 date +%Y-%m-%d`

for z in $ZONES; do
    if [[ ! $IMAGES =~ $z ]]; then
        for s in `zfs list -H -t snapshot -o name | grep $z@ | sed 's/.*@//g'`; do
            if [[ $s == $old ]]; then
                zfs destroy zones/$z@$s
            fi
            if [[ $s == $today ]]; then
                zfs destroy zones/$z@$s
            fi
        done
        zfs snapshot zones/$z@$today
        #zfs send zones/$z@$today | gzip -9 > /zones/backup/$z.$today.gz
    fi
done
