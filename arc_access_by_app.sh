#!/bin/sh

dtrace -n 'sdt:zfs::arc-hit,sdt:zfs::arc-miss { @[execname] = count() }'
