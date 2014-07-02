#!/bin/bash

vmadm boot $1 order=cd,once=d cdrom=/$2,ide
