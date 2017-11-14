#!/bin/bash
source /tmp/env
set -x
cd "$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")"
condor_q
condor_status
condor_run hostname
condor_history
touch $_CONDOR_LOCAL_DIR/../../pool_kill
