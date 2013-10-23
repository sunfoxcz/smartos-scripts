#!/bin/bash

name=0
smp=0
m=0
for x in `ps ax|grep /smartdc/bin/qemu-system`; do
    if [ "$x" == "-name" ]; then
        name=1
        continue
    fi
    if [ "$x" == "-smp" ]; then
        smp=1
        continue
    fi
    if [ "$x" == "-m" ]; then
        m=1
        continue
    fi
    if [ "$name" == 1 ]; then
        echo -e "$x"
        name=0
    fi
    if [ "$smp" == 1 ]; then
        echo -e "\t$x"
        smp=0
    fi
    if [ "$m" == 1 ]; then
        echo -e "\t$x"
        m=0
    fi
done
