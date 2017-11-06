#!/bin/bash
set -x
pool=$(readlink -f $1)
mode=$2
driver_script=$3

if [[ $mode != 'head' && $mode != 'worker' ]]; then
	echo Invalid mode
	exit 1
fi

titan-sshd

export _CONDOR_LOCAL_DIR=$pool/nodes/$(hostname)
mkdir -p $_CONDOR_LOCAL_DIR
export _CONDOR_NETWORK_INTERFACE="$(ip -4 addr show dev ipogif0 | awk -F '[ /]+' '/inet/{print $3}')"
export _CONDOR_LOCAL_CONFIG_DIR=$pool/config

if [[ $mode == 'head' ]]; then
	ln -T -sf $(hostname) $pool/nodes/cm
	echo $_CONDOR_NETWORK_INTERFACE > $pool/cm_addr
	mkdir -p $pool/config
	cat <<- EOF > $pool/config/00_pool
		CONDOR_HOST=$_CONDOR_NETWORK_INTERFACE
		MAX_FILE_DESCRIPTORS = 80000
		COLLECTOR_MAX_FILE_DESCRIPTORS = 80000
		SCHEDD_MAX_FILE_DESCRIPTORS = 80000

		CONDOR_ADMIN = Undefined
		ENABLE_KERNEL_TUNING = False
		ALLOW_DAEMON = *
		LOG = \$(LOCAL_DIR)
		RUN = \$(LOCAL_DIR)
		LOCK = \$(LOCAL_DIR)

		RUNBENCHMARKS = False
		use feature : GPUs
		GPU_DISCOVERY_EXTRA = -extra
		SLOT_TYPE_1 = auto
		SLOT_TYPE_1_PARTITIONABLE = TRUE
		NUM_SLOTS_TYPE_1 = 1
	EOF

	export _CONDOR_DAEMON_LIST="MASTER SCHEDD COLLECTOR NEGOTIATOR"
	export _CONDOR_HISTORY="$_CONDOR_LOCAL_DIR/history"
	export _CONDOR_EVENT_LOG="$_CONDOR_LOCAL_DIR/events"
	export _CONDOR_SPOOL="$pool/spool"
	mkdir -p $_CONDOR_SPOOL

	export | grep ' _CONDOR_' > $pool/head.env
	condor_master -f &
	sleep 5 # give condor time to start up
	$driver_script
	wait
elif [[ $mode == 'worker' ]]; then
	export _CONDOR_DAEMON_LIST="MASTER STARTD"
	export _CONDOR_EXECUTE=/tmp/execute
	mkdir -p $_CONDOR_EXECUTE
	condor_master -f
fi
