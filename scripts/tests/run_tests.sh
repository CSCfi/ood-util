#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# This scripts runs some tests for the scripts that fetch information from Slurm
# basically only smoke testing

ruby -Ilib:${SCRIPT_DIR}/../ ${SCRIPT_DIR}/test_slurm_project_partition.rb
ruby -Ilib:${SCRIPT_DIR}/../ ${SCRIPT_DIR}/test_slurm_limits.rb
ruby -Ilib:${SCRIPT_DIR}/../ ${SCRIPT_DIR}/test_slurm_reservation.rb
