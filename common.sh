#!/bin/bash

function condor_setup_common() {
	pool=$1
	export _CONDOR_LOCAL_DIR=$pool/nodes/$(hostname)
	mkdir -p $_CONDOR_LOCAL_DIR
	export _CONDOR_NETWORK_INTERFACE="$(ip -4 addr show dev ipogif0 | awk -F '[ /]+' '/inet/{print $3}')"
	export _CONDOR_LOCAL_CONFIG_DIR=$pool/config
	export _CONDOR_EXECUTE=/tmp/execute
	mkdir -p $_CONDOR_EXECUTE
}

function create_pool_config() {
	pool=$1
	host=$2
	mkdir -p $pool/config
	cat <<- EOF > $pool/config/00_pool
		CONDOR_HOST=$host
		CONDOR_FSYNC = False
		FILESYSTEM_DOMAIN = titan
		MAX_FILE_DESCRIPTORS = 80000
		COLLECTOR_MAX_FILE_DESCRIPTORS = 80000
		SCHEDD_MAX_FILE_DESCRIPTORS = 80000
		CLAIM_WORKLIFE = -1
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
	EOF
}

# stop condor if $pool/pool_kill exists
function shutdown_on_pool_kill() {
	pool=$1
	while true; do
		sleep 10
		if [ -f "$pool/pool_kill" ]; then
			condor_off -daemon master
			sleep 5
			killall condor_master
			sleep 5
			kill -INT -1
			sleep 1
			kill -KILL -1
		fi
	done
}
