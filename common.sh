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
		CONDOR_HOST=$host
		CONDOR_FSYNC = False
		FILESYSTEM_DOMAIN = titan
		MAX_FILE_DESCRIPTORS = 80000
		COLLECTOR_MAX_FILE_DESCRIPTORS = 80000
		SCHEDD_MAX_FILE_DESCRIPTORS = 80000
		JobLeaseDuration = 600
		SUBMIT_EXPRS = \$(SUBMIT_EXPRS) JobLeaseDuration

		CONDOR_ADMIN =
		SCHEDD_RESTART_REPORT =
		ENABLE_KERNEL_TUNING = False
		ALLOW_DAEMON = *
		HOSTALLOW_ADMINISTRATOR = *
		
		LOG = \$(LOCAL_DIR)
		RUN = \$(LOCAL_DIR)
		LOCK = \$(LOCAL_DIR)
		MAX_DEFAULT_LOG = 0

		RUNBENCHMARKS = False
		use feature : GPUs
		GPU_DISCOVERY_EXTRA = -extra
		SLOT_TYPE_1 = auto
		SLOT_TYPE_1_PARTITIONABLE = TRUE
		NUM_SLOTS_TYPE_1 = 1
		
		# Titan nodes have no swap, and if a node runs out of memory, the
		# entire aprun "application" may be killed, or condor may crash.
		# Because of that, and because Condor may not catch rapidly increasing
		# memory consumption, set the limit to be conservative.
		MEMORY_TOO_HIGH = (isDefined(MemoryUsage) && MemoryUsage > 20000)
		use POLICY : WANT_HOLD_IF(MEMORY_TOO_HIGH, 102, "memory too high")
	EOF
}

function monitor_connectivity() {
	local d=$1
	local pool=$2
	for ((;;)); do
		nmap --host-timeout 1 -Pn -p 22 $(<$pool/pool_nodes) &>> $d/nmap_pool_nodes
		sleep 5
		nmap --host-timeout 1 -Pn -p 22 $(awk '/login/{print $1}' /etc/hosts) &>> $d/nmap_login_hosts
		sleep 5
	done
}

function monitor_host() {
	local d=$1
	local pool=$2
	dstat -t -cngy -p --proc-count -l --mem --tcp >> $d/dstat &
	nvidia-smi dmon -o DT -s um >> $d/dmon || true &
	monitor_connectivity $d $pool &
	for ((;;)); do
		dmesg | ts > $d/dmesg
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
	while true; do
		sleep 10
		if [ -f "$pool/pool_kill" ]; then
			condor_off -daemon master
			sleep 6
			killall condor_master
			sleep 3
			kill -INT -1
			sleep 1
			kill -KILL -1
		fi
	done
}
