#!/bin/bash
set -o errexit
set -o nounset
pool=$(readlink -f $1)

titan-sshd

while ! test -f "$pool/pool_is_ready"; do
	echo Waiting for $pool/pool_is_ready
	sleep 5
done
echo Starting condor on $(hostname)

source $(dirname "${BASH_SOURCE[0]}")/common.sh
condor_setup_common $pool
export _CONDOR_STARTD_HISTORY=$_CONDOR_LOCAL_DIR/startd_history
export _CONDOR_DAEMON_LIST="MASTER STARTD"
export | grep -v 'SSH\|PWD\|SHLVL' > /tmp/env
dstat -t --all -p --proc-count -l --mem --swap >> $_CONDOR_LOCAL_DIR/dstat &
nvidia-smi dmon -o DT -s um >> $_CONDOR_LOCAL_DIR/dmon &
ping -i 10 $(<$pool/cm_addr) | awk '{print strftime("[%Y-%m-%d %H:%M:%S]"), $0}' \
														>> $_CONDOR_LOCAL_DIR/ping &
shutdown_on_pool_kill $pool &

condor_master -f 
