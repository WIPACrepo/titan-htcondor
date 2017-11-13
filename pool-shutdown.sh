#!/bin/bash
pool=$1
source /tmp/env

set -x
while true; do
	sleep 10
	idle_jobs=$(condor_status -sched -af TotalIdleJobs)
	if ((idle_jobs == 0)); then
		touch $pool/pool_kill
		exit
	fi
done
