#!/usr/bin/bash

P=`echo "arc_stats::print -a arcstat_p.value.ui64" | mdb -kw`
C=`echo "arc_stats::print -a arcstat_c.value.ui64" | mdb -kw`
C_MAX=`echo "arc_stats::print -a arcstat_c_max.value.ui64" | mdb -kw`

P1=`echo "$P" | cut -d ' ' -f 1`
C1=`echo "$C" | cut -d ' ' -f 1`
C_MAX1=`echo "$C_MAX" | cut -d ' ' -f 1`

printf -v P2 "%i" `echo "$P" | cut -d ' ' -f 4`
printf -v C2 "%i" `echo "$C" | cut -d ' ' -f 4`
printf -v C_MAX2 "%i" `echo "$C_MAX" | cut -d ' ' -f 4`

if [ $1 ]; then
    printf -v NEW "%x" $(($1 * 1024 * 1024))
    printf -v NEW2 "%x" $(($1 * 1024 * 1024 / 2))
    echo "$P1/Z $NEW2" | mdb -kw
    echo "$C1/Z $NEW" | mdb -kw
    echo "$C_MAX1/Z $NEW" | mdb -kw
else
    echo "arc.p $(($P2 / 1024 / 1024))"
    echo "arc.c $(($C2 / 1024 / 1024))"
    echo "arc.c_max $(($C_MAX2 / 1024 / 1024))"
fi
