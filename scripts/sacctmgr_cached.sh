#!/bin/bash

# take arguments to minimize repeating of constants
CACHE_TIME=$1
file=$2

# time since last cache update
time_now=$(date +%s)
last_update=$(date +%s -r $file)
time_since=$((time_now-last_update))

if [ "$time_since" -gt "$CACHE_TIME" ]; then
  # update cache and echo results
  sacctmgr -p show -n assoc where user=$USER | cut -d "|" -f 2,4 | tee "$file"
else
  # cache up to date, just read it
  echo "$(cat $file)"
fi

