#!/bin/bash
# create pool_kill file on certain conditions

pool=$1
out_of_jobs_shutdown_delay=60
source /tmp/env

while ! test -f "$pool/pool_kill"; do
	sleep 20
	idle_jobs=$(condor_status -sched -af TotalIdleJobs)
	#dyn_slots=$(condor_status -con DynamicSlot -af Machine | wc -l)
	#part_slots=$(condor_status -con PartitionableSlot -af Machine |wc -l)
	if ((idle_jobs == 0)); then
		touch $pool/pool_no_idle_jobs
		running_jobs=$(condor_status -sched -af TotalRunningJobs)
		if ((running_jobs > 0)); then
			sleep $out_of_jobs_shutdown_delay
		fi
		condor_off -all -daemon startd
		sleep 5
		condor_off -all
		sleep 3
		touch $pool/pool_kill
		break
	fi
done

{
	echo ----
	condor_status
	condor_q -currentrun -nob -wide
} &>> $pool/pool_last_state

