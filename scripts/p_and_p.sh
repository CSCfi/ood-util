#!/bin/bash
SCRIPT_DIR="/appl/opt/ood_util/scripts"

CACHE_TIME=600
# per-user cache
file="/tmp/${USER}_ood_sacctmgr_cache.txt"

# create cache file if it doesn't exist, should probably add error checks
# to make sure it is actually successfully created
if [ ! -f "$file" ]; then
  CACHE_TIME=-1
  touch "$file"
fi

# get the possibly cached sacctmgr output and parse it
sact_res=$(flock -x -w 60 $file $SCRIPT_DIR/sacctmgr_cached.sh $CACHE_TIME $file)
partitions=$(echo "$sact_res" | cut -d "|" -f 1 | sort | uniq |  grep -v "default_no_jobs" )
projects=$(echo "$sact_res" | cut -d "|" -f 2 | sort | uniq | grep -v "^$")
echo "$projects"
echo "@"
echo "$partitions"
