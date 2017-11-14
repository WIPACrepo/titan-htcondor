#!/bin/bash

source /tmp/env
set -x
condor_q
condor_status
