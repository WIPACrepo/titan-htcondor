#!/bin/bash
set -o errexit
set -o nounset
pool=$(readlink -f $1)

titan-sshd

while ! test -f "$pool/pool_is_ready"; do
	echo Waiting for $pool/pool_is_ready
	sleep 5
done

source $(dirname "${BASH_SOURCE[0]}")/condor-common.sh
condor_setup_common $pool
export _CONDOR_DAEMON_LIST="MASTER STARTD"
export | grep -v 'SSH\|PWD\|SHLVL' > /tmp/env

shutdown_on_pool_kill $pool &

condor_master -f 
