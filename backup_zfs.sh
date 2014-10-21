#!/bin/bash

ZFSNAP=/backup/scripts/zfsnap/sbin/zfsnap.sh
ZONES=$(zfs list -H -o name | grep "^zones\/[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}" | sed 's/zones\///g')
IMAGES=$(imgadm list -H -o uuid)
HOUR=$(date +%H)

for zone in $ZONES; do
    if [[ ! $IMAGES =~ $zone ]]; then
        if [ "$HOUR" == "01" ]; then
            $ZFSNAP snapshot -a 1w -z zones/$zone
        else
            $ZFSNAP snapshot -a 1d -z zones/$zone
        fi
        $ZFSNAP destroy zones/$zone
        #zfs send zones/$z@$today | gzip -9 > /zones/backup/$z.$today.gz
    fi
done
