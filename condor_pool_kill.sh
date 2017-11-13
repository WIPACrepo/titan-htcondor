#!/bin/bash
pool=$1

while true; do
	sleep 10
	if [ -f "$pool/pool_kill" ]; then
		set -o xtrace
		set +o errexit
		condor_off -daemon master
		sleep 3
		killall condor_master
		sleep 3
		pkill -KILL condor # this will probably kill this and other scripts
	fi
done &
