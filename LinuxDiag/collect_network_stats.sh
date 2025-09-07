#!/bin/bash

# include helper functions
source ./pssdiag_support_functions.sh

#if inside container exit 0 
pssdiag_inside_container_get_instance_status
if [ "${is_instance_inside_container_active}" == "YES" ]; then
    exit 0
fi


OS_COUNTERS_INTERVAL=$1

working_dir="$PWD"
mkdir -p $PWD/output
outputdir=$PWD/output
if [ "$EUID" -eq 0 ]; then
  group=$(id -gn "$SUDO_USER")
  chown "$SUDO_USER:$group" "$outputdir" -R
else
	chown $(id -u):$(id -g) "$outputdir" -R
fi

LC_TIME=en_US.UTF-8 sar -n DEV $OS_COUNTERS_INTERVAL >> $outputdir/${HOSTNAME}_os_network_stats.perf &
printf "%s\n" "$!" >> $outputdir/pssdiag_stoppids_os_collectors.log






