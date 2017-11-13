#!/bin/bash
set -o xtrace; set -o errexit; set -o nounset
pool=$(readlink -f $1)

titan-sshd

while ! test -f "$pool/pool_is_ready"; do
	echo Waiting for $pool/pool_is_ready
	sleep 5
done

source $(dirname "${BASH_SOURCE[0]}")/condor_common.sh $pool
export _CONDOR_DAEMON_LIST="MASTER STARTD"
export | grep -v 'SSH\|PWD\|SHLVL' > /tmp/env

set +o xtrace; source $(dirname "${BASH_SOURCE[0]}")/condor_pool_kill.sh $pool; set -o xtrace

condor_master -f 
