#!/bin/bash

function condor_setup_common() {
	local pool=$1
	export _CONDOR_LOCAL_DIR=$pool/nodes/$(hostname)
	mkdir -p $_CONDOR_LOCAL_DIR
	local ipaddr="$(ip -4 addr show dev ipogif0 | awk -F '[ /]+' '/inet/{print $3}')"
	echo $ipaddr >> $pool/pool_nodes
	export _CONDOR_NETWORK_INTERFACE=$ipaddr
	export _CONDOR_LOCAL_CONFIG_DIR=$pool/config
	export _CONDOR_EXECUTE=/tmp/execute
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
		CLAIM_WORKLIFE = -1
		PROCD_ADDRESS = /tmp/procd_pipe
		LOCK = /tmp
		MAX_JOBS_PER_SUBMISSION = 100000

		CONDOR_ADMIN =
		SCHEDD_RESTART_REPORT =
		ENABLE_KERNEL_TUNING = False
		ALLOW_DAEMON = *
		HOSTALLOW_ADMINISTRATOR = *
		
		LOG = \$(LOCAL_DIR)
		RUN = \$(LOCAL_DIR)
		LOCK = \$(LOCAL_DIR)
		MAX_DEFAULT_LOG = 0
		EVENT_LOG_MAX_SIZE = 0
		ENABLE_HISTORY_ROTATION = False

		RUNBENCHMARKS = False
		use feature : GPUs
		GPU_DISCOVERY_EXTRA = -extra
		SLOT_TYPE_1 = auto
		SLOT_TYPE_1_PARTITIONABLE = TRUE
		NUM_SLOTS_TYPE_1 = 1
		
		# Titan nodes have no swap, and if a node runs out of memory, the
		# entire aprun "application" may be killed (including processes on
		# other machines), or condor may crash. Because of that, and because
		# Condor may not catch rapidly increasing memory consumption, set the
		# limit to be conservative.
		job_age = (time() - JobCurrentStartDate)
		time_hold = ((\$(job_age) > 1.5 * \$(hour)) is True)
		mem_used = ImageSize/1024/1024
		mem_hold = ((\$(mem_used) > 20000) is True)
		WANT_HOLD = (\$(mem_hold) || \$(time_hold))
		PREEMPT = \$(WANT_HOLD)
		WANT_HOLD_REASON = strcat(\
			ifthenelse(\$(time_hold) is True, strcat("t ", interval(\$(job_age))), ""), \
			ifthenelse(\$(mem_hold) is True, strcat("m ", \$(mem_used)), "") \
		)
	EOF
}

function monitor_host() {
	local d=$1
	local pool=$2
	dstat -t -cngy -p --proc-count -l --mem --tcp >> $d/dstat &
	nvidia-smi dmon -o DT -s um >> $d/dmon || true &
	for ((;;)); do
		dmesg | ts > $d/dmesg
		sleep 60
	done &
}

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
	pgrep condor && sleep 5
	kill -KILL -1
}
