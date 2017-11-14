#!/bin/bash
set -o xtrace; set -o errexit
pool=$(readlink -f $1)
extra_daemons="$2"
set -o nounset

titan-sshd

source $(dirname "${BASH_SOURCE[0]}")/condor-common.sh $pool
ln -T -sf $(hostname) $pool/nodes/cm
echo $_CONDOR_NETWORK_INTERFACE > $pool/cm_addr
mkdir -p $pool/config
cat <<- EOF > $pool/config/00_pool
	CONDOR_HOST=$_CONDOR_NETWORK_INTERFACE
	FILESYSTEM_DOMAIN = titan
	MAX_FILE_DESCRIPTORS = 80000
	COLLECTOR_MAX_FILE_DESCRIPTORS = 80000
	SCHEDD_MAX_FILE_DESCRIPTORS = 80000

	CONDOR_ADMIN = Undefined
	ENABLE_KERNEL_TUNING = False
	ALLOW_DAEMON = *
	HOSTALLOW_ADMINISTRATOR = *
	
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
touch $pool/pool_is_ready

export _CONDOR_HISTORY="$_CONDOR_LOCAL_DIR/history"
export _CONDOR_EVENT_LOG="$_CONDOR_LOCAL_DIR/events"
export _CONDOR_SPOOL="$pool/spool"
mkdir -p $_CONDOR_SPOOL

export _CONDOR_DAEMON_LIST="MASTER SCHEDD COLLECTOR NEGOTIATOR $extra_daemons"
export | grep -v 'SSH\|PWD\|SHLVL' > /tmp/env
set +o xtrace; source $(dirname "${BASH_SOURCE[0]}")/condor-pool-kill.sh $pool; set -o xtrace

condor_master -f
