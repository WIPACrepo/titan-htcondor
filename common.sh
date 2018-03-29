#!/bin/bash

function condor_setup_common() {
	local pool=$1
	mkdir -p /tmp/$USER/ # used in condor config
	export _CONDOR_LOCAL_DIR=$pool/nodes/$(hostname)
	mkdir -p $_CONDOR_LOCAL_DIR
	local ipaddr="$(ip -4 addr show dev ipogif0 | awk -F '[ /]+' '/inet/{print $3}')"
	echo $ipaddr >> $pool/pool_nodes
	export _CONDOR_NETWORK_INTERFACE=$ipaddr
	export _CONDOR_LOCAL_CONFIG_DIR=$pool/config
	export _CONDOR_EXECUTE=/tmp/$USER/execute
	mkdir -p $_CONDOR_EXECUTE
}

function create_pool_config() {
	local pool=$1
	local host=$2
	mkdir -p $pool/config
	cat <<- EOF > $pool/config/00_pool
		CONDOR_HOST = $host
		CONDOR_FSYNC = False
		FILESYSTEM_DOMAIN = titan
		MAX_FILE_DESCRIPTORS = 80000
		COLLECTOR_MAX_FILE_DESCRIPTORS = 80000
		SCHEDD_MAX_FILE_DESCRIPTORS = 80000
		# Since we only run jobs of the same user, avoid idle time on
		# workers waiting for negotiator.
		CLAIM_WORKLIFE = -1
		# Shadow starts noisy in the logs, so make shadows live longer.
		SHADOW_WORKLIFE = 36000
		MAX_JOBS_PER_SUBMISSION = 100000
		# We want frequent updates about jobs memory usage, since nodes
		# running out of memory may turn them into black holes or kill
		# the intire aprun group.
		STARTER_UPDATE_INTERVAL = 120
		STARTER_UPDATE_INTERVAL_TIMESLICE = 0.5
		SHADOW_QUEUE_UPDATE_INTERVAL = 120
		MAX_PERIODIC_EXPR_INTERVAL = 300
		PERIODIC_EXPR_TIMESLICE = 0.1

		CONDOR_ADMIN =
		SCHEDD_RESTART_REPORT =
		ENABLE_KERNEL_TUNING = False
		ALLOW_DAEMON = *
		HOSTALLOW_ADMINISTRATOR = *
		
		# Keep non-essential logs and temporary files on local filesystem
		# to reduce load on Lustre.
		RUN = /tmp/$USER
		LOCK = /tmp/$USER
		MAX_DEFAULT_LOG = 0
		LOG = \$(LOCAL_DIR)
		PROCD_LOG = /tmp/$USER/ProcLog
		STARTER_STATS_LOG = /tmp/$USER/XferStatsLog
		SHARED_PORT_LOG = /tmp/$USER/SharedPortLog
		NEGOTIATOR_MATCH_LOG = /tmp/$USER/MatchLog

		RUNBENCHMARKS = False
		use feature : GPUs
		GPU_DISCOVERY_EXTRA = -extra
		SLOT_TYPE_1 = auto
		SLOT_TYPE_1_PARTITIONABLE = TRUE
		NUM_SLOTS_TYPE_1 = 1
		
		# Titan nodes have no swap, and if a node runs out of memory, the
		# entire aprun "application" may be killed (including processes on
		# other machines), or condor may crash, or a strange condition may
		# occur when condor keeps running, but all jobs segfault, turning
		# the node into a black hole. Because of that, and because Condor 
		# may not catch rapidly increasing memory consumption (in part since
		# cgroups are not available), set the limit to be conservative.
		# It would be better to do this on startd, but I couldn't get that
		# to work.
		job_age = ifthenelse(JobCurrentStartDate is Undefined, 1, time() - JobCurrentStartDate)
		time_hold = ((\$(job_age) > 1.5 * \$(hour)) is True)
		mem_used = ifthenelse(MemoryUsage is Undefined, 0, MemoryUsage)
		mem_hold = ((\$(mem_used) > 15000) is True)
		SYSTEM_PERIODIC_HOLD = (JobStatus == 2 && (\$(mem_hold) || \$(time_hold)))
		SYSTEM_PERIODIC_HOLD_REASON = strcat(\
			ifthenelse(\$(time_hold) is True, strcat("t ", interval(\$(job_age))), ""), \
			ifthenelse(\$(mem_hold) is True, strcat("m ", \$(mem_used)), "") \
		)
	EOF
}

function monitor_host() {
	local d=$1
	local pool=$2
	# Only write stats every 5 seconds to reduce load on lustre
	# (only matters for big jobs).
	dstat -t -cngy -p --proc-count -l --mem --tcp 5 >> $d/dstat &
	nvidia-smi dmon -o DT -s um -d 5 >> $d/dmon || true &
}

# This is messy, and is not currently used
function monitor_networking() {
	local d=$1
	local pool=$2
	for ((;;)); do
		nmap --host-timeout 1 -Pn -p 22 $(<$pool/pool_nodes) &>> $d/nmap_pool_nodes
		nmap --host-timeout 1 -Pn -p 22 $(awk '/login/{print $1}' /etc/hosts) &>> $d/nmap_login_hosts
		sleep 60
	done &
	for ((;;)); do
		ifconfig |& ts >> $d/ifconfig
		netstat -anpl | ts >> $d/netstat
		netstat -s | ts >> $d/netstat
		# ping fails with permission error, so don't use it
		nc -v -w 1 $(<$pool/cm_addr) 22 <<< "" |& ts >> $d/nc
		sleep 10
	done &
}

# stop condor if $pool/pool_kill exists
function shutdown_on_pool_kill() {
	local pool=$1
	while ! test -f "$pool/pool_kill"; do
		sleep 10
	done
	condor_off -daemon master
	pgrep condor && (echo "Some condor daemons still alive"; sleep 5)
	kill -KILL -1
}
