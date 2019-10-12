#!/bin/bash

DATASETS=`zfs list -H -o name | grep "^zones\/[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}" | sed 's/zones\///g'`

for d in $DATASETS; do
    origin=`zfs get -H -o value origin zones/$d`
    echo "$d $origin"
done
