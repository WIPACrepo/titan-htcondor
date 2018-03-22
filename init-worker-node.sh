#!/bin/bash
set -o errexit
set -o nounset
pool=$(readlink -f $1)

titan-sshd

delay=$((RANDOM % 60))
echo "Delaying $BASH_SOURCE on $(hostname) by $delay seconds"
sleep $delay
while ! test -f "$pool/pool_is_ready"; do
	sleep 10
done

source $(dirname "${BASH_SOURCE[0]}")/common.sh
condor_setup_common $pool
export _CONDOR_DAEMON_LIST="MASTER STARTD"

export TITAN_POOL_DIR=$pool
export | grep -v 'SSH\|PWD\|SHLVL' > /tmp/env
monitor_host $_CONDOR_LOCAL_DIR $pool
shutdown_on_pool_kill $pool 0 &

condor_master -f 
