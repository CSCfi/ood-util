#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

ruby -Ilib:${SCRIPT_DIR}/../ ${SCRIPT_DIR}/test_slurm_project_partition.rb
