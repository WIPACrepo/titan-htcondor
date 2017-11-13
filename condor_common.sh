#!/bin/bash
pool=$1

export _CONDOR_LOCAL_DIR=$pool/nodes/$(hostname)
mkdir -p $_CONDOR_LOCAL_DIR
export _CONDOR_NETWORK_INTERFACE="$(ip -4 addr show dev ipogif0 | awk -F '[ /]+' '/inet/{print $3}')"
export _CONDOR_LOCAL_CONFIG_DIR=$pool/config
export _CONDOR_EXECUTE=/tmp/execute
mkdir -p $_CONDOR_EXECUTE
